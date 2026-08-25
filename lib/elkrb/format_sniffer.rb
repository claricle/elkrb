# frozen_string_literal: true

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
    BYTE_ORDER_MARK = "\uFEFF"
    private_constant :BYTE_ORDER_MARK

    class << self
      # @param content [String] raw file content
      # @param unparseable_message [String] message for the final ArgumentError
      # @return [Elkrb::Graph::Graph, Hash] a parsed graph model, or an ELKT hash
      # @raise [ArgumentError] when neither JSON/YAML nor ELKT yields real content
      def parse(content, unparseable_message:)
        require_relative "graph/graph"

        text = content.delete_prefix(BYTE_ORDER_MARK)
        sniff(text) || parse_elkt_or_fail(text, unparseable_message)
      end

      # For a file whose extension already names the format there is nothing to
      # sniff, so the hollow-content guard does not apply: an empty ELKT
      # document is a valid empty graph, which the parser, layout and the ELKT
      # serializer all round-trip.
      #
      # @param content [String] raw file content
      # @param unparseable_message [String] message for the ArgumentError
      # @return [Hash] the parsed ELKT graph
      # @raise [ArgumentError] when the ELKT parser itself fails
      DEFAULT_UNPARSEABLE = "Unable to parse input file. Supported formats: JSON, YAML, ELKT"

      # The single entry point every command reads input through. Extension
      # dispatch plus shape validation lived in four places and drifted apart;
      # a guard added to one silently left the other three open.
      #
      # @param content [String] raw file content
      # @param extension [String] the file's downcased extension
      # @return [Elkrb::Graph::Graph, Hash] the parsed graph
      # @raise [ArgumentError] for unsupported or unparseable input
      def read(content, extension, unparseable_message: DEFAULT_UNPARSEABLE)
        require_relative "graph/graph"

        case extension
        when ".json"
          validate_model!(Elkrb::Graph::Graph.from_json(content),
                          unparseable_message: unparseable_message)
        when ".yml", ".yaml"
          validate_model!(Elkrb::Graph::Graph.from_yaml(content),
                          unparseable_message: unparseable_message)
        when ".elkt"
          parse_elkt(content, unparseable_message: unparseable_message)
        when ".dot", ".gv"
          raise ArgumentError, "DOT format input not yet supported. Use JSON, YAML, or ELKT."
        else
          parse(content, unparseable_message: unparseable_message)
        end
      end

      # A file whose extension names the format skips sniffing, so it also
      # skips the malformed-shape check the sniffer applies. Both paths need
      # it: lutaml coerces a mapping where a sequence belongs into one
      # nil-filled model, and every downstream reader then breaks on it.
      #
      # @raise [ArgumentError] when the parsed model is not usable
      def validate_model!(graph, unparseable_message:)
        unless graph.is_a?(Elkrb::Graph::Graph) && !malformed_model?(graph)
          raise ArgumentError, unparseable_message
        end

        graph
      end

      def parse_elkt(content, unparseable_message:)
        text = content.delete_prefix(BYTE_ORDER_MARK)
        graph = parse_elkt!(text, unparseable_message)
        raise ArgumentError, unparseable_message if hollow_hash?(graph) && declarations?(text)

        graph
      end

      private

      # A JSON document can only open with `{` or `[`, so anything else goes
      # straight to YAML. Flow-style YAML opens with `{` too, though, so a
      # failed JSON parse has to fall through to YAML before ELKT gets a
      # turn -- otherwise a flow-style graph is read as ELKT layout options
      # and silently loses its children.
      def sniff(text)
        return try_json(text) || try_yaml(text) if text.lstrip.start_with?("{", "[")

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
      # layout_options is a typed LayoutOptions model rather than a Hash, so
      # it gets a nil check -- it has no #empty?, and any recognized
      # layoutOptions substructure at all is real content.
      def hollow_model?(graph)
        graph.id.nil? && graph.x.nil? && graph.y.nil? &&
          graph.width.nil? && graph.height.nil? && graph.layout_options.nil? &&
          blank?(graph.children) && blank?(graph.edges) && blank?(graph.properties)
      end

      def parse_elkt_or_fail(content, unparseable_message)
        graph = parse_elkt!(content, unparseable_message)
        return graph unless hollow_hash?(graph)

        raise ArgumentError, unparseable_message
      end

      def parse_elkt!(content, unparseable_message)
        require_relative "parsers/elkt_parser"
        Elkrb::Parsers::ElktParser.parse(content)
      rescue StandardError
        raise ArgumentError, unparseable_message
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
          blank?(graph[:layoutOptions]) && graph.values_at(:x, :y, :width, :height).all?(&:nil?)
      end

      def blank?(collection)
        collection.nil? || collection.empty?
      end
    end
  end
end
