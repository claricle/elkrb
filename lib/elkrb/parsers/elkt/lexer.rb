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
        WS = /\G[ \t\r\n]+/
        NEWLINE = /\r\n|\r|\n/
        # The exponent alternative MUST precede the plain-decimal one: Ruby
        # alternation is ordered, so `\d+\.\d+` first matches "1.5" of
        # "1.5e-3" and leaves "e-3" to lex as an identifier.
        NUMBER = /\G[+-]?(?:\d+(?:\.\d+)?[eE][+-]?\d+|\d+\.\d+|\d+)/
        IDENT = /\G\^?[A-Za-z_]\w*(?:\.\^?[A-Za-z_]\w*)*/
        PUNCT = {
          "{" => :lbrace, "}" => :rbrace, "[" => :lbracket,
          "]" => :rbracket, ":" => :colon, "," => :comma, "." => :dot
        }.freeze
        SCANNERS = %i[
          whitespace string line_comment block_comment arrow number
          identifier pipe punctuation
        ].freeze

        def initialize(source)
          @src = normalize(source.to_s)
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

        # ELKT is UTF-8. A caller handing us bytes read in binary mode, or text
        # that is not valid UTF-8, would otherwise escape the facade's
        # documented ParseError boundary as an Encoding::CompatibilityError or
        # a bare ArgumentError from the first regexp match.
        def normalize(text)
          unless text.encoding == Encoding::UTF_8
            text = text.dup.force_encoding(Encoding::UTF_8)
          end
          return text if text.valid_encoding?

          raise Elkrb::ParseError.new(
            "Input is not valid UTF-8 at line 1, column 1", line: 1, column: 1
          )
        end

        def scan_one
          SCANNERS.each { |name| return if send(:"take_#{name}") }
          raise_at(@line, @col,
                   "Unexpected character #{@src[@pos].inspect}")
        end

        def take_whitespace
          text = match(WS) or return nil

          advance(text)
          text
        end

        # Xtext's SL_COMMENT is `'//' !('\n'|'\r')*`, so a lone CR ends it too.
        # Stopping only at LF swallowed the rest of a CR-delimited file.
        def take_line_comment
          return unless @src[@pos, 2] == "//"

          stop = @src.index(/[\r\n]/, @pos)
          text = stop ? @src[@pos...stop] : @src[@pos..]
          advance(text)
          text
        end

        def take_block_comment
          return unless @src[@pos, 2] == "/*"

          line = @line
          col = @col
          close = @src.index("*/", @pos + 2)
          raise_at(line, col, "Unterminated block comment") unless close

          text = @src[@pos...(close + 2)]
          advance(text)
          text
        end

        def take_arrow
          return unless @src[@pos, 2] == "->"

          emit(:arrow, "->", nil)
        end

        def take_number
          text = match(NUMBER) or return nil

          emit(:number, text, cast_number(text))
        end

        def take_identifier
          text = match(IDENT) or return nil

          segments = build_segments(text)
          emit(:identifier, text, segments.map(&:first).join("."), segments)
        end

        def take_pipe
          return unless @src[@pos] == "|"

          emit(:pipe, "|", "|")
        end

        def take_punctuation
          type = PUNCT[@src[@pos]] or return nil

          emit(type, @src[@pos], @src[@pos])
        end

        # Consumes the whole literal and keeps the RAW inner lexeme: label text
        # and property values decode differently upstream, so decoding belongs
        # at the parse site.
        def take_string
          quote = @src[@pos]
          return unless ['"', "'"].include?(quote)

          line = @line
          col = @col
          inner = read_string_body(quote, line, col)
          @tokens << Token.new(type: :string, value: inner, segments: nil,
                               line: line, column: col)
          inner
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
          @tokens.last
        end

        # CRLF, lone CR and lone LF each end one line. Counting only LF left
        # every location wrong in the CR-delimited files the comment fix
        # started accepting.
        def advance(text)
          parts = text.split(NEWLINE, -1)
          if parts.length <= 1
            @col += text.length
          else
            @line += parts.length - 1
            @col = parts.last.length + 1
          end
          @pos += text.length
        end

        def raise_at(line, col, message)
          raise Elkrb::ParseError.new(
            "#{message} at line #{line}, column #{col}",
            line: line, column: col,
          )
        end
      end
    end
  end
end
