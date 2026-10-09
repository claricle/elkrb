# frozen_string_literal: true

module Elkrb
  module Layout
    # java.util.Random's 48-bit linear congruential generator. Java ELK draws
    # its random layouts from it, so the same seed only gives the same
    # numbers here if the generator is the same one.
    class JavaRandom
      MULTIPLIER = 0x5DEECE66D
      ADDEND = 0xB
      MASK = (1 << 48) - 1
      INT_LIMIT = 1 << 31

      def initialize(seed)
        @state = (seed ^ MULTIPLIER) & MASK
      end

      # The top `bits` bits of the next state, as a Java int (bits <= 32).
      def next_bits(bits)
        @state = ((@state * MULTIPLIER) + ADDEND) & MASK
        value = @state >> (48 - bits)
        value >= INT_LIMIT ? value - (1 << 32) : value
      end

      # A float in [0, 1) with 24 random bits, like Random#nextFloat.
      def next_float
        next_bits(24) / 16_777_216.0
      end

      # A double in [0, 1) with 53 random bits, like Random#nextDouble.
      def next_double
        ((next_bits(26) << 27) + next_bits(27)) / 9_007_199_254_740_992.0
      end

      # An integer in [0, bound), like Random#nextInt(bound).
      def next_int(bound)
        raise ArgumentError, "bound must be positive" unless bound.positive?
        return (bound * next_bits(31)) >> 31 if bound.nobits?(bound - 1)

        loop do
          bits = next_bits(31)
          value = bits % bound
          return value if bits - value + (bound - 1) < INT_LIMIT
        end
      end
    end
  end
end
