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
    class << self
      # @param content [String] raw file content
      # @param unparseable_message [String] message for the final ArgumentError
      # @return [Elkrb::Graph::Graph, Hash] a parsed graph model, or an ELKT hash
      # @raise [ArgumentError] when neither JSON/YAML nor ELKT yields real content
      def parse(content, unparseable_message:)
        require_relative "graph/graph"

        graph = safely_sniff(content)
        return graph if graph && !hollow_model?(graph)

        parse_elkt_or_fail(content, unparseable_message)
      end

      private

      def safely_sniff(content)
        if content.lstrip.start_with?("{", "[")
          Elkrb::Graph::Graph.from_json(content)
        else
          Elkrb::Graph::Graph.from_yaml(content)
        end
      rescue Lutaml::Model::InvalidFormatError
        nil
      end

      # graph.layout_options is a typed LayoutOptions model (not a Hash) on
      # this codebase, so it's checked for nil only -- it doesn't respond to
      # #empty?, and any recognized layoutOptions substructure at all is
      # real enough content not to treat as garbage.
      def hollow_model?(graph)
        graph.id.nil? && blank?(graph.children) && blank?(graph.edges) && graph.layout_options.nil?
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
