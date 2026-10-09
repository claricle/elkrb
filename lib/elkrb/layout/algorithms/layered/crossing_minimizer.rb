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
            @input_order = input_order(graph, layers)
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

          def input_order(graph, layers)
            children = graph.children || []
            order = children.each_with_index.to_h do |node, position|
              [node.id, position]
            end
            offset = order.length
            dummy_slots(layers).each do |slot|
              order[slot.id] = offset + slot.edge_order
            end
            order
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
            slots_by_edge = dummy_slots_by_edge
            layer_by_id = layer_indexes
            @index.edges.each do |edge|
              connect_edge_neighbors(
                edge, neighbors, slots_by_edge, layer_by_id
              )
            end
            neighbors
          end

          def connect_edge_neighbors(edge, neighbors, slots_by_edge,
                                     layer_by_id)
            source = endpoint_owner(edge.sources)
            target = endpoint_owner(edge.targets)
            return unless source && target && source != target

            chain = edge_chain(
              source, target, slots_by_edge[edge], layer_by_id
            )
            chain.each_cons(2) do |first, second|
              neighbors[first] << second
              neighbors[second] << first
            end
          end

          def dummy_slots(layers = @layers)
            layers.flatten.select { |item| item.respond_to?(:dummy?) }
          end

          def dummy_slots_by_edge
            slots = {}.compare_by_identity
            dummy_slots.each do |slot|
              (slots[slot.edge] ||= []) << slot
            end
            slots
          end

          def layer_indexes
            @layers.each_with_index.with_object({}) do |(layer, index), map|
              layer.each { |item| map[item.id] = index }
            end
          end

          def edge_chain(source, target, slots, layer_by_id)
            ordered = Array(slots).sort_by(&:layer_index)
            if layer_by_id.fetch(source) > layer_by_id.fetch(target)
              ordered.reverse!
            end
            [source, *ordered.map(&:id), target]
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
