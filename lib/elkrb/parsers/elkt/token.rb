# frozen_string_literal: true

module Elkrb
  module Parsers
    module Elkt
      # A single ELKT token.
      #
      # `segments` is populated for `:identifier` only: one `[name, escaped]`
      # pair per dotted segment, carets stripped. `value` is the joined
      # semantic name. Both are needed because ELKT's leading-caret escape is
      # per segment -- `org.eclipse.elk.^port.side` escapes only its fourth --
      # and because a declaration site accepts a single segment only.
      #
      # A `:string` value is the unquoted RAW inner lexeme. Labels and property
      # values decode differently upstream, so decoding happens at the parse
      # site, never here.
      #
      # @api private
      Token = Data.define(:type, :value, :segments, :line, :column) do
        def keyword?(name)
          type == :identifier && value == name && !segments.first[1]
        end

        def single_segment?
          type == :identifier && segments.length == 1
        end

        def to_s
          type == :eof ? "end of input" : value.to_s
        end
      end
    end
  end
end
