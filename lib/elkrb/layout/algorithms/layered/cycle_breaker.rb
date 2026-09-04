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
        # The returned ids are consumed by LayerAssigner to orient the edge
        # only while calculating layers.
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
            reversed = Set.new
            return reversed unless @graph.children

            adjacency = outgoing_edges
            colors = {}

            @graph.children.each do |node|
              next if colors[node.id]

              walk_from(node.id, adjacency, colors, reversed)
            end

            reversed
          end

          private

          def walk_from(root_id, adjacency, colors, reversed)
            colors[root_id] = :active
            stack = [[root_id, 0]]

            until stack.empty?
              current_id, edge_index = stack[-1]
              edges = adjacency[current_id]

              if edge_index >= edges.length
                colors[current_id] = :complete
                stack.pop
                next
              end

              target_id, edge_id = edges[edge_index]
              stack[-1][1] = edge_index + 1
              visit_target(target_id, edge_id, stack, colors, reversed)
            end
          end

          def visit_target(target_id, edge_id, stack, colors, reversed)
            case colors[target_id]
            when :active
              reversed << edge_id
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

                  adjacency[source_id] << [target_id, edge.id]
                end
              end
            end

            adjacency
          end

          def endpoint_owner_ids(endpoints)
            (endpoints || []).filter_map do |id|
              owner = @index.owner(id) if id
              owner&.id
            end.uniq
          end
        end
      end
    end
  end
end
