# frozen_string_literal: true

require_relative "point"
require_relative "dimension"

module Elkrb
  module Geometry
    class Rectangle
      attr_accessor :x, :y, :width, :height

      def initialize(x = 0.0, y = 0.0, width = 0.0, height = 0.0)
        @x = x.to_f
        @y = y.to_f
        @width = width.to_f
        @height = height.to_f
      end

      def position
        Point.new(@x, @y)
      end

      def position=(point)
        @x = point.x
        @y = point.y
      end

      def size
        Dimension.new(@width, @height)
      end

      def size=(dimension)
        @width = dimension.width
        @height = dimension.height
      end

      def left
        @x
      end

      def right
        @x + @width
      end

      def top
        @y
      end

      def bottom
        @y + @height
      end

      def center
        Point.new(@x + (@width / 2.0), @y + (@height / 2.0))
      end

      def contains?(point)
        point.x.between?(@x, right) &&
          point.y >= @y && point.y <= bottom
      end

      def intersects?(other)
        !(right < other.left || left > other.right ||
          bottom < other.top || top > other.bottom)
      end

      def area
        @width * @height
      end

      def ==(other)
        return false unless other.is_a?(Rectangle)

        @x == other.x && @y == other.y &&
          @width == other.width && @height == other.height
      end

      def to_h
        { x: @x, y: @y, width: @width, height: @height }
      end

      def to_s
        "(#{@x}, #{@y}, #{@width}x#{@height})"
      end
    end
  end
end
