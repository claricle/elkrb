# frozen_string_literal: true

# This file is loadable on its own, so do not rely on another algorithm
# having loaded Ruby's Set first.
# rubocop:disable Lint/RedundantRequireStatement
require "set"
# rubocop:enable Lint/RedundantRequireStatement

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Finds back edges without changing the graph supplied by the caller.
        # The returned EDGES are consumed by LayerAssigner to orient each one
        # only while calculating layers.
        #
        # The set holds the edge OBJECTS and compares by identity, not their
        # ids. An id is optional on an edge, so keying by id gave every
        # id-less edge in the graph the same handle: reverse one of them and
        # LayerAssigner reversed all of them. Identity is the only handle
        # every edge has. A PLAIN Set is not enough either -- lutaml-model
        # gives these classes VALUE equality, so two distinct edges whose
        # attributes ALL match, id and endpoints alike, are `==`, hash
        # alike, and collapse into one entry. Differing ids are enough to
        # keep them apart in a plain Set; two anonymous parallel edges are
        # not.
        #
        # `outgoing_edges` still walks every source against every target,
        # even though LayeredAlgorithm#validate_simple_edge! now rejects any
        # edge that isn't exactly one source and one target before this class
        # is ever constructed -- so today that cross product is always over
        # arrays of length 0 or 1. Kept general on purpose, unlike
        # LayerAssigner#endpoint_owner_id (singular, .first-based): this
        # class is unit-tested directly with hyperedge-shaped input
        # (cycle_breaker_spec.rb), and narrowing it to the current caller's
        # guarantee would make it correct only through that one caller.
        class CycleBreaker
          def initialize(graph, index)
            @graph = graph
            @index = index
          end

          def break_cycles
            reversed = Set.new.compare_by_identity
            return reversed unless @graph.children

            adjacency = outgoing_edges
            colors = {}

            @graph.children.each do |node|
              # keep this `colors[node.id]` truthiness check, even though
              # `colors.key?(node.id)` reads identically: every value ever
              # stored in `colors` is `:active` or `:complete`, both
              # truthy, and nothing ever stores a falsy value under a key
              # -- so "has a value" and "has a truthy value" can never
              # diverge for this hash. Confirmed by hand: swapping in
              # `colors.key?(node.id)` leaves the whole suite green.
              next if colors[node.id]

              walk_from(node.id, adjacency, colors, reversed)
            end

            reversed
          end

          private

          # Every mutant mutant finds in this method is equivalent, confirmed
          # by hand (each one individually applied, whole suite still
          # green) -- they all fall into two classes:
          #   - `stack[-1]`, `edges[edge_index]`: `Array#[]` with a single
          #     Integer index reads identically to `#at` and, since the
          #     `if` just above always holds `edge_index` in bounds before
          #     either line runs, identically to `#fetch` too.
          #   - `edge_index >= edges.length`, `next`, and the exact
          #     `:complete` symbol: `edge_index` only ever grows by
          #     `frame[1] = edge_index + 1` and is re-checked every pass
          #     before it can grow again, so it can equal `edges.length`
          #     but never exceed it -- making `>=`, `==`, `eql?` and
          #     `equal?` the same test here, and `colors` is a local
          #     consumed only by `== :active` / nil checks (never a
          #     specific "is it :complete" check, never read outside this
          #     method), so renaming that value or falling through `next`
          #     onto a redundant `edges[edge_index]` read changes nothing
          #     reachable from `reversed`, the one value this method hands
          #     back out.
          def walk_from(root_id, adjacency, colors, reversed)
            colors[root_id] = :active
            stack = [[root_id, 0]]

            until stack.empty?
              frame = stack[-1]
              current_id, edge_index = frame
              edges = adjacency[current_id]

              if edge_index >= edges.length
                colors[current_id] = :complete
                stack.pop
                next
              end

              target_id, edge = edges[edge_index]
              frame[1] = edge_index + 1
              visit_target(target_id, edge, stack, colors, reversed)
            end
          end

          def visit_target(target_id, edge, stack, colors, reversed)
            case colors[target_id]
            when :active
              reversed << edge
            when nil
              colors[target_id] = :active
              stack << [target_id, 0]
            end
          end

          def outgoing_edges
            adjacency = Hash.new { |hash, id| hash[id] = [] }

            @index.edges.each do |edge|
              source_ids = endpoint_owner_ids(edge.sources)
              target_ids = endpoint_owner_ids(edge.targets)

              source_ids.each do |source_id|
                target_ids.each do |target_id|
                  next if source_id == target_id

                  adjacency[source_id] << [target_id, edge]
                end
              end
            end

            adjacency
          end

          def endpoint_owner_ids(endpoints)
            (endpoints || []).filter_map do |id|
              # keep the `if id` guard even though `@index.owner(nil)` is
              # itself nil-safe (NodeIndex#owner is `node(id) ||
              # @owners_by_descendant_id[id]`, and a Hash lookup of a nil
              # key that was never stored just answers nil) -- so for the
              # one falsy id this array can ever hold, skipping the call
              # and calling it unconditionally land on the identical nil.
              # Confirmed by hand: forcing this branch to always run
              # leaves the whole suite green.
              owner = @index.owner(id) if id
              owner&.id
            end.uniq
          end
        end
      end
    end
  end
end
