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
        def initialize(tree, declared_ids, edge_refs)
          @tree = tree
          @declared_ids = declared_ids
          @edge_refs = edge_refs
        end

        def resolve!
          resolve_container(@tree, [])
          assign_edge_ids
          @tree
        end

        private

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
          current = index[parts.first]
          return nil unless current

          parts.drop(1).each do |part|
            current = descend(current, part)
            return nil unless current
          end
          current[:id]
        end

        # A port outranks a child of the same name: an edge endpoint denotes an
        # ElkConnectableShape, and NodeIndex already lets a port keep a
        # contested id.
        def descend(node, name)
          port = (node[:ports] || []).find { |entry| entry[:id] == name }
          return port if port

          (node[:children] || []).find { |entry| entry[:id] == name }
        end

        # Children go in FIRST so a same-id port overwrites one: inserting
        # ports first let a child win the first path segment, inverting the
        # rule `descend` applies to every later segment.
        def build_index(container)
          entries = {}
          (container[:children] || []).each do |child|
            entries[child[:id]] = child
          end
          (container[:ports] || []).each { |port| entries[port[:id]] = port }
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
