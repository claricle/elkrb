# frozen_string_literal: true

module Elkrb
  module Geometry
    class Vector
      attr_accessor :x, :y

      def initialize(x = 0.0, y = 0.0)
        @x = x.to_f
        @y = y.to_f
      end

      def +(other)
        Vector.new(@x + other.x, @y + other.y)
      end

      def -(other)
        Vector.new(@x - other.x, @y - other.y)
      end

      def *(other)
        Vector.new(@x * other, @y * other)
      end

      def /(other)
        Vector.new(@x / other, @y / other)
      end

      def magnitude
        Math.sqrt((@x**2) + (@y**2))
      end

      def normalize
        mag = magnitude
        return Vector.new(0, 0) if mag.zero?

        Vector.new(@x / mag, @y / mag)
      end

      def dot(other)
        (@x * other.x) + (@y * other.y)
      end

      def perpendicular
        Vector.new(-@y, @x)
      end

      def angle
        Math.atan2(@y, @x)
      end

      def ==(other)
        return false unless other.is_a?(Vector)

        @x == other.x && @y == other.y
      end

      def to_h
        { x: @x, y: @y }
      end

      def to_s
        "<#{@x}, #{@y}>"
      end
    end
  end
end
