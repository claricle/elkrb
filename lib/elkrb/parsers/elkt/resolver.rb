# frozen_string_literal: true

module Elkrb
  module Parsers
    module Elkt
      # Finishes a parsed tree: resolves dotted endpoints and allocates the
      # automatic edge ids.
      #
      # Neither pass can run during the parse. ELKT permits forward references
      # -- five files in ELK's own corpus declare an edge before its nodes --
      # so endpoints resolve only once the whole tree exists. And the tree has
      # already split `children` from `edges`, losing source interleaving, so
      # ids come from `edge_refs`, which the parser appended in document order.
      #
      # @api private
      class Resolver
        def initialize(tree, declared_ids, edge_refs, graph_id = nil)
          @tree = tree
          @declared_ids = declared_ids
          @edge_refs = edge_refs
          @graph_id = graph_id
        end

        def resolve!
          resolve_container(@tree, root_scope)
          assign_edge_ids
          @tree
        end

        private

        # `graph G` names the root, and ELK resolves `G.a.p` through it. Whether
        # a header was written is tracked as its own fact: inferring it from
        # `declared_ids` gave a document containing `node root` a root scope it
        # never declared.
        def root_scope
          return [] unless @graph_id

          [{ @graph_id => [@tree] }]
        end

        # `scopes` is the enclosing chain, innermost first. ELKT binds Xtext's
        # ImportedNamespaceAwareLocalScopeProvider, so a name unresolved in the
        # edge's own container falls outward to the enclosing ones -- while a
        # local match still wins, which is what keeps a repeated id at another
        # level from binding to the wrong node.
        def resolve_container(container, outer)
          scopes = [build_index(container), *outer]
          (container[:edges] || []).each { |edge| resolve_edge(edge, scopes) }
          (container[:children] || []).each do |child|
            resolve_container(child, scopes)
          end
        end

        def resolve_edge(edge, scopes)
          %i[sources targets].each do |key|
            edge[key] = edge[key].map { |ref| resolve_ref(ref, scopes) }
          end
          (edge[:sections] || []).each { |s| resolve_section(s, scopes) }
        end

        # incoming/outgoing are cross-references to ElkConnectableShape, the
        # same as an endpoint; ELK's JsonExporter writes the terminal id.
        def resolve_section(section, scopes)
          %i[incomingShape outgoingShape].each do |key|
            next unless section[key]

            section[key] = resolve_ref(section[key], scopes)
          end
        end

        # An unresolvable reference is kept verbatim rather than collapsed to
        # its head segment, which would silently point the edge at a different,
        # real node.
        def resolve_ref(reference, scopes)
          scopes.each do |index|
            resolved = resolve_in(reference, index)
            return resolved if resolved
          end
          reference
        end

        def resolve_in(reference, index)
          parts = reference.split(".")
          index.fetch(parts.first, []).each do |entry|
            resolved = resolve_path(entry, parts.drop(1))
            return resolved if resolved
          end
          nil
        end

        # Backtracks rather than committing to the first candidate segment.
        # ELK builds a fully qualified name from the containing elements, so a
        # COMPLETE node chain beats a port whose prefix matches but whose path
        # dead-ends. Measured against ELK 0.12.0: with `port b` and
        # `node b { node c }` in one node, `a.b.c` resolves to `c`.
        def resolve_path(node, parts)
          return node[:id] if parts.empty?

          head = parts.first
          rest = parts.drop(1)
          candidates(node, head).each do |entry|
            resolved = resolve_path(entry, rest)
            return resolved if resolved
          end
          nil
        end

        # Children first: a port is a leaf, so it can only ever satisfy the
        # final segment, and preferring it earlier truncates a longer path.
        def candidates(node, name)
          (node[:children] || []).select { |entry| entry[:id] == name } +
            (node[:ports] || []).select { |entry| entry[:id] == name }
        end

        # Every candidate for an id, not one winner: the first segment needs
        # the same backtracking as every later one, so a contested name keeps
        # both the child and the port in play.
        def build_index(container)
          entries = Hash.new { |hash, key| hash[key] = [] }
          (container[:children] || []).each { |c| entries[c[:id]] << c }
          (container[:ports] || []).each { |port| entries[port[:id]] << port }
          entries
        end

        # One graph-wide counter over a taken set seeded with every declared id
        # -- the root graph's own id included -- so an automatic id can collide
        # with neither an explicit edge id nor a node, port, label or section.
        def assign_edge_ids
          taken = @declared_ids.to_h { |id| [id, true] }
          counter = 0
          @edge_refs.each do |edge|
            next if edge[:id]

            counter += 1 while taken.key?("e#{counter}")
            edge[:id] = "e#{counter}"
            taken[edge[:id]] = true
            counter += 1
          end
        end
      end
    end
  end
end
