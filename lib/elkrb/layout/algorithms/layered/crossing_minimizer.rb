# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Reorders nodes inside assigned layers using four barycenter sweeps.
        class CrossingMinimizer
          STRATEGY = "elk.layered.crossingMinimization.strategy"
          MODEL_ORDER = "elk.layered.considerModelOrder.strategy"

          def initialize(graph, layers, index, resolver)
            @layers = layers
            @index = index
            @strategy = resolver.get(STRATEGY, graph)
            @preserve_input_order =
              resolver.get(MODEL_ORDER, graph) == "NODES_AND_EDGES"
            @input_order = input_order(graph)
            @neighbors = build_neighbors
          end

          def minimize
            return @layers if @strategy == "NONE"

            2.times do
              sweep_down
              sweep_up
            end
            @layers
          end

          private

          def input_order(graph)
            (graph.children || []).each_with_index.to_h do |node, position|
              [node.id, position]
            end
          end

          def sweep_down
            (1...@layers.length).each do |layer_index|
              reorder(layer_index, layer_index - 1)
            end
          end

          def sweep_up
            (@layers.length - 2).downto(0) do |layer_index|
              reorder(layer_index, layer_index + 1)
            end
          end

          def reorder(layer_index, adjacent_index)
            adjacent_positions = positions(@layers[adjacent_index])
            current_positions = positions(@layers[layer_index])
            @layers[layer_index].sort_by! do |node|
              barycenter = neighbor_barycenter(node.id, adjacent_positions)
              [barycenter || current_positions.fetch(node.id),
               tie_breaker(node)]
            end
          end

          def positions(layer)
            layer.each_with_index.to_h { |node, position| [node.id, position] }
          end

          def neighbor_barycenter(node_id, adjacent_positions)
            values = @neighbors[node_id].filter_map do |id|
              adjacent_positions[id]
            end
            return if values.empty?

            values.sum.to_f / values.length
          end

          def tie_breaker(node)
            if @preserve_input_order
              @input_order.fetch(node.id)
            else
              node.id.to_s
            end
          end

          def build_neighbors
            neighbors = Hash.new { |hash, id| hash[id] = [] }
            @index.edges.each do |edge|
              source = endpoint_owner(edge.sources)
              target = endpoint_owner(edge.targets)
              next unless source && target && source != target

              neighbors[source] << target
              neighbors[target] << source
            end
            neighbors
          end

          def endpoint_owner(endpoints)
            id = (endpoints || []).first
            @index.owner(id)&.id if id
          end
        end
      end
    end
  end
end
