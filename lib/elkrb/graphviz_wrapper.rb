# frozen_string_literal: true

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

      engine = options[:engine] || "dot"
      validate_engine!(engine)

      dpi = options[:dpi] || 96

      cmd = build_command(engine, format, dot_file, output_file, dpi)
      execute_command(cmd)
    end

    def version
      return nil unless available?

      output = IO.popen([@dot_path, "-V"], err: %i[child out], &:read)
      output.match(/version\s+([\d.]+)/i)&.captures&.first
    end

    def supported_formats
      SUPPORTED_FORMATS
    end

    def supported_engines
      SUPPORTED_ENGINES
    end

    private

    def find_graphviz
      # Try common locations
      candidates = [
        "dot",
        "/usr/bin/dot",
        "/usr/local/bin/dot",
        "/opt/homebrew/bin/dot",
        "/opt/local/bin/dot",
      ]

      candidates.find { |path| executable_candidate?(path) }
    end

    # A shell-free replacement for `which`. An absolute candidate is asked of
    # the filesystem directly; a bare name is resolved against PATH the way
    # execvp would. Nothing here interpolates into a command string, which is
    # what the old `system("which #{path} ...")` did.
    def executable_candidate?(path)
      return true if File.executable?(path)
      return false if path.include?(File::SEPARATOR)

      dirs = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
      dirs.reject(&:empty?).any? do |dir|
        entry = File.join(dir, path)
        File.file?(entry) && File.executable?(entry)
      end
    end

    def build_command(engine, format, input_file, output_file, dpi)
      cmd_parts = [
        @dot_path,
        "-K#{engine}",
        "-T#{format}",
        "-Gdpi=#{dpi}",
      ]

      cmd_parts << "-o#{output_file}" if output_file
      # `File.path` is exactly the conversion `validate_file_exists!` already
      # accepts -- a String, or anything with `#to_path` -- and it is the one
      # `system(*argv)` will not do for us (argv converts via `#to_str`, which
      # Pathname does not define). `#to_s` is NOT interchangeable here: on a
      # `#to_path` object that is not a Pathname it yields "#<Object:0x...>".
      cmd_parts << File.path(input_file)

      cmd_parts
    end

    def execute_command(cmd)
      success = system(*cmd)
      unless success
        raise GraphvizNotFoundError,
              "Graphviz command failed: #{cmd.inspect}"
      end

      success
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
      MSG
    end
  end
end
