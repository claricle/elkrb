# frozen_string_literal: true

require_relative "base_algorithm"

module Elkrb
  module Layout
    module Algorithms
      # Box layout algorithm
      #
      # Arranges nodes in a simple box/grid pattern. Nodes are placed
      # in rows from left to right, top to bottom, with uniform spacing.
      # Useful for simple diagrams and quick visualization.
      class Box < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          # Get configuration
          aspect_ratio = option("aspect_ratio", 1.6).to_f
          spacing = node_spacing

          # Calculate number of columns based on aspect ratio
          num_nodes = graph.children.length
          cols = Math.sqrt(num_nodes * aspect_ratio).ceil
          cols = [cols, 1].max

          # Find maximum node dimensions for uniform grid
          max_width = graph.children.map(&:width).max
          max_height = graph.children.map(&:height).max

          # Position nodes in grid
          graph.children.each_with_index do |node, i|
            row = i / cols
            col = i % cols

            node.x = col * (max_width + spacing)
            node.y = row * (max_height + spacing)
          end

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end
      end
    end
  end
end
