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

        # An image format NEVER has DOT written under its own name. The DOT
        # went to `out.svg` first and was read back for rendering, so any
        # failure between those two points left the caller an `out.svg` that
        # began `digraph G{`. Cleanup could not be relied on to undo it
        # either: `FileUtils.rm_f` swallows an unlink failure, so in a
        # non-writable directory the misleading file simply stayed.
        #
        # Staging under a separate name means the image path is only ever
        # written by a render that succeeded.
        if image_format?(output_format)
          render_to_image(content, @options[:output], output_format)
        else
          write_output(content, @options[:output])
        end

        # Preview if requested
        preview(@options[:output]) if @options[:preview]

        puts "✓ Diagram created: #{@options[:output]}"
      end

      private

      def load_graph(file)
        raise ArgumentError, "File not found: #{file}" unless File.exist?(file)

        require_relative "../format_sniffer"
        Elkrb::FormatSniffer.read(File.read(file), File.extname(file).downcase)
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

      def render_to_image(dot_content, output_file, format)
        dot_file = "#{output_file}.tmp.dot"
        # Whether the image path was OURS to remove. Cleanup used to delete it
        # unconditionally, which took a file the caller already had there --
        # one we never wrote to, since staging goes elsewhere now.
        pre_existing = File.exist?(output_file)

        begin
          write_output(dot_content, dot_file)

          require_relative "../graphviz_wrapper"
          graphviz = Elkrb::GraphvizWrapper.new

          graphviz.render(dot_file, output_file, format, engine: "dot", dpi: 96)

          FileUtils.rm_f(dot_file)
        rescue StandardError
          discard_unrendered(dot_file, output_file, pre_existing)
          raise
        end
      end

      # Nothing should exist at the image path unless a render put it there,
      # so both the staging file and any partial image are cleared. The image
      # goes FIRST: a staging path that cannot be deleted -- a directory of
      # that name raises EPERM -- must not stop the image being cleaned up.
      def discard_unrendered(dot_file, output_file, pre_existing)
        # Only a file this run created is ours to take away. A half-written
        # image from a failed render is; the caller's own file is not.
        FileUtils.rm_f(output_file) unless pre_existing
        FileUtils.rm_f(dot_file) if File.file?(dot_file)
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
