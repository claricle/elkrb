# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"

module Elkrb
  module Commands
    # Command for converting between graph formats
    # Supports JSON, YAML, DOT, and ELKT formats
    class ConvertCommand
      def initialize(file, options)
        @file = file
        @options = options
      end

      def run
        # Load source file
        graph = load_any_format(@file)

        # Detect target format
        target_format = detect_format(@options[:output])

        # Convert
        content = export_to_format(graph, target_format)

        # Write output
        write_output(content, @options[:output])

        puts "✓ Converted #{@file} → #{@options[:output]} (#{target_format})"
      end

      private

      def load_any_format(file)
        raise ArgumentError, "File not found: #{file}" unless File.exist?(file)

        content = File.read(file)
        ext = File.extname(file).downcase

        case ext
        when ".json"
          require_relative "../graph/graph"
          Elkrb::Graph::Graph.from_json(content)
        when ".yml", ".yaml"
          require_relative "../graph/graph"
          Elkrb::Graph::Graph.from_yaml(content)
        when ".elkt"
          require_relative "../parsers/elkt_parser"
          Elkrb::Parsers::ElktParser.parse(content)
        when ".dot", ".gv"
          raise ArgumentError,
                "DOT format input not yet supported. Use JSON, YAML, or ELKT."
        else
          detect_and_parse(content)
        end
      end

      def detect_and_parse(content)
        require_relative "../graph/graph"

        # Try JSON first
        begin
          return Elkrb::Graph::Graph.from_json(content)
        rescue JSON::ParserError
          # Not JSON
        end

        # Try YAML
        begin
          return Elkrb::Graph::Graph.from_yaml(content)
        rescue Psych::SyntaxError
          # Not YAML
        end

        # Try ELKT
        begin
          require_relative "../parsers/elkt_parser"
          Elkrb::Parsers::ElktParser.parse(content)
        rescue StandardError
          raise ArgumentError,
                "Unable to parse input file. Supported formats: JSON, YAML, ELKT"
        end
      end

      def detect_format(filename)
        ext = File.extname(filename).downcase

        case ext
        when ".json" then :json
        when ".yml", ".yaml" then :yaml
        when ".dot", ".gv" then :dot
        when ".elkt" then :elkt
        else
          # Use explicit format option if provided
          if @options[:format]
            @options[:format].to_sym
          else
            raise ArgumentError,
                  "Cannot detect output format from extension: #{ext}"
          end
        end
      end

      def export_to_format(graph, format)
        case format
        when :json
          graph.to_json
        when :yaml
          graph.to_yaml
        when :dot
          require_relative "../serializers/dot_serializer"
          Elkrb::Serializers::DotSerializer.new.serialize(graph)
        when :elkt
          require_relative "../serializers/elkt_serializer"
          Elkrb::Serializers::ElktSerializer.new.serialize(graph)
        else
          raise ArgumentError, "Unsupported output format: #{format}"
        end
      end

      def write_output(content, filename)
        dir = File.dirname(filename)
        FileUtils.mkdir_p(dir)

        File.write(filename, content)
      end
    end
  end
end
