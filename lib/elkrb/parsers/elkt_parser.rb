# frozen_string_literal: true

require_relative "../errors"
require_relative "elkt/token"
require_relative "elkt/lexer"
require_relative "elkt/resolver"
require_relative "elkt/parser"

module Elkrb
  module Parsers
    # Parser for the ELKT (ELK Text) format.
    #
    # Tokenizes, then parses by recursive descent, then resolves endpoints and
    # edge ids. Raises Elkrb::ParseError, carrying a line and column, for input
    # that is not valid ELKT.
    #
    # The returned Hash is the full ELK graph. `Graph.from_hash` reads the
    # parts the models have today: ids, sizes, positions, layout options,
    # children, ports and edges. Root labels, root ports, labels nested inside
    # a label and edge section options are parsed but the models drop them.
    #
    # @example
    #   Elkrb::Parsers::ElktParser.parse("node n1\nnode n2\nedge n1 -> n2\n")
    #   # => {id: "root", layoutOptions: {}, children: [...], edges: [...]}
    #
    # @param input [String] ELKT source
    # @return [Hash] an ELK graph Hash
    # @raise [Elkrb::ParseError] if the input is not valid ELKT
    class ElktParser
      # Kept so old code that rescues ElktParser::ParseError keeps working.
      ParseError = Elkrb::ParseError

      def self.parse(input)
        Elkt::Parser.new(Elkt::Lexer.new(input).tokenize).parse
      end

      # The instance API of the old parser. It is kept so
      # `ElktParser.new(source).parse` still works.
      def initialize(input)
        @input = input
      end

      attr_reader :input

      def parse
        self.class.parse(@input)
      end
    end
  end
end
