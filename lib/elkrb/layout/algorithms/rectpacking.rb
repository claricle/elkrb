# frozen_string_literal: true

require_relative "base_algorithm"

module Elkrb
  module Layout
    module Algorithms
      # Rectangle Packing layout algorithm
      #
      # Efficiently packs rectangular nodes using a shelf-based bin packing approach.
      class RectPacking < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          if graph.children.size == 1
            # Single node at origin
            graph.children.first.x = 0.0
            graph.children.first.y = 0.0
            apply_padding(graph)
            return graph
          end

          # Pack rectangles using shelf algorithm
          pack_rectangles(graph.children)

          apply_padding(graph)

          graph
        end

        private

        def pack_rectangles(nodes)
          return if nodes.empty?

          spacing = node_spacing

          # Sort nodes by height (tallest first) for better packing
          sorted_nodes = nodes.sort_by { |n| -n.height }

          # Initialize first shelf
          shelves = []
          current_shelf = {
            y: 0.0,
            height: 0.0,
            width: 0.0,
            nodes: [],
          }

          sorted_nodes.each do |node|
            # Try to fit on current shelf
            unless can_fit_on_shelf?(node, current_shelf, spacing)
              # Start a new shelf
              shelves << current_shelf unless current_shelf[:nodes].empty?

              current_shelf = {
                y: shelves.empty? ? 0.0 : shelves.last[:y] + shelves.last[:height] + spacing,
                height: node.height,
                width: 0.0,
                nodes: [],
              }

            end
            place_on_shelf(node, current_shelf, spacing)
          end

          # Add the last shelf
          shelves << current_shelf unless current_shelf[:nodes].empty?
        end

        def can_fit_on_shelf?(node, shelf, _spacing)
          # First node always fits
          return true if shelf[:nodes].empty?

          # Check if adding this node would make the shelf too tall
          # (we want relatively uniform shelf heights)
          shelf[:height] >= node.height * 0.8
        end

        def place_on_shelf(node, shelf, spacing)
          # Place node at the end of the current shelf
          node.x = shelf[:width]
          node.y = shelf[:y]

          # Update shelf dimensions
          shelf[:nodes] << node
          shelf[:width] += node.width + spacing
          shelf[:height] = [shelf[:height], node.height].max
        end
      end
    end
  end
end
