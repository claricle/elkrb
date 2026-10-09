# frozen_string_literal: true

module Elkrb
  module Layout
    module Polyomino
      # One raster cell, as a rectangle in the plane of the shapes it is
      # tested against. A shape is an Array of [x, y] corners.
      #
      # ELK rasterises a shape to the cells whose border it crosses, or that
      # contain it whole; a cell lying wholly inside a shape is not touched
      # by it. Profile Fill closes that gap.
      class Footprint
        EPSILON = 0.00001
        private_constant :EPSILON

        def initialize(left, top, width, height)
          @left = left
          @top = top
          @width = width
          @height = height
        end

        # The footprint +cols+ cells right and +rows+ cells down.
        def step(cols, rows)
          self.class.new(@left + (cols * @width), @top + (rows * @height),
                         @width, @height)
        end

        # ELK's DCElement#intersects: a border of the cell crosses the shape,
        # or the shape lies strictly inside the cell. Touching does not count.
        def touched_by?(shape)
          return false if shape.size < 2

          crosses_border?(shape) || shape.all? { |point| inside?(point) }
        end

        private

        def crosses_border?(shape)
          shape.zip(shape.rotate).any? do |first, second|
            !(inside?(first) && inside?(second)) &&
              sides.any? { |side| crossing?(side, [first, second]) }
          end
        end

        def inside?(point)
          strictly_between?(point[0], @left, @left + @width) &&
            strictly_between?(point[1], @top, @top + @height)
        end

        def strictly_between?(value, low, high)
          low < value && value < high
        end

        def sides
          right = @left + @width
          bottom = @top + @height
          corners = [[@left, @top], [right, @top],
                     [right, bottom], [@left, bottom]]
          corners.zip(corners.rotate)
        end

        # ELK's ElkMath.intersects(l11, l12, l21, l22): the segments cross
        # at a point interior to both, within EPSILON.
        def crossing?(first, second)
          direction = vector(first)
          other = vector(second)
          det = cross_product(other, direction)
          return false if det.abs <= EPSILON

          delta = difference(first[0], second[0])
          [cross_product(delta, direction), cross_product(delta, other)]
            .all? { |numerator| interior?(numerator / det) }
        end

        def interior?(fraction)
          fraction > EPSILON && fraction < 1 - EPSILON
        end

        def vector(segment)
          difference(segment[1], segment[0])
        end

        def difference(first, second)
          [first[0] - second[0], first[1] - second[1]]
        end

        def cross_product(first, second)
          (first[0] * second[1]) - (first[1] * second[0])
        end
      end
    end
  end
end
