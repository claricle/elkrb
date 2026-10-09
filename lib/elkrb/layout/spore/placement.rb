# frozen_string_literal: true

require_relative "body"
require_relative "geometry"

module Elkrb
  module Layout
    module Spore
      # Reading nodes into bodies and writing them back, shared by the two
      # SPOrE algorithms. The including algorithm supplies +rng+ and +option+.
      module Placement
        # ELK's own defaults for the SPOrE algorithms; the shared registry
        # values are for the other algorithms.
        DEFAULT_SPACING = 8.0
        DEFAULT_PADDING = {
          left: 8.0, top: 8.0, right: 8.0, bottom: 8.0
        }.freeze

        private

        def padding
          option("elk.padding", default: DEFAULT_PADDING).to_h
        end

        def build_bodies(nodes, spacing)
          seen = {}
          nodes.map do |node|
            body = Body.new(node, spacing)
            body.nudge(rng) while seen.key?(body.origin)
            seen[body.origin] = true
            body
          end
        end

        # The body whose centre is nearest the middle of the graph; the first
        # of equally near ones.
        def most_central(bodies, graph)
          cx, cy = middle(graph)
          bodies.each_with_index.min_by do |body, i|
            [Geometry.distance(body.origin_x, body.origin_y, cx, cy), i]
          end.first
        end

        def middle(graph)
          [graph.x.to_f + (graph.width.to_f / 2.0),
           graph.y.to_f + (graph.height.to_f / 2.0)]
        end

        def place(body)
          node = body.source
          node.x = body.center_x - (node.width.to_f / 2.0)
          node.y = body.center_y - (node.height.to_f / 2.0)
        end
      end
    end
  end
end
