# frozen_string_literal: true

require_relative "base_algorithm"

module Elkrb
  module Layout
    module Algorithms
      # Fixed layout algorithm
      #
      # Keeps nodes at their current positions and calculates graph dimensions
      # without translating them.
      # Useful when node positions are pre-determined or manually set.
      class Fixed < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          graph.children.each { |node| apply_position(node) }

          size_graph(graph)

          graph
        end

        private

        def apply_position(node)
          position = resolver.get("elk.position", node, default: nil)
          node.x = position ? position.x : (node.x || 0.0)
          node.y = position ? position.y : (node.y || 0.0)
        end

        def size_graph(graph)
          pad = padding
          graph.width = max_right(graph) + horizontal_padding(pad)
          graph.height = max_bottom(graph) + vertical_padding(pad)
        end

        def max_right(graph)
          graph.children.map { |node| right_edge(node) }.max
        end

        def max_bottom(graph)
          graph.children.map { |node| bottom_edge(node) }.max
        end

        def right_edge(node)
          node.x + (node.width || 0.0)
        end

        def bottom_edge(node)
          node.y + (node.height || 0.0)
        end

        def horizontal_padding(pad)
          pad[:left] + pad[:right]
        end

        def vertical_padding(pad)
          pad[:top] + pad[:bottom]
        end

        def padding
          option(
            "elk.padding",
            default: { left: 15.0, top: 15.0, right: 15.0, bottom: 15.0 },
          ).to_h
        end

        # Fixed layout preserves routes. It only applies explicitly declared
        # bend points and records the containing graph.
        def apply_edge_routing(graph)
          (graph.edges || []).each do |edge|
            bends = resolver.get("elk.bendPoints", edge, default: nil)
            apply_bends(edge, bends) if bends
            edge.container = graph.id
          end
        end

        def apply_bends(edge, bends)
          edge.sections ||= []
          section = edge.sections.first || Graph::EdgeSection.new(
            id: "#{edge.id}_s0",
          )
          section.bend_points = bends.vectors.map do |point|
            Geometry::Point.new(x: point.x, y: point.y)
          end
          edge.sections = [section]
        end
      end
    end
  end
end
