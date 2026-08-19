# frozen_string_literal: true

require_relative "k_vector"

module Elkrb
  module Options
    # KVectorChain parser for coordinate chains
    #
    # Parses coordinate chain strings in the format:
    #   "( {1,2}, {3,4} )" or "({1,2},{3,4})"
    class KVectorChain
      attr_reader :vectors

      def initialize(vectors = [])
        @vectors = vectors.map { |v| KVector.parse(v) }
      end

      # Parse KVectorChain from string or array
      #
      # @param value [String, Array, KVectorChain] The coordinate chain
      # @return [KVectorChain] Parsed coordinate chain object
      def self.parse(value)
        return value if value.is_a?(KVectorChain)
        return from_array(value) if value.is_a?(Array)
        return from_string(value) if value.is_a?(String)

        raise ArgumentError, "Invalid KVectorChain value: #{value.inspect}"
      end

      # Parse from array
      #
      # @param array [Array] Array of coordinate pairs or KVectors
      # @return [KVectorChain] Parsed coordinate chain object
      def self.from_array(array)
        new(array)
      end

      # Parse from string
      #
      # Mirrors ELK's own KVectorChain parser: split on any run of comma,
      # semicolon, and bracket/brace/paren characters (plus whitespace),
      # then group the resulting numeric tokens into pairs. Accepts every
      # bracket style elkrb previously emitted as well as ELK's own
      # canonical "(x,y; x,y)" output.
      #
      # @param str [String] e.g. "(1,2; 3,4)", "({1,2},{3,4})", "(1,2),(3,4)"
      # @return [KVectorChain] Parsed coordinate chain object
      def self.from_string(str)
        tokens = str.split(/[,;()\[\]{}\s]+/).reject(&:empty?)

        if tokens.size.odd?
          raise ArgumentError, "Invalid KVectorChain format: #{str}"
        end

        vectors = tokens.each_slice(2).map { |x, y| KVector.new(x, y) }
        new(vectors)
      end

      # Add a vector to the chain
      #
      # @param vector [KVector, Array, Hash] Vector to add
      # @return [KVectorChain] Self for chaining
      def add(vector)
        @vectors << KVector.parse(vector)
        self
      end
      alias << add

      # Get vector at index
      #
      # @param index [Integer] Index of vector
      # @return [KVector] Vector at index
      def [](index)
        @vectors[index]
      end

      # Number of vectors in chain
      #
      # @return [Integer] Count of vectors
      def size
        @vectors.size
      end
      alias length size

      # Check if chain is empty
      #
      # @return [Boolean] True if empty
      def empty?
        @vectors.empty?
      end

      # Iterate over vectors
      #
      # @yield [KVector] Each vector in chain
      def each(&)
        @vectors.each(&)
      end

      # Convert to array
      #
      # @return [Array<KVector>] Array of vectors
      def to_a
        @vectors.dup
      end

      # Convert to string
      #
      # @return [String] String representation
      def to_s
        return "()" if @vectors.empty?

        vector_strs = @vectors.map { |v| "{#{v.x}, #{v.y}}" }
        "( #{vector_strs.join(', ')} )"
      end

      # Check equality
      #
      # @param other [KVectorChain] Other coordinate chain
      # @return [Boolean] True if equal
      def ==(other)
        return false unless other.is_a?(KVectorChain)

        @vectors == other.vectors
      end
    end
  end
end
