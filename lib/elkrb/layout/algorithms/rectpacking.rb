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

          pack_rectangles(graph.children)

          apply_padding(graph)

          graph
        end

        private

        def pack_rectangles(nodes)
          return if nodes.empty?

          spacing = option("elk.spacing.nodeNode", default: 15.0).to_f
          budget = packing_width(nodes, spacing)
          shelf = new_shelf(0.0)

          nodes.each do |node|
            if shelf[:width].positive? &&
                (shelf[:width] + (node.width || 0.0)) > budget
              shelf = new_shelf(
                shelf[:y] + shelf[:height] + spacing,
              )
            end
            place_on_shelf(node, shelf, spacing)
          end
        end

        def packing_width(nodes, spacing)
          area = nodes.sum do |node|
            ((node.width || 0.0) + (2 * spacing)) *
              ((node.height || 0.0) + (2 * spacing))
          end
          Math.sqrt(area * option("elk.aspectRatio").to_f)
        end

        def new_shelf(y_position)
          { y: y_position, height: 0.0, width: 0.0 }
        end

        def place_on_shelf(node, shelf, spacing)
          # Place node at the end of the current shelf
          node.x = shelf[:width]
          node.y = shelf[:y]

          # Update shelf dimensions
          shelf[:width] += (node.width || 0.0) + spacing
          shelf[:height] = [shelf[:height], node.height || 0.0].max
        end

        def padding
          option(
            "elk.padding",
            default: { left: 15.0, top: 15.0, right: 15.0, bottom: 15.0 },
          ).to_h
        end
      end
    end
  end
end
