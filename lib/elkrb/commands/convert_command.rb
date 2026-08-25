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

        require_relative "../format_sniffer"
        Elkrb::FormatSniffer.read(File.read(file), File.extname(file).downcase)
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
