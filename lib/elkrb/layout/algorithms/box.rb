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

          aspect_ratio = option("elk.aspectRatio")
          spacing = option("elk.spacing.nodeNode", default: 15.0).to_f
          nodes = graph.children.sort_by do |node|
            (node.width || 0.0) * (node.height || 0.0)
          end
          budget = row_budget(nodes, spacing, aspect_ratio)
          place_rows(nodes, spacing, budget)

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end

        private

        def row_budget(nodes, spacing, aspect_ratio)
          area = nodes.sum do |node|
            ((node.width || 0.0) + spacing) *
              ((node.height || 0.0) + spacing)
          end
          computed = Math.sqrt(area * Math.sqrt(aspect_ratio.to_f))
          pair_width = nodes.first(2).sum { |node| node.width || 0.0 }
          pair_width += spacing if nodes.length > 1
          [computed, pair_width].max
        end

        def place_rows(nodes, spacing, budget)
          x = 0.0
          y = 0.0
          row_height = 0.0

          nodes.each do |node|
            width = node.width || 0.0
            height = node.height || 0.0
            if x.positive? && (x + width) > budget
              x = 0.0
              y += row_height + spacing
              row_height = 0.0
            end

            node.x = x
            node.y = y
            x += width + spacing
            row_height = [row_height, height].max
          end
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
