# frozen_string_literal: true

module Elkrb
  module Layout
    module Spore
      # Rectangle arithmetic shared by the SPOrE overlap removal phases.
      # Rectangles are anything answering x, y, width and height.
      module Geometry
        FUZZINESS = 0.0001
        DISTANCE_EPSILON = 0.00001

        # Two rectangles seen along one axis.
        Axis = Struct.new(:low_a, :size_a, :low_b, :size_b) do
          # Signed gap between the nearer sides; negative when they overlap.
          def separation
            [low_a - (low_b + size_b), low_b - (low_a + size_a)].max
          end

          # Distance from the far side of one to the near side of the other,
          # the smaller of the two ways round.
          def span_gap
            [(low_a - (low_b + size_b)).abs, (low_a + size_a - low_b).abs].min
          end

          def center_distance
            ((low_a + (size_a / 2.0)) - (low_b + (size_b / 2.0))).abs
          end

          def within_reach?
            center_distance <= (size_a / 2.0) + (size_b / 2.0)
          end

          def coincident?
            center_distance.zero?
          end

          def ratio
            span_gap / center_distance
          end

          def depth
            [low_a + size_a, low_b + size_b].min - [low_a, low_b].max
          end
        end

        module_function

        def distance(from_x, from_y, to_x, to_y)
          dx = from_x - to_x
          dy = from_y - to_y
          Math.sqrt((dx * dx) + (dy * dy))
        end

        # Guava's DoubleMath.fuzzyCompare: 0 when within +tolerance+.
        def fuzzy_compare(left, right, tolerance)
          return 0 if fuzzy_equal?(left, right, tolerance)
          return left <=> right unless left.nan? || right.nan?

          left.nan? ? 1 : -1
        end

        def fuzzy_equal?(left, right, tolerance)
          left == right || (left - right).abs <= tolerance ||
            (left.nan? && right.nan?)
        end

        def axes(first, second)
          [Axis.new(first.x, first.width, second.x, second.width),
           Axis.new(first.y, first.height, second.y, second.height)]
        end

        # The factor by which the line between the two centres must be
        # stretched for the rectangles to just touch (1.0 when they already
        # do not overlap). The centres must differ.
        def overlap(first, second)
          both = axes(first, second)
          return 1.0 unless both.all?(&:within_reach?)

          apart = both.reject(&:coincident?)
          return 0.0 if apart.empty?

          apart.map(&:ratio).min + 1
        end

        # Whether the rectangles share more than rounding noise in both axes.
        def intersect?(first, second)
          axes(first, second).all? { |axis| axis.depth > FUZZINESS }
        end

        # Distance between the closest sides (touching sides: 0), or the
        # negated corner distance when the rectangles overlap.
        def shortest_distance(first, second)
          horizontal, vertical = axes(first, second).map(&:separation)
          h_clear = fuzzy_compare(horizontal, 0.0, DISTANCE_EPSILON)
          v_clear = fuzzy_compare(vertical, 0.0, DISTANCE_EPSILON)
          return [vertical, horizontal].max if (h_clear >= 0) ^ (v_clear >= 0)

          corner = Math.sqrt((vertical * vertical) + (horizontal * horizontal))
          h_clear.positive? ? corner : -corner
        end
      end
    end
  end
end
