# frozen_string_literal: true

require "lutaml/model"

module Elkrb
  module Geometry
    class Point < Lutaml::Model::Serializable
      attribute :x, :float, default: -> { 0.0 }
      attribute :y, :float, default: -> { 0.0 }

      key_value do
        map "x", to: :x
        map "y", to: :y
      end

      yaml do
        map "x", to: :x
        map "y", to: :y
      end

      # The explicit zeros matter: a lutaml default is not marked as set and so
      # would not be rendered, making a bare Point serialize to {} instead of
      # {"x":0.0,"y":0.0}.
      def initialize(**attributes)
        attributes.empty? ? super(x: 0.0, y: 0.0) : super
      end

      def +(other)
        Point.new(x: @x + other.x, y: @y + other.y)
      end

      def -(other)
        Point.new(x: @x - other.x, y: @y - other.y)
      end

      def *(other)
        Point.new(x: @x * other, y: @y * other)
      end

      def /(other)
        Point.new(x: @x / other, y: @y / other)
      end

      def distance_to(other)
        Math.sqrt(((@x - other.x)**2) + ((@y - other.y)**2))
      end

      def ==(other)
        return false unless other.is_a?(Point)

        @x == other.x && @y == other.y
      end

      def to_h
        { x: @x, y: @y }
      end

      def to_s
        "(#{@x}, #{@y})"
      end
    end
  end
end
