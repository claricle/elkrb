# frozen_string_literal: true

require_relative "bk_node_placer"
require_relative "port_order"
require_relative "orthogonal_router"

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Places nodes within their assigned layers
        #
        # This phase calculates the x and y coordinates for each node
        # based on their layer assignment and spacing requirements.
        class NodePlacer
          # Cross size of a long-edge dummy while nodes are being placed.
          EDGE_THICKNESS = 1.0
          # Gap between a long edge and a node, or another long edge, beside it.
          EDGE_SPACING = 10.0

          attr_writer :index, :port_order, :orthogonal

          # @param layer_spacing [Numeric] gap between consecutive layers
          # @param node_spacing [Numeric] gap between nodes in one layer
          def initialize(_graph, layers, direction: "RIGHT",
                         layer_spacing: 20.0, node_spacing: 20.0)
            @layers = layers
            @direction = direction
            @layer_spacing = layer_spacing
            @node_spacing = node_spacing
          end

          def place_nodes
            return unless @layers && !@layers.empty?

            mark_dummy_slots
            cross = cross_coordinates
            layer_extents = calculate_layer_extents
            layer_positions = calculate_layer_positions(
              layer_extents, gap_widths(cross)
            )

            place_all_layers(layer_positions, cross)
            mirror_layers(layer_positions, layer_extents)
          end

          private

          def size_dummy_slots
            layer_dimension = horizontal? ? :width : :height
            cross_dimension = horizontal? ? :height : :width
            @layers.each do |items|
              size_dummy_layer(items, layer_dimension, cross_dimension)
            end
          end

          def size_dummy_layer(items, layer_dimension, cross_dimension)
            nodes = items.reject { |item| dummy?(item) }
            layer_extent = maximum_size(nodes, layer_dimension)
            cross_extent = maximum_size(nodes, cross_dimension)
            items.select { |item| dummy?(item) }.each do |slot|
              slot.public_send("#{layer_dimension}=", layer_extent)
              slot.public_send("#{cross_dimension}=", cross_extent)
            end
          end

          def maximum_size(nodes, dimension)
            nodes.map { |node| size(node, dimension) }.max || 0
          end

          def dummy?(item)
            item.respond_to?(:dummy?) && item.dummy?
          end

          def place_all_layers(layer_positions, cross)
            @layers.each_with_index do |nodes, layer_index|
              lead = overhang(nodes, :west)
              extent = layer_extent(nodes)
              nodes.each do |node|
                offset = dummy?(node) ? lead : layer_offset(node, nodes, extent)
                place_node(node, layer_positions[layer_index] + offset,
                           cross.fetch(node.id) - dummy_lead(node))
              end
            end
          end

          # Where a node sits across its layer's width: nodes with more
          # outgoing than incoming ports lean toward the far side, so
          # unequal nodes meet their edges on the shared side of the gap.
          # Declared ports stay inside the layer, so the node leans within
          # the room they leave.
          def layer_offset(node, nodes, extent)
            room = extent - overhang(nodes, :west) - overhang(nodes, :east)
            overhang(nodes, :west) +
              ((room - size(node, layer_dimension)) * alignment_ratio(node))
          end

          def alignment_ratio(node)
            outgoing = port_order.visual(node.id, :east).size
            incoming = port_order.visual(node.id, :west).size
            total = outgoing + incoming
            total.zero? ? 0.5 : outgoing.fdiv(total)
          end

          def layer_dimension
            horizontal? ? :width : :height
          end

          def cross_coordinates
            BkNodePlacer.new(
              @layers, @port_order || PortOrder.new(@layers, @index),
              spacing: method(:spacing_between),
              size_of: method(:placed_cross_size),
              port_size_of: ->(port) { port_cross_size(port) }
            ).place
          end

          # A long edge occupies a hairline in its layer; the slot keeps the
          # full layer size so the edge's bend points sit on its centre.
          def placed_cross_size(item)
            dummy?(item) ? EDGE_THICKNESS : cross_size(item)
          end

          def dummy_lead(item)
            return 0.0 unless dummy?(item)

            (cross_size(item) - EDGE_THICKNESS) / 2.0
          end

          def spacing_between(first_id, second_id)
            dummies = [first_id, second_id].count do |id|
              @dummy_ids.include?(id)
            end
            dummies.zero? ? @node_spacing : EDGE_SPACING
          end

          def port_order
            @port_order ||= PortOrder.new(@layers, @index)
          end

          # How far the declared ports of a layer's nodes stick out of the
          # nodes on one side; the layer keeps clear of them.
          def overhang(nodes, side)
            nodes.flat_map { |node| port_order.visual(node.id, side) }
              .filter_map(&:declared)
              .map { |declared| size(declared, horizontal? ? :width : :height) }
              .max || 0
          end

          def mark_dummy_slots
            size_dummy_slots
            dummies = @layers.flatten.select { |item| dummy?(item) }
            @dummy_ids = dummies.to_set(&:id)
          end

          # Width of each gap between two layers. Orthogonal routes need room
          # for one routing slot per parallel run, with a clear margin at both
          # ends; a gap never drops below the layer spacing.
          def gap_widths(cross)
            return [] unless @orthogonal

            router_for(cross).slot_counts.map do |slots|
              next @layer_spacing if slots.zero?

              runs = (slots - 1) * OrthogonalRouter::EDGE_SPACING
              margins = 2 * OrthogonalRouter::EDGE_NODE_SPACING
              width = runs + margins
              [width, @layer_spacing].max
            end
          end

          def router_for(cross)
            OrthogonalRouter.new(
              @layers, port_order, @index,
              direction: @direction,
              measure: OrthogonalRouter::Measure.new(
                start: ->(item) { cross.fetch(item.id) },
                extent: method(:placed_cross_size),
                port: method(:port_cross_size),
              )
            )
          end

          def port_cross_size(port)
            return 0 unless port.declared

            size(port.declared, horizontal? ? :height : :width)
          end

          def calculate_layer_extents
            @layers.map { |nodes| layer_extent(nodes) }
          end

          def layer_extent(nodes)
            widest = nodes.map { |node| size(node, layer_dimension) }.max || 0
            overhang(nodes, :west) + widest + overhang(nodes, :east)
          end

          def calculate_layer_positions(extents, gap_widths = [])
            position = 0
            extents.each_with_index.map do |extent, i|
              position.tap do
                position += extent + gap_widths.fetch(i, @layer_spacing)
              end
            end
          end

          def place_node(node, layer_position, cross_position)
            if horizontal?
              node.x = layer_position
              node.y = cross_position
            else
              node.x = cross_position
              node.y = layer_position
            end
          end

          def mirror_layers(layer_positions, layer_extents)
            return unless %w[LEFT UP].include?(@direction)

            bound = layer_positions.zip(layer_extents)
              .map { |position, extent| position + extent }.max
            coordinate, dimension = mirror_axis

            @layers.flatten.each do |node|
              mirror_node(node, coordinate, dimension, bound)
            end
          end

          def mirror_axis
            @direction == "LEFT" ? %i[x width] : %i[y height]
          end

          def mirror_node(node, coordinate, dimension, bound)
            mirrored = bound - node.public_send(coordinate) -
              size(node, dimension)
            node.public_send("#{coordinate}=", mirrored)
          end

          def horizontal?
            %w[RIGHT LEFT].include?(@direction)
          end

          def cross_size(node)
            size(node, horizontal? ? :height : :width)
          end

          def size(node, dimension)
            node.public_send(dimension) || 0
          end
        end
      end
    end
  end
end
