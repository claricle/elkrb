# frozen_string_literal: true

require "open3"

module Elkrb
  # Wrapper for optional Graphviz integration
  # Provides graceful degradation when Graphviz is not installed
  class GraphvizWrapper
    class GraphvizNotFoundError < StandardError; end

    SUPPORTED_FORMATS = %i[png svg pdf ps eps].freeze
    SUPPORTED_ENGINES = %w[dot neato fdp sfdp twopi circo].freeze

    def initialize
      @dot_path = find_graphviz
    end

    def available?
      !@dot_path.nil?
    end

    def render(dot_file, output_file, format, options = {})
      raise GraphvizNotFoundError, installation_message unless available?

      validate_format!(format)
      validate_file_exists!(dot_file)
      validate_output_file!(output_file)

      engine = options[:engine] || "dot"
      validate_engine!(engine)

      dpi = options[:dpi] || 96

      argv = build_command(engine, format, dot_file, output_file, dpi)
      execute_command(argv)
    end

    def version
      return nil unless available?

      output, = Open3.capture2e(@dot_path, "-V")
      output.match(/version\s+([\d.]+)/i)&.captures&.first
    end

    def supported_formats
      SUPPORTED_FORMATS
    end

    def supported_engines
      SUPPORTED_ENGINES
    end

    private

    # Finds the Graphviz `dot` executable.
    #
    # @return [String, nil] the path to `dot`, or nil if not found
    #
    # ENV["ELKRB_DOT"], if set to a non-empty value, is the sole candidate —
    # no PATH fallback if it doesn't point at a real executable. An unset or
    # empty ELKRB_DOT is treated as no override: every `dot` on PATH is
    # tried in order.
    def find_graphviz
      override = ENV["ELKRB_DOT"]
      candidates = override.nil? || override.empty? ? path_dot_candidates : [override]
      candidates.find { |candidate| valid_executable?(candidate) }
    end

    def path_dot_candidates
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "dot") }
    end

    def valid_executable?(path)
      File.file?(path) && File.executable?(path)
    end

    def build_command(engine, format, input_file, output_file, dpi)
      [@dot_path, "-K#{engine}", "-T#{format}", "-Gdpi=#{dpi}", "-o", output_file, input_file]
    end

    def execute_command(argv)
      success = system(*argv)
      return success if success

      raise GraphvizNotFoundError, "Graphviz command failed: #{argv.join(' ')}"
    end

    def validate_format!(format)
      format_sym = format.to_sym
      return if SUPPORTED_FORMATS.include?(format_sym)

      raise ArgumentError, "Unsupported format: #{format}. " \
                           "Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
    end

    def validate_engine!(engine)
      return if SUPPORTED_ENGINES.include?(engine.to_s)

      raise ArgumentError, "Unsupported engine: #{engine}. " \
                           "Supported engines: #{SUPPORTED_ENGINES.join(', ')}"
    end

    def validate_file_exists!(file)
      return if File.exist?(file)

      raise ArgumentError, "Input file not found: #{file}"
    end

    def validate_output_file!(output_file)
      return if output_file

      raise ArgumentError, "Output file path is required"
    end

    def installation_message
      <<~MSG
        Graphviz is required but not found.

        Installation instructions:
          macOS:   brew install graphviz
          Ubuntu:  sudo apt-get install graphviz
          Fedora:  sudo dnf install graphviz
          Windows: https://graphviz.org/download/

        Alternatively, export to DOT format and render manually:
          elkrb diagram input.json -o output.dot

        If Graphviz is installed but not on PATH, set ELKRB_DOT=/path/to/dot
      MSG
    end
  end
end
