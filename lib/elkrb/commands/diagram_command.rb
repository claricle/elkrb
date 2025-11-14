# frozen_string_literal: true

require "json"
require "yaml"
require "fileutils"

module Elkrb
  module Commands
    # Command for creating diagrams from ELK graph files
    # Supports multiple input formats (JSON, YAML, ELKT) and output formats (DOT, PNG, SVG, PDF)
    class DiagramCommand
      def initialize(file, options)
        @file = file
        @options = options
      end

      def run
        # Load graph
        graph = load_graph(@file)

        # Apply layout
        layout_options = build_layout_options
        result = Elkrb::Layout::LayoutEngine.layout(graph, layout_options)

        # Determine output format
        output_format = detect_format(@options[:output])

        # Export to format
        content = export_to_format(result, output_format)

        # Write output
        write_output(content, @options[:output])

        # Render to image if needed
        if image_format?(output_format)
          render_to_image(@options[:output], output_format)
        end

        # Preview if requested
        preview(@options[:output]) if @options[:preview]

        puts "✓ Diagram created: #{@options[:output]}"
      end

      private

      def load_graph(file)
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

      def build_layout_options
        opts = {}

        opts[:algorithm] = @options[:algorithm] if @options[:algorithm]
        opts[:direction] = @options[:direction] if @options[:direction]
        opts[:spacing_node_node] = @options[:spacing] if @options[:spacing]
        opts[:edge_routing] = @options[:edge_routing] if @options[:edge_routing]

        opts
      end

      def detect_format(filename)
        ext = File.extname(filename).downcase

        case ext
        when ".json" then :json
        when ".yml", ".yaml" then :yaml
        when ".dot", ".gv" then :dot
        when ".elkt" then :elkt
        when ".png" then :png
        when ".svg" then :svg
        when ".pdf" then :pdf
        when ".ps" then :ps
        when ".eps" then :eps
        else
          # Use explicit format option if provided
          if @options[:format]
            @options[:format].to_sym
          else
            :dot # Default to DOT
          end
        end
      end

      def export_to_format(result, format)
        case format
        when :json
          # Use Lutaml-model's to_json for proper serialization
          result.to_json
        when :yaml
          # Use Lutaml-model's to_yaml for proper serialization
          result.to_yaml
        when :dot, :png, :svg, :pdf, :ps, :eps
          require_relative "../serializers/dot_serializer"
          Elkrb::Serializers::DotSerializer.new.serialize(result)
        when :elkt
          require_relative "../serializers/elkt_serializer"
          Elkrb::Serializers::ElktSerializer.new.serialize(result)
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
      end

      def write_output(content, filename)
        dir = File.dirname(filename)
        FileUtils.mkdir_p(dir)

        File.write(filename, content)
      end

      def image_format?(format)
        %i[png svg pdf ps eps].include?(format)
      end

      def render_to_image(output_file, format)
        # For image formats, we need to render DOT -> image
        # First write DOT to temp file
        dot_file = "#{output_file}.tmp.dot"

        # Re-read the content we just wrote (which is DOT)
        dot_content = File.read(output_file)

        # If output is not already DOT, we need to export it
        if File.extname(output_file).downcase == ".dot"
          dot_file = output_file
        else
          File.write(dot_file, dot_content)
        end

        # Render using Graphviz
        begin
          require_relative "../graphviz_wrapper"
          graphviz = Elkrb::GraphvizWrapper.new

          unless graphviz.available?
            warn "⚠ Graphviz not found. Cannot render to #{format}."
            warn "  Install Graphviz or export to DOT format instead."
            return
          end

          graphviz.render(dot_file, output_file, format, engine: "dot", dpi: 96)

          # Clean up temp DOT file if we created one
          File.delete(dot_file) if dot_file != output_file && File.exist?(dot_file)
        rescue Elkrb::GraphvizWrapper::GraphvizNotFoundError => e
          warn "⚠ #{e.message}"
        end
      end

      def preview(file)
        case RbConfig::CONFIG["host_os"]
        when /darwin/
          system("open", file)
        when /linux/
          system("xdg-open", file)
        when /mswin|mingw|cygwin/
          system("start", file)
        else
          warn "Preview not supported on this platform"
        end
      end
    end
  end
end
