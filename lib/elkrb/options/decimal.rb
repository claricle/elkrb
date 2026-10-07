# frozen_string_literal: true

module Elkrb
  module Options
    # Reads the numbers inside an option value. String#to_f answers 0.0 for
    # "abc" and for "0x10", which would lay a graph out with zero spacing and
    # no sign anything was wrong, so a string must be plain decimal notation.
    # Float() is not the guard: it also takes "0x10".
    module Decimal
      PATTERN = /\A[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?\z/
      # Ruby 3.3's Float() rejects "5." and "1.e3"; 3.4 accepts them.
      TRAILING_DOT = /\.(?=\D|\z)/
      private_constant :PATTERN, :TRAILING_DOT

      # @param text [String]
      # @return [Float, nil] nil unless text is plain decimal in a readable
      #   encoding
      def self.parse(text)
        return unless text.encoding.ascii_compatible? && text.valid_encoding?

        stripped = text.strip
        Float(stripped.sub(TRAILING_DOT, ".0")) if PATTERN.match?(stripped)
      end

      # @param value [String, Numeric, nil] a number or its text
      # @return [Float]
      # @raise [ArgumentError] when a String is not plain decimal
      def self.to_f(value)
        return value.to_f unless value.is_a?(String)

        parse(value) ||
          raise(ArgumentError, "Invalid number: #{value.inspect}")
      end
    end
  end
end
