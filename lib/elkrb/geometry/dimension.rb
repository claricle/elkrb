# frozen_string_literal: true

module Elkrb
  module Geometry
    class Dimension
      attr_accessor :width, :height

      def initialize(width = 0.0, height = 0.0)
        @width = width.to_f
        @height = height.to_f
      end

      def area
        @width * @height
      end

      def ==(other)
        return false unless other.is_a?(Dimension)

        @width == other.width && @height == other.height
      end

      def to_h
        { width: @width, height: @height }
      end

      def to_s
        "#{@width}x#{@height}"
      end
    end
  end
end
