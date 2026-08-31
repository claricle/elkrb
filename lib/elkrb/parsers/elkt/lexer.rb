# frozen_string_literal: true

require_relative "../../errors"
require_relative "token"

module Elkrb
  module Parsers
    module Elkt
      # Turns ELKT source into a flat Array of Token, ending in :eof.
      #
      # Scan order is load-bearing. Strings are consumed ATOMICALLY before any
      # comment is recognised, so `/*` and `//` inside a label are ordinary
      # characters; the reverse order deletes everything between a label's `/*`
      # and the next real block comment.
      #
      # @api private
      class Lexer
        BOM = "﻿"
        WS = /\G[ \t\r\n]+/.freeze
        # The exponent alternative MUST precede the plain-decimal one: Ruby
        # alternation is ordered, so `\d+\.\d+` first matches "1.5" of
        # "1.5e-3" and leaves "e-3" to lex as an identifier.
        NUMBER = /\G[+-]?(?:\d+(?:\.\d+)?[eE][+-]?\d+|\d+\.\d+|\d+)/.freeze
        IDENT = /\G\^?[A-Za-z_]\w*(?:\.\^?[A-Za-z_]\w*)*/.freeze
        PUNCT = {
          "{" => :lbrace, "}" => :rbrace, "[" => :lbracket,
          "]" => :rbracket, ":" => :colon, "," => :comma, "." => :dot
        }.freeze
        SCANNERS = %i[
          whitespace string line_comment block_comment arrow number
          identifier pipe punctuation
        ].freeze

        def initialize(source)
          @src = source.to_s
          @pos = 0
          @line = 1
          @col = 1
          @tokens = []
        end

        def tokenize
          advance(BOM) if @src.start_with?(BOM)
          scan_one while @pos < @src.length
          emit(:eof, "", nil)
          @tokens
        end

        private

        def scan_one
          SCANNERS.each { |name| return if send(:"try_#{name}") }
          raise_at(@line, @col,
                   "Unexpected character #{@src[@pos].inspect}")
        end

        def try_whitespace
          text = match(WS) or return false

          advance(text)
          true
        end

        def try_line_comment
          return false unless @src[@pos, 2] == "//"

          stop = @src.index("\n", @pos)
          advance(stop ? @src[@pos...stop] : @src[@pos..])
          true
        end

        def try_block_comment
          return false unless @src[@pos, 2] == "/*"

          line = @line
          col = @col
          close = @src.index("*/", @pos + 2)
          raise_at(line, col, "Unterminated block comment") unless close

          advance(@src[@pos...(close + 2)])
          true
        end

        def try_arrow
          return false unless @src[@pos, 2] == "->"

          emit(:arrow, "->", nil)
          true
        end

        def try_number
          text = match(NUMBER) or return false

          emit(:number, text, cast_number(text))
          true
        end

        def try_identifier
          text = match(IDENT) or return false

          segments = build_segments(text)
          emit(:identifier, text, segments.map(&:first).join("."), segments)
          true
        end

        def try_pipe
          return false unless @src[@pos] == "|"

          emit(:pipe, "|", "|")
          true
        end

        def try_punctuation
          type = PUNCT[@src[@pos]] or return false

          emit(type, @src[@pos], @src[@pos])
          true
        end

        # Consumes the whole literal and keeps the RAW inner lexeme: label text
        # and property values decode differently upstream, so decoding belongs
        # at the parse site.
        def try_string
          quote = @src[@pos]
          return false unless ['"', "'"].include?(quote)

          line = @line
          col = @col
          inner = read_string_body(quote, line, col)
          @tokens << Token.new(type: :string, value: inner, segments: nil,
                               line: line, column: col)
          true
        end

        def read_string_body(quote, line, col)
          advance(quote)
          inner = +""
          inner << take_string_char while @pos < @src.length &&
                                         @src[@pos] != quote
          raise_at(line, col, "Unterminated string") if @pos >= @src.length

          advance(quote)
          inner
        end

        def take_string_char
          char = @src[@pos]
          return advance_with(char) unless char == "\\"

          nxt = @src[@pos + 1]
          raise_at(@line, @col, "Unterminated escape") if nxt.nil?

          advance_with(char + nxt)
        end

        def advance_with(text)
          advance(text)
          text
        end

        def build_segments(text)
          text.split(".").map do |segment|
            if segment.start_with?("^")
              [segment[1..], true]
            else
              [segment, false]
            end
          end
        end

        def cast_number(text)
          text.match?(/[.eE]/) ? text.to_f : text.to_i
        end

        def match(regexp)
          regexp.match(@src, @pos)&.[](0)
        end

        def emit(type, text, value, segments = nil)
          @tokens << Token.new(type: type, value: value, segments: segments,
                               line: @line, column: @col)
          advance(text)
        end

        def advance(text)
          newlines = text.count("\n")
          if newlines.zero?
            @col += text.length
          else
            @line += newlines
            @col = text.length - text.rindex("\n")
          end
          @pos += text.length
        end

        def raise_at(line, col, message)
          raise Elkrb::ParseError.new(
            "#{message} at line #{line}, column #{col}",
            line: line, column: col
          )
        end
      end
    end
  end
end
