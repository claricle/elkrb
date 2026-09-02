# frozen_string_literal: true

require "json"
require "securerandom"
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

      # Renders to a SCRATCH path and moves it into place only once the
      # render has succeeded. Nothing else makes the guarantee hold.
      #
      # Rendering straight to `output_file` and cleaning up afterwards does
      # not work, and both attempts at it failed differently. Deleting
      # unconditionally destroyed a file the caller already had there.
      # Deleting only when we had created it left a TRUNCATED image behind --
      # measured, a 1024-byte file beginning `<?xml` from a render that died
      # partway, sitting under the caller's own filename. `File.rename` is
      # atomic within a filesystem, so the image path either holds the
      # previous content or a complete render, never a fragment.
      # A scratch path in the destination directory that did not exist a
      # moment ago and that this process created. `File::EXCL` is what makes
      # that true rather than merely likely.
      def scratch_path(output_file, suffix)
        dir = File.dirname(output_file)
        base = File.basename(output_file)

        loop do
          candidate = File.join(
            dir, ".#{base}.#{SecureRandom.hex(8)}.tmp.#{suffix}"
          )
          begin
            File.open(candidate,
                      File::CREAT | File::EXCL | File::WRONLY, &:close)
            return candidate
          rescue Errno::EEXIST
            next
          end
        end
      end

      def render_to_image(dot_content, output_file, format)
        # Scratch names are UNIQUE and created exclusively. A fixed name like
        # `out.svg.tmp.svg` is guessable, and if something already sits there
        # the renderer follows it: measured, a symlink at that name pointing
        # back at `out.svg` sent a failed render's partial output straight
        # onto the caller's file. Two concurrent renders of the same target
        # collided the same way. `File::EXCL` refuses to open an existing path
        # at all, so neither can happen.
        #
        # Both live in the DESTINATION directory, which keeps `File.rename` on
        # one filesystem and therefore atomic.
        dot_file = scratch_path(output_file, "dot")
        image_file = scratch_path(output_file, format.to_s)

        begin
          write_output(dot_content, dot_file)

          require_relative "../graphviz_wrapper"
          graphviz = Elkrb::GraphvizWrapper.new

          graphviz.render(dot_file, image_file, format, engine: "dot", dpi: 96)
          File.rename(image_file, output_file)

          FileUtils.rm_f(dot_file)
        rescue StandardError
          discard_unrendered(dot_file, image_file)
          raise
        end
      end

      # Only the scratch files. The image path is never touched on failure,
      # because nothing was written there -- the render goes to a scratch
      # name and is moved into place only on success.
      def discard_unrendered(dot_file, image_file)
        FileUtils.rm_f(image_file) if File.file?(image_file)
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
