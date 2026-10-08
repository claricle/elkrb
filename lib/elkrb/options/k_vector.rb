# frozen_string_literal: true

require_relative "decimal"

module Elkrb
  module Options
    # KVector parser for coordinate pairs
    #
    # Parses coordinate strings in the format:
    #   "(23, 43)" or "(23,43)"
    class KVector
      attr_reader :x, :y

      def initialize(x, y)
        @x = Decimal.to_f(x)
        @y = Decimal.to_f(y)
      end

      # Parse KVector from string, hash, or array
      #
      # @param value [String, Hash, Array, KVector] The coordinate specification
      # @return [KVector] Parsed coordinate object
      def self.parse(value)
        return value if value.is_a?(KVector)
        return from_hash(value) if value.is_a?(Hash)
        return from_array(value) if value.is_a?(Array)
        return from_string(value) if value.is_a?(String)

        raise ArgumentError, "Invalid KVector value: #{value.inspect}"
      end

      # Parse from hash
      #
      # @param hash [Hash] Hash with :x and :y keys
      # @return [KVector] Parsed coordinate object
      def self.from_hash(hash)
        new(Decimal.component(hash, :x, 0), Decimal.component(hash, :y, 0))
      end

      # Parse from array
      #
      # @param array [Array] Array with [x, y] values
      # @return [KVector] Parsed coordinate object
      def self.from_array(array)
        raise ArgumentError, "Array must have 2 elements" unless array.size == 2

        new(array[0], array[1])
      end

      # Parse from string
      #
      # @param str [String] String like "(23, 43)" or "(23,43)"
      # @return [KVector] Parsed coordinate object
      def self.from_string(str)
        # Remove parentheses and split by comma
        content = str.strip.gsub(/^\(|\)$/, "")
        parts = content.split(",", -1).map(&:strip)

        unless parts.size == 2
          raise ArgumentError,
                "Invalid KVector format: #{str}"
        end

        new(parts[0], parts[1])
      end

      # Convert to hash
      #
      # @return [Hash] Hash representation
      def to_h
        { x: @x, y: @y }
      end

      # Convert to array
      #
      # @return [Array] Array representation
      def to_a
        [@x, @y]
      end

      # Convert to string
      #
      # @return [String] String representation
      def to_s
        "(#{@x}, #{@y})"
      end

      # Check equality
      #
      # @param other [KVector] Other coordinate object
      # @return [Boolean] True if equal
      def ==(other)
        return false unless other.is_a?(KVector)

        @x == other.x && @y == other.y
      end
    end
  end
end
