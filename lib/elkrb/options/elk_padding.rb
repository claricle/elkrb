# frozen_string_literal: true

require_relative "decimal"

module Elkrb
  module Options
    # ElkPadding parser for padding specifications
    #
    # Parses padding strings in the format:
    #   "[left=2, top=3, right=3, bottom=2]"
    class ElkPadding
      attr_reader :left, :top, :right, :bottom

      def initialize(left: 0, top: 0, right: 0, bottom: 0)
        @left = Decimal.to_f(left)
        @top = Decimal.to_f(top)
        @right = Decimal.to_f(right)
        @bottom = Decimal.to_f(bottom)
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
          **%i[left top right bottom].to_h do |side|
            [side, Decimal.component(hash, side, 0)]
          end,
        )
      end

      # Parse from string
      #
      # @param str [String] String like "[left=2, top=3, right=3, bottom=2]"
      # @return [ElkPadding] Parsed padding object
      def self.from_string(str)
        content = str.strip.gsub(/^\[|\]$/, "")
        new(**content.split(",", -1).to_h { |entry| side_and_number(entry) })
      end

      # One "side=number" entry, validated here so a repeated side cannot
      # hide a malformed earlier value; an entry without exactly one '=' is
      # malformed.
      def self.side_and_number(entry)
        key, value, extra = entry.split("=", -1).map(&:strip)
        if extra || !value
          raise ArgumentError, "Invalid padding entry: #{entry.inspect}"
        end

        [key.to_sym, Decimal.to_f(value)]
      end
      private_class_method :side_and_number

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
