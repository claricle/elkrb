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
    # @example
    #   Elkrb::Parsers::ElktParser.parse("node n1\nnode n2\nedge n1 -> n2\n")
    #   # => {id: "root", layoutOptions: {}, children: [...], edges: [...]}
    #
    # @param input [String] ELKT source
    # @return [Hash] an ELK graph Hash, ready for Graph.from_hash
    # @raise [Elkrb::ParseError] if the input is not valid ELKT
    class ElktParser
      def self.parse(input)
        Elkt::Parser.new(Elkt::Lexer.new(input).tokenize).parse
      end
    end
  end
end
