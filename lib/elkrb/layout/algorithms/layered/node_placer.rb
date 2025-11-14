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
          def initialize(graph, layers, options = {})
            @graph = graph
            @layers = layers
            @options = options
            @layer_spacing = options[:layer_spacing] || 60.0
            @node_spacing = options[:spacing_node_node] || 20.0
          end

          def place_nodes
            return unless @layers && !@layers.empty?

            # Calculate layer widths
            layer_widths = calculate_layer_widths

            # Calculate y positions for each layer
            y_positions = calculate_layer_y_positions

            # Place nodes in each layer
            @layers.each_with_index do |layer_nodes, layer_index|
              place_layer(layer_nodes, layer_index, layer_widths[layer_index],
                          y_positions[layer_index])
            end
          end

          private

          def calculate_layer_widths
            @layers.map do |layer_nodes|
              return 0 if layer_nodes.empty?

              total_width = layer_nodes.sum { |n| n.width || 0 }
              total_spacing = (layer_nodes.length - 1) * @node_spacing
              total_width + total_spacing
            end
          end

          def calculate_layer_y_positions
            y = 0
            positions = []

            @layers.each do |layer_nodes|
              positions << y
              max_height = layer_nodes.map { |n| n.height || 0 }.max || 0
              y += max_height + @layer_spacing
            end

            positions
          end

          def place_layer(nodes, _layer_index, _layer_width, y_pos)
            return if nodes.empty?

            # Center the layer horizontally
            x = 0

            nodes.each do |node|
              node.x = x
              node.y = y_pos
              x += (node.width || 0) + @node_spacing
            end
          end
        end
      end
    end
  end
end
