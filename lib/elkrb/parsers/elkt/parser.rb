# frozen_string_literal: true

require_relative "../../errors"
require_relative "lexer"
require_relative "resolver"

module Elkrb
  module Parsers
    module Elkt
      # Recursive-descent parser over the Lexer's token array.
      #
      # Nesting is token-driven, never line-driven: a block is entered on a
      # `{` wherever it appears. Each container admits only what its own Xtext
      # production admits -- a label or port body holds labels, not nodes.
      #
      # @api private
      class Parser
        # Every keyword in ElkGraph.xtext. An unescaped occurrence of one is
        # not a legal ID, which is why ELK's own corpus writes `^port.side`
        # and `^position` 700 times over and bare `port:` zero times.
        KEYWORDS = %w[
          graph node port label edge layout section position size
          start end bends incoming outgoing true false null
        ].freeze
        MEMBERS = { "node" => :parse_node, "port" => :parse_port,
                    "label" => :parse_label, "edge" => :parse_edge }.freeze
        GEOMETRY = %w[incoming outgoing start end].freeze
        LITERALS = { "true" => true, "false" => false,
                     "null" => nil }.freeze
        ESCAPES = { "\\" => "\\", '"' => '"', "'" => "'", "n" => "\n",
                    "t" => "\t", "r" => "\r", "b" => "\b",
                    "f" => "\f" }.freeze

        def initialize(tokens)
          @tokens = tokens
          @pos = 0
          @declared_ids = []
          @edge_refs = []
          @graph_id = nil
        end

        def parse
          tree = parse_root
          Resolver.new(tree, @declared_ids, @edge_refs, @graph_id).resolve!
          tree
        end

        private

        def parse_root
          root = { id: "root", layoutOptions: {}, children: [], edges: [] }
          root[:id] = parse_graph_header if keyword?("graph")
          parse_shape_layout(root) if keyword?("layout")
          parse_properties(root)
          parse_members(root, %w[node port label edge])
          expect_eof
          root
        end

        def parse_graph_header
          advance
          @graph_id = single_id
        end

        def parse_members(container, allowed)
          until %i[rbrace eof].include?(peek.type)
            name = allowed.find { |key| peek.keyword?(key) }
            raise_at(peek, "expected #{allowed.join(', ')}") unless name

            send(MEMBERS.fetch(name), container)
          end
        end

        def parse_body(container, allowed)
          expect(:lbrace)
          parse_shape_layout(container) if keyword?("layout")
          parse_properties(container)
          parse_members(container, allowed)
          expect(:rbrace)
        end

        def parse_node(container)
          advance
          node = { id: single_id, width: 40, height: 40, layoutOptions: {} }
          (container[:children] ||= []) << node
          parse_body(node, %w[node port label edge]) if brace?
        end

        def parse_port(container)
          advance
          port = { id: single_id, layoutOptions: {} }
          (container[:ports] ||= []) << port
          parse_body(port, %w[label]) if brace?
        end

        def parse_label(container)
          advance
          id = optional_prefix_id
          token = peek
          text = decode_label(expect(:string), token)
          label = { text: text, width: text.length * 7.0, height: 14.0 }
          label[:id] = id if id
          (container[:labels] ||= []) << label
          parse_body(label, %w[label]) if brace?
        end

        def parse_edge(container)
          advance
          edge = { id: optional_prefix_id }
          edge[:sources] = parse_endpoints
          expect(:arrow)
          edge[:targets] = parse_endpoints
          (container[:edges] ||= []) << edge
          @edge_refs << edge
          parse_edge_body(edge) if brace?
        end

        def parse_edge_body(edge)
          expect(:lbrace)
          parse_edge_layout(edge) if keyword?("layout")
          parse_properties(edge)
          parse_members(edge, %w[label])
          expect(:rbrace)
        end

        # `^section` is not the keyword, so an escaped one falls through to the
        # unnamed single section and is read as one of its properties.
        def parse_edge_layout(edge)
          advance
          expect(:lbracket)
          if keyword?("section")
            parse_section(edge) while keyword?("section")
          else
            (edge[:sections] ||= []) << parse_section_body({})
          end
          expect(:rbracket)
        end

        def parse_section(edge)
          advance
          section = { id: single_id }
          parse_outgoing_refs if peek.type == :arrow
          expect(:lbracket)
          parse_section_body(section)
          expect(:rbracket)
          (edge[:sections] ||= []) << section
        end

        def parse_outgoing_refs
          advance
          single_id(record: false)
          single_id(record: false) while consume?(:comma)
        end

        # Ordered phases, matching ElkGraph.xtext: an unordered geometry group
        # with each member at most once, then at most one bends clause, then
        # properties. Geometry after bends is malformed.
        def parse_section_body(section)
          seen = []
          parse_geometry(section, seen) while geometry?
          parse_bends(section) if keyword?("bends")
          parse_properties(section)
          section
        end

        def geometry?
          GEOMETRY.any? { |key| peek.keyword?(key) }
        end

        def parse_geometry(section, seen)
          name = GEOMETRY.find { |key| peek.keyword?(key) }
          raise_at(peek, "duplicate #{name}") if seen.include?(name)

          seen << name
          advance
          expect(:colon)
          assign_geometry(section, name)
        end

        def assign_geometry(section, name)
          case name
          when "incoming" then section[:incomingShape] = qualified_id
          when "outgoing" then section[:outgoingShape] = qualified_id
          when "start" then section[:startPoint] = point
          else section[:endPoint] = point
          end
        end

        def parse_bends(section)
          advance
          expect(:colon)
          points = [point]
          points << point while consume?(:pipe)
          section[:bendPoints] = points
        end

        # ElkGraph.xtext types Number as EDouble, so `position: 1, 2` is
        # 1.0, 2.0 -- not Integer, whatever the source spelling.
        def point
          x = expect(:number).to_f
          expect(:comma)
          { x: x, y: expect(:number).to_f }
        end

        # `position` and `size` are an Xtext unordered group: either order,
        # each at most once, and both applied -- never one or the other.
        def parse_shape_layout(container)
          advance
          expect(:lbracket)
          seen = []
          parse_shape_member(container, seen) while peek.type != :rbracket
          expect(:rbracket)
        end

        def parse_shape_member(container, seen)
          name = %w[position size].find { |key| peek.keyword?(key) }
          raise_at(peek, "expected position or size") unless name
          raise_at(peek, "duplicate #{name}") if seen.include?(name)

          seen << name
          advance
          expect(:colon)
          assign_shape(container, name)
        end

        def assign_shape(container, name)
          pair = point
          if name == "position"
            container[:x] = pair[:x]
            container[:y] = pair[:y]
          else
            container[:width] = pair[:x]
            container[:height] = pair[:y]
          end
        end

        def parse_properties(container)
          parse_property(container) while property?
        end

        def property?
          peek.type == :identifier && peek(1).type == :colon
        end

        def parse_property(container)
          token = expect_identifier
          expect(:colon)
          (container[:layoutOptions] ||= {})[token.value] = parse_value
        end

        def parse_value
          case peek.type
          when :string, :number then advance.value
          when :identifier then identifier_value
          else raise_at(peek, "expected a value")
          end
        end

        def identifier_value
          token = peek
          return LITERALS.fetch(token.value).tap { advance } if literal?(token)

          qualified_id
        end

        def literal?(token)
          token.single_segment? && LITERALS.key?(token.value) &&
            !token.segments.first[1]
        end

        def parse_endpoints
          list = [qualified_id]
          list << qualified_id while consume?(:comma)
          list
        end

        # QualifiedId carries no hidden() override, so whitespace between
        # segments is legal here -- unlike a property key, where maximal munch
        # already guarantees one token.
        def qualified_id
          parts = [expect_identifier.value]
          parts << expect_identifier.value while consume?(:dot)
          parts.join(".")
        end

        def optional_prefix_id
          return nil unless property?

          id = single_id
          expect(:colon)
          id
        end

        def single_id(record: true)
          token = expect_identifier
          raise_at(token, "expected a single identifier") unless
            token.single_segment?

          @declared_ids << token.value if record
          token.value
        end

        # A surrogate pair is matched as ONE unit, before the single-unit
        # alternative: decoding `\uD83D` and `\uDE00` separately packs two
        # lone surrogates and yields a String that is not valid UTF-8.
        def decode_label(raw, token)
          raw.gsub(/\\(u[dD][89abAB]\h{2}\\u[dD][c-fC-F]\h{2}|u\h{4}|.)/m) do
            decode_escape(Regexp.last_match(1), token)
          end
        end

        # Xtext's STRINGValueConverter rejects an unknown escape outright; the
        # bare character is only the recovery value on its exception.
        def decode_escape(sequence, token)
          return decode_surrogate_pair(sequence) if sequence.length == 11
          return decode_code_unit(sequence) if sequence.length == 5

          ESCAPES.fetch(sequence) do
            raise_at(token, "invalid escape \\#{sequence} in label text")
          end
        end

        def decode_surrogate_pair(sequence)
          high = sequence[1, 4].hex
          low = sequence[7, 4].hex
          [0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)].pack("U")
        end

        # An unpaired surrogate is accepted: ELK emits the single UTF-16 code
        # unit with no diagnostic, so raising here rejected valid input --
        # exactly the failure this rewrite exists to remove. Ruby packs it to
        # CESU-8 bytes, giving a String that is not valid UTF-8, so anything
        # serializing it downstream must expect that.
        def decode_code_unit(sequence)
          [sequence[1..].hex].pack("U")
        end

        def expect_identifier
          token = peek
          raise_at(token, "expected an identifier") unless
            token.type == :identifier

          validate_segments(token)
          advance
        end

        def validate_segments(token)
          token.segments.each do |name, escaped|
            next if escaped || !KEYWORDS.include?(name)

            raise_at(token,
                     "`#{name}` is a reserved keyword; write `^#{name}`")
          end
        end

        def keyword?(name)
          peek.keyword?(name)
        end

        def brace?
          peek.type == :lbrace
        end

        def peek(offset = 0)
          @tokens[@pos + offset] || @tokens.last
        end

        def advance
          token = peek
          @pos += 1
          token
        end

        def consume?(type)
          return false unless peek.type == type

          advance
          true
        end

        def expect(type)
          token = peek
          raise_at(token, "expected #{type}") unless token.type == type

          advance
          token.value
        end

        def expect_eof
          raise_at(peek, "unexpected `#{peek}`") unless peek.type == :eof
        end

        def raise_at(token, message)
          raise Elkrb::ParseError.new(
            "#{message} at line #{token.line}, column #{token.column}",
            line: token.line, column: token.column,
          )
        end
      end
    end
  end
end
