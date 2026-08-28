# frozen_string_literal: true

require "open3"
require "rbconfig"

module Elkrb
  # Wrapper for optional Graphviz integration
  # Provides graceful degradation when Graphviz is not installed
  class GraphvizWrapper
    class GraphvizNotFoundError < StandardError; end

    SUPPORTED_FORMATS = %i[png svg pdf ps eps].freeze
    SUPPORTED_ENGINES = %w[dot neato fdp sfdp twopi circo].freeze

    # Where the package managers put `dot` when it is not on PATH. macOS
    # cron and launchd hand a process /usr/bin:/bin, and Homebrew -- the
    # install route #installation_message recommends -- is on neither.
    FALLBACK_DOT_PATHS = %w[
      /usr/bin/dot
      /usr/local/bin/dot
      /opt/homebrew/bin/dot
      /opt/local/bin/dot
    ].freeze
    private_constant :FALLBACK_DOT_PATHS

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
    # ELKRB_DOT, if set to a non-empty value, is the sole candidate —
    # neither PATH nor a fallback location is tried if it doesn't point at a
    # real executable. An unset or empty ELKRB_DOT is treated as no override:
    # every `dot` on PATH is tried in order, then the fallback locations.
    #
    # The override is anchored to the working directory because a bare name
    # like "dot" resolves two different ways: File.file? reads it against the
    # working directory, while the OS resolves an argv[0] carrying no
    # separator through PATH. Unanchored, this method validated one binary
    # and #render ran another.
    def find_graphviz
      override = ENV.fetch("ELKRB_DOT", nil)
      candidates = if override.nil? || override.empty?
                     path_dot_candidates + FALLBACK_DOT_PATHS
                   else
                     [File.absolute_path(override)]
                   end
      candidates.find { |candidate| valid_executable?(candidate) }
    end

    def path_dot_candidates
      # An empty PATH component means the working directory, and #split would
      # otherwise turn it into "/dot". The shell would find dot there; we must
      # too, or #available? disagrees with the command that actually runs.
      # "".split(sep, -1) is [], not [""], so an empty PATH would search
      # nowhere at all — while the shell still looks in the working directory.
      raw = ENV.fetch("PATH", "")
      components = raw.empty? ? [""] : raw.split(File::PATH_SEPARATOR, -1)
      components.flat_map do |dir|
        base = dir.empty? ? "." : dir
        dot_basenames.map { |name| File.join(base, name) }
      end
    end

    # Windows needs the executable suffix; everywhere else the bare name is
    # what exists. Both are probed so a checkout works either side.
    def dot_basenames
      suffix = RbConfig::CONFIG["EXEEXT"].to_s
      suffix.empty? ? ["dot"] : ["dot#{suffix}", "dot"]
    end

    def valid_executable?(path)
      File.file?(path) && File.executable?(path)
    end

    def build_command(engine, format, input_file, output_file, dpi)
      [@dot_path, "-K#{engine}", "-T#{format}", "-Gdpi=#{dpi}",
       "-o", output_file, input_file]
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
