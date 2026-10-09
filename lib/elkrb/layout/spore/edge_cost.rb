# frozen_string_literal: true

require_relative "gap"
require_relative "geometry"

module Elkrb
  module Layout
    module Spore
      # The cost of a spanning-tree edge between two bodies, by the names ELK
      # gives its cost functions. Costs read the bodies' positions from
      # before the pass moved anything.
      module EdgeCost
        NAMES = %w[CENTER_DISTANCE CIRCLE_UNDERLAP RECTANGLE_UNDERLAP
                   INVERTED_OVERLAP MINIMUM_ROOT_DISTANCE].freeze

        module_function

        # @param name [String] one of NAMES
        # @param root [Body] the body the tree grows from
        # @return [Proc] takes two bodies, returns their edge's cost
        def for(name, root)
          case name
          when "CENTER_DISTANCE" then method(:center_distance)
          when "CIRCLE_UNDERLAP" then method(:circle_underlap)
          when "RECTANGLE_UNDERLAP" then Gap.method(:underlap)
          when "INVERTED_OVERLAP" then method(:inverted_overlap)
          when "MINIMUM_ROOT_DISTANCE" then root_distance(root)
          else raise ArgumentError, "unknown cost function #{name.inspect}"
          end
        end

        def center_distance(first, second)
          Geometry.distance(first.origin_x, first.origin_y,
                            second.origin_x, second.origin_y)
        end

        # The distance between the circles around the two rectangles, each
        # reaching from its centre to its top left corner.
        def circle_underlap(first, second)
          center_distance(first, second) - reach(first) - reach(second)
        end

        def reach(body)
          Geometry.distance(body.origin_x, body.origin_y, body.x, body.y)
        end

        def root_distance(root)
          lambda do |first, second|
            [first, second].map do |body|
              Geometry.distance(body.origin_x, body.origin_y,
                                root.center_x, root.center_y)
            end.min
          end
        end

        # Negative and growing with the overlap when the rectangles overlap,
        # so the most overlapped pairs join the tree first.
        def inverted_overlap(first, second)
          distance = Geometry.shortest_distance(first, second)
          return distance if distance >= 0

          between = Geometry.distance(first.center_x, first.center_y,
                                      second.center_x, second.center_y)
          -(Geometry.overlap(first, second) - 1) * between
        end
      end
    end
  end
end
