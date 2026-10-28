# frozen_string_literal: true

require_relative "geometry"
require_relative "rays"

module Elkrb
  module Layout
    module Spore
      # How far apart two bodies' rectangles are, in the three senses the
      # tree compaction needs.
      module Gap
        # Corner pairs that make up a rectangle's four sides, indexing
        # [top left, bottom left, top right, bottom right].
        EDGE_CORNERS = [[0, 2], [0, 1], [3, 2], [3, 1]].freeze

        module_function

        # How far the rectangles can be pushed together along the line
        # between their centres before they touch (0 when their reach
        # overlaps on both axes).
        def underlap(first, second)
          axes = Geometry.axes(first, second)
          scale = axes.map { |axis| reach_scale(axis) }.min
          centres = Math.sqrt(axes.sum { |axis| axis.center_distance**2 })
          (1 - scale) * centres
        end

        # 1 when the rectangles' reach overlaps on this axis, else the share
        # of the centre distance left once they touch.
        def reach_scale(axis)
          axis.within_reach? ? 1 : 1 - axis.ratio
        end

        # Whether the rectangles share a point, give or take rounding noise.
        def touch?(first, second)
          Geometry.axes(first, second).all? do |axis|
            Geometry.fuzzy_compare(axis.separation, 0.0,
                                   Geometry::FUZZINESS) <= 0
          end
        end

        # Whether first's side lies exactly on second's, on the side that a
        # push along +direction+ would drive them into each other.
        def pressed?(first, second, direction)
          Geometry.axes(first, second).zip(direction).any? do |axis, push|
            pressed_on?(axis, push)
          end
        end

        def pressed_on?(axis, push)
          (push.negative? && flush?(axis.low_b, axis.low_a + axis.size_a)) ||
            (push.positive? && flush?(axis.low_b + axis.size_b, axis.low_a))
        end

        def flush?(left, right)
          Geometry.fuzzy_compare(left, right, Geometry::FUZZINESS).zero?
        end

        # How far +second+ can move along +direction+ before it hits +first+
        # (Infinity when it never does).
        def distance(first, second, direction)
          edges(first).product(edges(second)).map do |one, other|
            Rays.distance(*one, *other, direction)
          end.min
        end

        def edges(body)
          xs = [body.x, body.x + body.width]
          ys = [body.y, body.y + body.height]
          corners = xs.product(ys)
          EDGE_CORNERS.map { |from, to| [corners[from], corners[to]] }
        end
      end
    end
  end
end
