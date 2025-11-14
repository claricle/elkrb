# frozen_string_literal: true

module Elkrb
  module Options
    # ElkPadding parser for padding specifications
    #
    # Parses padding strings in the format:
    #   "[left=2, top=3, right=3, bottom=2]"
    class ElkPadding
      attr_reader :left, :top, :right, :bottom

      def initialize(left: 0, top: 0, right: 0, bottom: 0)
        @left = left.to_f
        @top = top.to_f
        @right = right.to_f
        @bottom = bottom.to_f
      end

      # Parse padding from string or hash
      #
      # @param value [String, Hash, ElkPadding] The padding specification
      # @return [ElkPadding] Parsed padding object
      def self.parse(value)
        return value if value.is_a?(ElkPadding)
        return from_hash(value) if value.is_a?(Hash)
        return from_string(value) if value.is_a?(String)

        raise ArgumentError, "Invalid padding value: #{value.inspect}"
      end

      # Parse from hash
      #
      # @param hash [Hash] Hash with :left, :top, :right, :bottom keys
      # @return [ElkPadding] Parsed padding object
      def self.from_hash(hash)
        new(
          left: hash[:left] || hash["left"] || 0,
          top: hash[:top] || hash["top"] || 0,
          right: hash[:right] || hash["right"] || 0,
          bottom: hash[:bottom] || hash["bottom"] || 0,
        )
      end

      # Parse from string
      #
      # @param str [String] String like "[left=2, top=3, right=3, bottom=2]"
      # @return [ElkPadding] Parsed padding object
      def self.from_string(str)
        # Remove brackets and split by comma
        content = str.strip.gsub(/^\[|\]$/, "")
        parts = {}

        content.split(",").each do |part|
          key, value = part.split("=").map(&:strip)
          parts[key.to_sym] = value.to_f
        end

        new(**parts)
      end

      # Convert to hash
      #
      # @return [Hash] Hash representation
      def to_h
        {
          left: @left,
          top: @top,
          right: @right,
          bottom: @bottom,
        }
      end

      # Convert to string
      #
      # @return [String] String representation
      def to_s
        "[left=#{@left}, top=#{@top}, right=#{@right}, bottom=#{@bottom}]"
      end

      # Check equality
      #
      # @param other [ElkPadding] Other padding object
      # @return [Boolean] True if equal
      def ==(other)
        return false unless other.is_a?(ElkPadding)

        @left == other.left &&
          @top == other.top &&
          @right == other.right &&
          @bottom == other.bottom
      end
    end
  end
end
