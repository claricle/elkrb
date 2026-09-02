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
        # Assigns nodes to layers using an iterative longest-path pass.
        class LayerAssigner
          attr_reader :layers

          def initialize(graph, index, reversed_edge_ids = Set.new)
            @graph = graph
            @index = index
            @reversed_edge_ids = reversed_edge_ids
            @layers = []
            @node_layers = {}
          end

          def assign_layers
            return [] unless @graph.children

            nodes = @graph.children.to_h { |node| [node.id, node] }
            predecessors = build_predecessors(nodes)
            assign_predecessor_layers(nodes, predecessors)
            build_layers(nodes)
          end

          def get_layer(node_id)
            @node_layers[node_id]
          end

          private

          # Keep the predecessor order used by the former recursive pass.
          # That order is observable in NodePlacer's same-layer coordinates,
          # so an acyclic graph must not be reordered as a side effect of the
          # iterative implementation.
          def build_predecessors(nodes)
            predecessors = Hash.new { |hash, id| hash[id] = [] }

            @index.edges.each do |edge|
              source_id, target_id = oriented_endpoints(edge)
              next unless usable_edge?(source_id, target_id, nodes)

              predecessors[target_id] << source_id
            end

            predecessors
          end

          # Iterative post-order traversal of each node's predecessors. This
          # is the stack-safe equivalent of the original memoised recursive
          # longest-path calculation and preserves its insertion order.
          def assign_predecessor_layers(nodes, predecessors)
            @node_layers = {}
            colors = {}

            nodes.each_key do |node_id|
              next if @node_layers.key?(node_id)

              walk_predecessors(node_id, predecessors, colors)
            end
          end

          def walk_predecessors(root_id, predecessors, colors)
            colors[root_id] = :active
            stack = [[root_id, 0]]

            until stack.empty?
              step_predecessor_stack(stack, predecessors, colors)
            end
          end

          def step_predecessor_stack(stack, predecessors, colors)
            current_id, predecessor_index = stack[-1]
            incoming = predecessors[current_id]

            if predecessor_index >= incoming.length
              finish_predecessor_frame(stack, current_id, incoming, colors)
              return
            end

            predecessor_id = incoming[predecessor_index]
            stack[-1][1] = predecessor_index + 1
            return if predecessor_assigned?(predecessor_id, colors)

            colors[predecessor_id] = :active
            stack << [predecessor_id, 0]
          end

          def finish_predecessor_frame(stack, node_id, incoming, colors)
            assign_layer(node_id, incoming)
            colors[node_id] = :complete
            stack.pop
          end

          # CycleBreaker orients every back edge away from the active DFS
          # path. Keep this guard defensive for direct callers of
          # LayerAssigner that provide an incomplete reversal set.
          def predecessor_assigned?(predecessor_id, colors)
            @node_layers.key?(predecessor_id) ||
              colors[predecessor_id] == :active
          end

          def assign_layer(node_id, incoming)
            max_predecessor_layer = incoming.filter_map do |predecessor_id|
              @node_layers[predecessor_id]
            end.max

            @node_layers[node_id] =
              if max_predecessor_layer
                max_predecessor_layer + 1
              else
                0
              end
          end

          def build_layers(nodes)
            max_layer = @node_layers.values.max || 0
            @layers = Array.new(max_layer + 1) { [] }
            @node_layers.each do |node_id, layer|
              @layers[layer] << nodes[node_id]
            end

            @layers
          end

          def usable_edge?(source_id, target_id, nodes)
            source_id && target_id && source_id != target_id &&
              nodes.key?(source_id) && nodes.key?(target_id)
          end

          def oriented_endpoints(edge)
            source_id = endpoint_owner_id(edge.sources)
            target_id = endpoint_owner_id(edge.targets)
            return [nil, nil] unless source_id && target_id

            if @reversed_edge_ids.include?(edge.id)
              [target_id, source_id]
            else
              [source_id, target_id]
            end
          end

          def endpoint_owner_id(endpoints)
            id = (endpoints || []).first
            owner = @index.owner(id) if id
            owner&.id
          end
        end
      end
    end
  end
end
