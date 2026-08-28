# frozen_string_literal: true

require "yaml"

module Elkrb
  # @api private
  #
  # Shared "sniff JSON/YAML, fall back to ELKT" input-format detection for
  # Cli#read_input_file and the convert/diagram/validate commands'
  # detect_and_parse. One tested home for logic all four call sites need
  # identical, instead of four private methods that can quietly drift (as
  # happened when the empty-graph guard needed a matching fix on the
  # from_json/from_yaml side: lutaml-model 0.8.19 succeeds on any YAML/JSON
  # mapping, even one with no recognized keys, returning a graph with every
  # field nil -- silent "success" on garbage is exactly the bug this slice
  # exists to kill).
  module FormatSniffer
    BYTE_ORDER_MARK = "\xEF\xBB\xBF".b.freeze
    private_constant :BYTE_ORDER_MARK

    UNPARSEABLE =
      "Unable to parse input file. Supported formats: JSON, YAML, ELKT"
    private_constant :UNPARSEABLE

    DOT_UNSUPPORTED =
      "DOT format input not yet supported. Use JSON, YAML, or ELKT."
    private_constant :DOT_UNSUPPORTED

    NIL_WHEN_HOLLOW = %i[id x y width height layout_options].freeze
    private_constant :NIL_WHEN_HOLLOW

    BLANK_WHEN_HOLLOW = %i[children edges properties].freeze
    private_constant :BLANK_WHEN_HOLLOW

    class << self
      # The single entry point every command reads input through. Extension
      # dispatch plus shape validation lived in four places and drifted apart;
      # a guard added to one silently left the other three open.
      #
      # The two paths raise differently, by design. A named JSON/YAML
      # extension hands lutaml-model the content directly, so a document it
      # cannot tokenize surfaces lutaml's own parse error, which names the
      # offending token, and a document Psych declines to load surfaces
      # Psych's own refusal. Only the sniffed path normalizes to UNPARSEABLE.
      #
      # The byte order mark comes off here rather than per branch, because
      # every branch needs it gone and neither named branch stripped it.
      # `.json` was the loud half: lutaml hands the leading U+FEFF straight
      # to the JSON parser, which rejects the document. `.yml`/`.yaml` was
      # the quiet and more dangerous one -- Psych loads a marked document
      # and silently drops every key after the first, so a marked graph laid
      # out as an empty graph and the CLI exited 0. String#strip does NOT
      # remove a BOM, so it is no substitute.
      #
      # @param content [String] raw file content
      # @param extension [String] the file's downcased extension
      # @return [Elkrb::Graph::Graph, Hash] the parsed graph
      # @raise [Lutaml::Model::InvalidFormatError] when .json/.yml/.yaml
      #   content will not parse as that format
      # @raise [Psych::Exception] when .yml/.yaml content is valid YAML that
      #   Psych's safe loader refuses -- a !ruby/object tag
      #   (Psych::DisallowedClass) or an alias (Psych::AliasesNotEnabled)
      # @raise [ArgumentError] for .dot/.gv, for a parsed-but-unusable
      #   JSON/YAML model, and for ELKT or sniffed content that yields nothing
      def read(content, extension)
        require_relative "graph/graph"

        text = strip_byte_order_mark(content)

        case extension
        when ".json", ".yml", ".yaml" then read_model(text, extension)
        when ".elkt" then parse_elkt(text)
        when ".dot", ".gv" then raise ArgumentError, DOT_UNSUPPORTED
        else parse(text)
        end
      end

      private

      # The mark is the three bytes EF BB BF, so it comes off by byte rather
      # than by character. String#delete_prefix compares CHARACTERS, and a
      # UTF-8 literal raises Encoding::CompatibilityError against a receiver
      # in another encoding that holds any non-ASCII byte -- File.read tags
      # content with Encoding.default_external, which the locale sets.
      #
      # @return [String] the content without its mark, in its own encoding
      def strip_byte_order_mark(content)
        return content unless content.byteslice(0, 3).b == BYTE_ORDER_MARK

        content.byteslice(3..)
      end

      # @param content [String] raw file content
      # @return [Elkrb::Graph::Graph, Hash] a parsed graph model, or an ELKT
      #   hash
      # @raise [ArgumentError] when neither JSON/YAML nor ELKT yields real
      #   content
      # lutaml-model normalizes only the errors in its own
      # format_error_types list, measured at runtime as
      # Psych::SyntaxError, JSON::ParserError, NoMethodError,
      # Lutaml::Model::TypeError, ArgumentError, Moxml::ParseError,
      # Nokogiri::XML::SyntaxError. Psych's safe-load REFUSALS are not in
      # it, so a !ruby/object tag (Psych::DisallowedClass) or an alias
      # (Psych::AliasesNotEnabled) arrives here unconverted. Those are valid
      # YAML we decline to load, not "maybe this is ELKT" -- letting them fall
      # through would hand the text to the ELKT parser, which reads
      # `foo: 1` as layout option elk.foo and exits 0 on it. Normalize
      # here instead, so the caller sees the same message as any other
      # unreadable input.
      def parse(content)
        sniff(content) || parse_elkt_or_fail(content)
      rescue Psych::Exception
        raise ArgumentError, UNPARSEABLE
      end

      # JSON and YAML differ only in the deserializer; both then need the same
      # shape check.
      #
      # @raise [ArgumentError] when the document parses to an unusable model
      def read_model(content, extension)
        model = if extension == ".json"
                  Elkrb::Graph::Graph.from_json(content)
                else
                  Elkrb::Graph::Graph.from_yaml(content)
                end

        validate_model!(model)
      end

      # A file whose extension names the format skips sniffing, so it also
      # skips the malformed-shape check the sniffer applies. Both paths need
      # it: lutaml coerces a mapping where a sequence belongs into one
      # nil-filled model, and every downstream reader then breaks on it.
      #
      # @raise [ArgumentError] when the parsed model is not usable
      def validate_model!(graph)
        unless graph.is_a?(Elkrb::Graph::Graph) && !malformed_model?(graph)
          raise ArgumentError, UNPARSEABLE
        end

        graph
      end

      def parse_elkt(content)
        graph = parse_elkt!(content)
        if hollow_hash?(graph) && declarations?(content)
          raise ArgumentError, UNPARSEABLE
        end

        graph
      end

      # A JSON document can only open with `{` or `[`, so anything else goes
      # straight to YAML. Flow-style YAML opens with `{` too, though, so a
      # failed JSON parse has to fall through to YAML before ELKT gets a
      # turn -- otherwise a flow-style graph is read as ELKT layout options
      # and silently loses its children.
      def sniff(text)
        if text.lstrip.start_with?("{", "[")
          return try_json(text) || try_yaml(text)
        end

        try_yaml(text)
      end

      def try_json(text)
        real_graph(Elkrb::Graph::Graph.from_json(text))
      rescue Lutaml::Model::InvalidFormatError
        nil
      end

      def try_yaml(text)
        real_graph(Elkrb::Graph::Graph.from_yaml(text))
      rescue Lutaml::Model::InvalidFormatError
        nil
      end

      # A top-level sequence (`[]`, `[{}]`, `- id: g`) parses without raising
      # but comes back an Array, and lutaml-model 0.8.19 turns any mapping at
      # all into a Graph with every field nil. Neither is a real parse, and
      # calling #id on the Array would blow up.
      def real_graph(result)
        return nil unless result.is_a?(Elkrb::Graph::Graph)
        return nil if malformed_model?(result)

        result unless hollow_model?(result)
      end

      # Given a mapping where a sequence belongs (`"children": {"a": 1}`),
      # lutaml-model coerces it into ONE nil-filled model, so `children` comes
      # back as a single empty Node instead of a list. That is a malformed
      # document, not a graph: hand it back and every downstream reader breaks
      # on it. Fall through to the normalized parse error instead.
      def malformed_model?(graph)
        [graph.children, graph.edges].any? do |value|
          !value.nil? && !value.is_a?(::Array)
        end
      end

      # Mirrors the field list in Graph's json and yaml mapping blocks: when
      # every recognized field comes back empty, lutaml-model matched nothing.
      # layout_options is nil-checked rather than blank-checked because any
      # recognized layoutOptions substructure at all is real content -- an
      # explicit `"layoutOptions": {}` means the document WAS understood, so
      # a present-but-empty LayoutOptions must not read as hollow.
      def hollow_model?(graph)
        NIL_WHEN_HOLLOW.all? { |field| graph.public_send(field).nil? } &&
          BLANK_WHEN_HOLLOW.all? { |field| blank?(graph.public_send(field)) }
      end

      def parse_elkt_or_fail(content)
        graph = parse_elkt!(content)
        return graph unless hollow_hash?(graph)

        raise ArgumentError, UNPARSEABLE
      end

      def parse_elkt!(content)
        require_relative "parsers/elkt_parser"
        Elkrb::Parsers::ElktParser.parse(content)
      rescue StandardError
        raise ArgumentError, UNPARSEABLE
      end

      # An empty or comment-only ELKT file is a valid empty graph, so the
      # hollow guard must not reject it. A file that DOES carry declarations
      # and still parses to nothing is unrecognized content — the parser skips
      # lines it does not understand, so without this it exits 0 on junk.
      def declarations?(text)
        text.gsub(%r{/\*.*?\*/}m, "")
          .each_line
          .any? { |line| !line.sub(%r{//.*$}, "").strip.empty? }
      end

      # An ELKT graph is itself a node and may carry only its own position or
      # size (`layout [ size: 30, 40 ]`). That is meaningful content, so the
      # root geometry counts alongside children, edges and options.
      def hollow_hash?(graph)
        blank?(graph[:children]) && blank?(graph[:edges]) &&
          blank?(graph[:layoutOptions]) &&
          graph.values_at(:x, :y, :width, :height).all?(&:nil?)
      end

      def blank?(collection)
        collection.nil? || collection.empty?
      end
    end
  end
end
