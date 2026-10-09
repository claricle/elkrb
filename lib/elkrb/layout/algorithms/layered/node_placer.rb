# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Places nodes within their assigned layers
        #
        # This phase calculates the x and y coordinates for each node
        # based on their layer assignment and spacing requirements.
        class NodePlacer
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

            cross_extents = calculate_directional_cross_extents
            layer_extents = calculate_layer_extents
            layer_positions = calculate_layer_positions(layer_extents)

            place_all_layers(cross_extents, layer_positions)
            mirror_layers(layer_positions, layer_extents)
          end

          private

          def calculate_layer_widths
            calculate_cross_extents(:width)
          end

          def calculate_layer_heights
            calculate_cross_extents(:height)
          end

          def calculate_directional_cross_extents
            horizontal? ? calculate_layer_heights : calculate_layer_widths
          end

          def calculate_cross_extents(dimension)
            @layers.map do |nodes|
              next 0 if nodes.empty?

              gaps = (nodes.length - 1) * @node_spacing
              nodes.sum { |node| size(node, dimension) } + gaps
            end
          end

          def place_all_layers(cross_extents, layer_positions)
            max_cross_extent = cross_extents.max || 0
            @layers.each_with_index do |layer_nodes, layer_index|
              cross_offset =
                (max_cross_extent - cross_extents[layer_index]) / 2.0
              place_layer(layer_nodes, layer_positions[layer_index],
                          cross_offset)
            end
          end

          def calculate_layer_extents
            dimension = horizontal? ? :width : :height
            @layers.map do |nodes|
              nodes.map { |node| size(node, dimension) }.max || 0
            end
          end

          def calculate_layer_positions(extents)
            position = 0
            extents.map do |extent|
              position.tap { position += extent + @layer_spacing }
            end
          end

          def place_layer(nodes, layer_position, cross_position)
            nodes.each do |node|
              place_node(node, layer_position, cross_position)
              cross_position += cross_size(node) + @node_spacing
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
