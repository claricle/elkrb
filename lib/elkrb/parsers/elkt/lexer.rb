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
        BOM = "\uFEFF"
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

        def initialize(source)
          unless source.is_a?(String)
            raise TypeError,
                  "ELKT source must be a String, got #{source.class}"
          end

          @src = normalize(source)
          @pos = 0
          @line = 1
          @col = 1
          @tokens = []
          @scanners = build_scanners
        end

        def tokenize
          @pos += BOM.length if @src.start_with?(BOM)
          scan_one while @pos < @src.length
          emit(:eof, "", nil)
          @tokens
        end

        private

        # The scan order described above, written out. Keep the string
        # scanner before the two comment scanners.
        def build_scanners
          [
            method(:take_whitespace), method(:take_string),
            method(:take_line_comment), method(:take_block_comment),
            method(:take_arrow), method(:take_number),
            method(:take_identifier), method(:take_pipe),
            method(:take_punctuation)
          ].freeze
        end

        # Skipped by moving @pos alone: a byte-order mark is a zero-width
        # marker, so the first real character is still at column 1. Routing it
        # through `advance` shifted every first-line column by one.
        #
        # ELKT is UTF-8 internally, but a caller may legitimately hand us
        # text tagged with a real, named source encoding (a file read with
        # `File.read(path, encoding: "ISO-8859-1")`, say). That tag carries
        # meaning -- byte 0xE9 in Latin-1 IS "e" with an acute accent -- so
        # it is transcoded via String#encode, not blindly reinterpreted.
        # ASCII-8BIT/BINARY is different: it is Ruby's "no real encoding is
        # known" tag (`File.read(path, "rb")`, or bytes assembled by hand),
        # so there is nothing to transcode FROM -- the historical behavior
        # of reinterpreting those bytes as UTF-8 is kept. A caller handing
        # us bytes read in binary mode, or text that is not valid UTF-8 in
        # whichever of these two ways applies, would otherwise escape the
        # facade's documented ParseError boundary as an
        # Encoding::CompatibilityError or a bare ArgumentError from the
        # first regexp match.
        # UTF-8 and ASCII-8BIT carry no real source encoding to transcode
        # from -- UTF-8 is already the target, and ASCII-8BIT is Ruby's "no
        # encoding is known" tag -- so both are reinterpreted in place.
        # Anything else is a real, named encoding and is converted with
        # String#encode instead, which is what turns a Latin-1 0xE9 into the
        # accented character it actually names rather than a byte sequence
        # that merely happens to be invalid UTF-8.
        NO_SOURCE_ENCODING_TO_TRANSCODE_FROM =
          [Encoding::UTF_8, Encoding::ASCII_8BIT].freeze
        private_constant :NO_SOURCE_ENCODING_TO_TRANSCODE_FROM

        def normalize(text)
          if NO_SOURCE_ENCODING_TO_TRANSCODE_FROM.include?(text.encoding)
            reinterpret(text)
          else
            transcode(text)
          end
        end

        # @return [String] transcoded to UTF-8, or reinterpreted as UTF-8
        #   when the source is invalid in its own declared encoding.
        def transcode(text)
          text.encode(Encoding::UTF_8)
        rescue EncodingError
          reinterpret(text)
        end

        # @return [String] the same bytes, tagged UTF-8.
        # @raise [Elkrb::ParseError] when those bytes are not valid UTF-8.
        def reinterpret(text)
          text = text.dup.force_encoding(Encoding::UTF_8)
          return text if text.valid_encoding?

          line, col = first_invalid_location(text)
          raise Elkrb::ParseError.new(
            "Input is not valid UTF-8 at line #{line}, column #{col}",
            line: line, column: col,
          )
        end

        # Walks up to the first broken character and counts the lines before
        # it. Reporting line 1, column 1 for every file pointed the user at
        # the top even when the bad bytes were far down.
        def first_invalid_location(text)
          line = 1
          col = 1
          previous = nil
          text.each_char do |char|
            return [line, col] unless char.valid_encoding?

            line, col = step_location(char, previous, line, col)
            previous = char
          end
          [line, col]
        end

        # CRLF is one line break, so the LF after a CR must not count again.
        def step_location(char, previous, line, col)
          return [line + 1, 1] if char == "\r" ||
            (char == "\n" && previous != "\r")
          return [line, col] if char == "\n"

          [line, col + 1]
        end

        def scan_one
          return if @scanners.any?(&:call)

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
          emit(:identifier, text, segments.map(&:name).join("."), segments)
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

        # Raw newlines are legal inside an Xtext STRING, and this walks the
        # body one character at a time -- so CRLF has to be consumed as a pair
        # here too, or the two halves reach the counter separately and every
        # later location is a line out.
        def take_string_char
          return advance_with("\r\n") if crlf?(@pos)
          return take_escape if @src[@pos] == "\\"

          advance_with(@src[@pos])
        end

        # The escape branch consumed the backslash and the CR together, which
        # left the LF for the next advance and counted the pair as two lines.
        def take_escape
          nxt = @src[@pos + 1]
          raise_at(@line, @col, "Unterminated escape") if nxt.nil?
          return advance_with("\\\r\n") if crlf?(@pos + 1)

          advance_with("\\#{nxt}")
        end

        def crlf?(pos)
          @src[pos] == "\r" && @src[pos + 1] == "\n"
        end

        def advance_with(text)
          advance(text)
          text
        end

        def build_segments(text)
          text.split(".").map do |segment|
            if segment.start_with?("^")
              Segment.new(name: segment[1..], escaped: true)
            else
              Segment.new(name: segment, escaped: false)
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
