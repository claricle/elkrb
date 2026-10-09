# frozen_string_literal: true

require_relative "port_order"

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Reorders nodes inside assigned layers with barycenter sweeps, the
        # way ELK's layer sweep does: a forward sweep, then backward sweeps
        # alternating while the crossing count keeps falling.
        #
        # A node's barycenter is the mean rank of the ports its edges meet
        # in the fixed layer, so two edges leaving one node pull their
        # targets apart. Each sweep also reorders the ports of the layer it
        # moves; #port_order carries the result to the node placer.
        class CrossingMinimizer
          STRATEGY = "elk.layered.crossingMinimization.strategy"
          MODEL_ORDER = "elk.layered.considerModelOrder.strategy"

          # @return [PortOrder] the port lists as the last sweep left them
          attr_reader :port_order

          def initialize(graph, layers, index, resolver)
            @layers = layers
            @strategy = resolver.get(STRATEGY, graph)
            @preserve_input_order =
              resolver.get(MODEL_ORDER, graph) == "NODES_AND_EDGES"
            @input_order = input_order(graph, layers)
            @port_order = PortOrder.new(layers, index)
          end

          def minimize
            return @layers if @strategy == "NONE"

            sweep_until_stable
            @layers
          end

          private

          def sweep_until_stable
            forward = true
            crossings = sweep_and_count(forward)
            loop do
              previous = crossings
              forward = !forward
              crossings = sweep_and_count(forward)
              break unless previous > crossings && crossings.positive?
            end
          end

          def sweep_and_count(forward)
            sweep(forward)
            count_crossings
          end

          def input_order(graph, layers)
            order = (graph.children || []).each_with_index
              .to_h { |node, position| [node.id, position] }
            layers.flatten.select { |item| item.respond_to?(:edge_order) }
              .each { |slot| order[slot.id] = order.length + slot.edge_order }
            order
          end

          def sweep(forward)
            if forward
              (1...@layers.length).each { |i| reorder(i, i - 1) }
            else
              (@layers.length - 2).downto(0) { |i| reorder(i, i + 1) }
            end
          end

          def reorder(layer_index, fixed_index)
            forward = fixed_index < layer_index
            free_side = forward ? :west : :east
            ranks = port_ranks(@layers[fixed_index], forward ? :east : :west)
            layer = @layers[layer_index]
            sort_ports(layer, free_side, ranks)
            layer.replace(sorted(layer, free_side, ranks))
          end

          def sort_ports(layer, side, ranks)
            layer.each do |item|
              @port_order.sort!(item.id, side) do |port|
                port_key(port, side, ranks)
              end
            end
          end

          # Model order keeps the WEST ports of a node in the order of the
          # nodes they come from; the stored WEST list runs bottom to top.
          def port_key(port, side, ranks)
            if @preserve_input_order && side == :west
              -port.others.map { |other| @input_order.fetch(other.item_id) }.min
            else
              mean(port.others.map { |other| ranks.fetch(other) })
            end
          end

          # Rank of every port on one side of a layer, counted top to bottom
          # across the whole layer.
          def port_ranks(layer, side)
            ranks = {}.compare_by_identity
            layer.each do |item|
              @port_order.visual(item.id, side).each do |port|
                ranks[port] = ranks.length
              end
            end
            ranks
          end

          def mean(values)
            values.sum.to_f / values.length
          end

          def sorted(layer, side, ranks)
            keys = fill_unknown(layer.map do |item|
              barycenter(item, side, ranks)
            end)
            layer.each_with_index.sort_by do |item, position|
              known, value = keys[position]
              [value, known ? 0 : 1, known ? tie_breaker(item) : position]
            end.map(&:first)
          end

          def barycenter(item, side, ranks)
            others = @port_order.visual(item.id, side)
              .flat_map(&:others)
            mean(others.map { |other| ranks.fetch(other) }) unless others.empty?
          end

          # A node with no edge toward the fixed layer takes the barycenter
          # of the node before it, so it keeps its place.
          def fill_unknown(values)
            lead = values.compact.first || 0.0
            last = nil
            values.map do |value|
              last = value if value
              [!value.nil?, value || last || lead]
            end
          end

          def tie_breaker(node)
            if @preserve_input_order
              @input_order.fetch(node.id)
            else
              node.id.to_s
            end
          end

          def count_crossings
            positions = layer_positions
            visual = visual_indexes
            gaps = @port_order.segments.group_by do |segment|
              positions.fetch(segment.from_port.item_id).first
            end
            gaps.values.sum do |segments|
              crossings_in(slot_pairs(segments, positions, visual))
            end
          end

          def slot_pairs(segments, positions, visual)
            segments.map do |segment|
              [slot(segment.from_port, positions, visual),
               slot(segment.to_port, positions, visual)]
            end
          end

          def crossings_in(pairs)
            pairs.combination(2).count do |(a1, b1), (a2, b2)|
              (a1 <=> a2) * (b1 <=> b2) == -1
            end
          end

          def slot(port, positions, visual)
            [positions.fetch(port.item_id).last, visual.fetch(port)]
          end

          def layer_positions
            @layers.each_with_index.with_object({}) do |(layer, number), map|
              layer.each_with_index do |item, position|
                map[item.id] = [number, position]
              end
            end
          end

          def visual_indexes
            indexes = {}.compare_by_identity
            @layers.flatten.each do |item|
              PortOrder::SIDES.each do |side|
                @port_order.visual(item.id, side).each_with_index do |port, i|
                  indexes[port] = i
                end
              end
            end
            indexes
          end
        end
      end
    end
  end
end
