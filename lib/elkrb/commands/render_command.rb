# frozen_string_literal: true

module Elkrb
  module Commands
    # Command for rendering DOT files to images using Graphviz
    class RenderCommand
      def initialize(dot_file, options)
        @dot_file = dot_file
        @options = options
      end

      def run
        unless File.exist?(@dot_file)
          raise ArgumentError,
                "File not found: #{@dot_file}"
        end

        # Detect image format
        format = detect_image_format(@options[:output])

        # Render using Graphviz
        require_relative "../graphviz_wrapper"
        graphviz = Elkrb::GraphvizWrapper.new

        engine = @options[:engine] || "dot"
        dpi = @options[:dpi] || 96

        graphviz.render(@dot_file, @options[:output], format, engine: engine,
                                                              dpi: dpi)

        puts "✓ Rendered #{@dot_file} → #{@options[:output]}"
      end

      private

      def detect_image_format(filename)
        ext = File.extname(filename).downcase

        case ext
        when ".png" then :png
        when ".svg" then :svg
        when ".pdf" then :pdf
        when ".ps" then :ps
        when ".eps" then :eps
        else
          raise ArgumentError, "Cannot detect image format from extension: #{ext}. " \
                               "Supported: .png, .svg, .pdf, .ps, .eps"
        end
      end
    end
  end
end
