# frozen_string_literal: true

require_relative "base_algorithm"

module Elkrb
  module Layout
    module Algorithms
      # Radial layout algorithm
      #
      # Arranges nodes in a circular/radial pattern around a center point.
      class Radial < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          if graph.children.size == 1
            # Single node - place at origin
            graph.children.first.x = 0.0
            graph.children.first.y = 0.0
            apply_padding(graph)
            return graph
          end

          # Calculate radius based on node count and sizes
          radius = calculate_radius(graph.children)

          # Calculate center point
          center_x = radius
          center_y = radius

          # Arrange nodes in a circle
          angle_step = (2 * Math::PI) / graph.children.size

          graph.children.each_with_index do |node, index|
            angle = index * angle_step

            # Calculate position on circle
            # Adjust for node size to center the node
            node.x = center_x + (radius * Math.cos(angle)) - (node.width / 2.0)
            node.y = center_y + (radius * Math.sin(angle)) - (node.height / 2.0)
          end

          apply_padding(graph)

          graph
        end

        private

        def calculate_radius(nodes)
          # Base radius on number of nodes and their average size
          avg_width = nodes.sum(&:width) / nodes.size.to_f
          avg_height = nodes.sum(&:height) / nodes.size.to_f
          avg_size = (avg_width + avg_height) / 2.0

          # Ensure enough space for all nodes
          min_radius = (nodes.size * avg_size) / (2 * Math::PI)

          # Add some extra spacing
          [min_radius * 1.2, 100.0].max
        end
      end
    end
  end
end
