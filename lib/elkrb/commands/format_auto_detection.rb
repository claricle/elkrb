# frozen_string_literal: true

require "yaml"

module Elkrb
  module Commands
    # Shared JSON -> YAML -> ELKT auto-detect fallback, included by every
    # command whose #load_any_format (or #load_graph) case statement falls
    # through to #detect_and_parse when the file extension is unrecognized.
    #
    # Rescue Lutaml::Model::InvalidFormatError, not only the stdlib parse
    # error: lutaml-model wraps a bad parse in it, so rescuing the stdlib
    # error alone never reaches the YAML or ELKT attempt. Keep the stdlib
    # classes too, in case a lutaml-model version lets them through.
    module FormatAutoDetection
      private

      def detect_and_parse(content)
        require_relative "../graph/graph"

        Parse.json(content) || Parse.yaml(content) || Parse.elkt!(content)
      end

      # Each attempt is a pure function of `content`, so it is a module
      # function rather than an instance method of the including command.
      module Parse
        def self.json(content)
          Elkrb::Graph::Graph.from_json(content)
        rescue JSON::ParserError, Lutaml::Model::InvalidFormatError
          nil
        end

        GRAPH_KEYS = %w[id children edges layoutOptions layout_options].freeze

        def self.yaml(content)
          return nil unless graph_mapping?(content)

          Elkrb::Graph::Graph.from_yaml(content)
        rescue Psych::SyntaxError, Lutaml::Model::InvalidFormatError
          nil
        end

        # An ELKT file of bare `key: value` lines is valid YAML too. Only a
        # mapping that carries a graph key is read as a YAML graph, so such
        # a file still reaches the ELKT attempt.
        def self.graph_mapping?(content)
          data = YAML.safe_load(content, permitted_classes: [Symbol])
          data.is_a?(Hash) && data.keys.map(&:to_s).intersect?(GRAPH_KEYS)
        rescue Psych::Exception
          false
        end

        def self.elkt!(content)
          require_relative "../parsers/elkt_parser"
          Elkrb::Parsers::ElktParser.parse(content)
        rescue StandardError
          raise ArgumentError,
                "Unable to parse input file. " \
                "Supported formats: JSON, YAML, ELKT"
        end
      end
      private_constant :Parse
    end
  end
end
