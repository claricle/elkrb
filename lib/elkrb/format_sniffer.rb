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

        result unless hollow_model?(result)
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

      def hollow_hash?(graph)
        blank?(graph[:children]) && blank?(graph[:edges]) && blank?(graph[:layoutOptions])
      end

      def blank?(collection)
        collection.nil? || collection.empty?
      end
    end
  end
end
