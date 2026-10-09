# frozen_string_literal: true

module Elkrb
  module Layout
    module Spore
      # Distance between two line segments measured along a direction, by
      # tracing rays from each segment's end points onto the other. Points
      # and vectors are [x, y] pairs of floats.
      module Rays
        # How close two points must be to count as the same end point.
        END_POINT_TOLERANCE = 0.05

        module_function

        # @return [Float] the distance from segment b to segment a along
        #   +direction+, or from a to b along its opposite, whichever is
        #   smaller; Infinity when neither reaches
        def distance(a_from, a_to, b_from, b_to, direction)
          [trace(a_from, a_to, b_from, b_to, direction),
           trace(b_from, b_to, a_from, a_to, negate(direction))].min
        end

        def trace(a_from, a_to, b_from, b_to, direction)
          a_span = minus(a_to, a_from)
          grazing = grazing_ray?([a_from, a_to], [b_from, b_to], direction)
          hits = [b_from, b_to].map do |origin|
            [origin, crossing(a_from, a_span, origin, direction)]
          end
          shortest(a_from, a_to, hits, grazing)
        end

        # One ray lands exactly on an end point of a while the shifted
        # segment crosses a elsewhere, so the other ray's miss is not a miss.
        def grazing_ray?(segment_a, segment_b, direction)
          a_from, a_to = segment_a
          b_from, b_to = segment_b
          shifted = crossing(a_from, minus(a_to, a_from),
                             plus(b_from, direction), minus(b_to, b_from))
          !shifted.nil? && !near?(shifted, a_from) && !near?(shifted, a_to)
        end

        # The first ray that lands on an end point of a is dropped, but lets
        # the second one through.
        def shortest(a_from, a_to, hits, grazing)
          forgiven = grazing
          hits.filter_map do |origin, point|
            next unless point

            if near?(point, a_from) != near?(point, a_to) && !forgiven
              forgiven = true
              next
            end
            length(minus(point, origin))
          end.min || Float::INFINITY
        end

        # Where the segments p + t*r and q + u*s meet (0 <= t, u <= 1), the
        # point of the collinear overlap nearest the middle of the second
        # when they overlap along a line, or nil.
        def crossing(p_from, r_span, q_from, s_span)
          offset = minus(q_from, p_from)
          return transversal(p_from, r_span, offset, s_span) unless
            cross(r_span, s_span).zero?

          return unless cross(offset, r_span).zero?

          collinear(p_from, r_span, q_from, s_span)
        end

        def transversal(p_from, r_span, offset, s_span)
          r_cross_s = cross(r_span, s_span)
          t = cross(offset, s_span) / r_cross_s
          u = cross(offset, r_span) / r_cross_s
          plus(p_from, scale(r_span, t)) if t.between?(0, 1) && u.between?(0, 1)
        end

        def collinear(p_from, r_span, q_from, s_span)
          middle = plus(q_from, scale(s_span, 0.5))
          near_start = length(minus(p_from, middle))
          p_to = plus(p_from, r_span)
          near_end = length(minus(p_to, middle))
          reach = length(s_span) * 0.5
          return p_from if near_start < near_end && near_start <= reach

          p_to if near_end <= reach
        end

        def near?(first, second)
          (first[0] - second[0]).abs <= END_POINT_TOLERANCE &&
            (first[1] - second[1]).abs <= END_POINT_TOLERANCE
        end

        def minus(first, second)
          [first[0] - second[0], first[1] - second[1]]
        end

        def plus(first, second)
          [first[0] + second[0], first[1] + second[1]]
        end

        def scale(vector, factor)
          [vector[0] * factor, vector[1] * factor]
        end

        def negate(vector)
          [-vector[0], -vector[1]]
        end

        def cross(first, second)
          (first[0] * second[1]) - (first[1] * second[0])
        end

        def length(vector)
          Math.sqrt((vector[0] * vector[0]) + (vector[1] * vector[1]))
        end
      end
    end
  end
end
