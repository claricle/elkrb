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
            successors, indegrees = build_topology(nodes)
            @node_layers = nodes.keys.to_h { |id| [id, 0] }
            assign_topological_layers(successors, indegrees)
            build_layers(nodes)
          end

          def get_layer(node_id)
            @node_layers[node_id]
          end

          private

          def build_topology(nodes)
            successors = Hash.new { |hash, id| hash[id] = [] }
            indegrees = nodes.to_h { |id, _node| [id, 0] }

            @index.edges.each do |edge|
              source_id, target_id = oriented_endpoints(edge)
              next unless usable_edge?(source_id, target_id, nodes)

              successors[source_id] << target_id
              indegrees[target_id] += 1
            end

            [successors, indegrees]
          end

          def assign_topological_layers(successors, indegrees)
            queue = indegrees.select { |_id, degree| degree.zero? }.keys
            queue_index = 0

            while queue_index < queue.length
              source_id = queue[queue_index]
              queue_index += 1

              successors[source_id].each do |target_id|
                advance_layer(source_id, target_id)
                indegrees[target_id] -= 1
                queue << target_id if indegrees[target_id].zero?
              end
            end
          end

          def advance_layer(source_id, target_id)
            @node_layers[target_id] = [
              @node_layers[target_id], @node_layers[source_id] + 1
            ].max
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
