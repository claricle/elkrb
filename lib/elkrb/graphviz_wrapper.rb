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
    rescue SystemCallError
      # `available?` only proves that a path looked executable once. Exec can
      # still fail -- a stale entry, a directory, a file this process may not
      # run. The backticks this replaced never surfaced that, because /bin/sh
      # absorbed the failure and handed back its own error text, so returning
      # nil is what keeps the documented nil-or-String contract.
      nil
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

    # A shell-free replacement for `which`. Nothing here interpolates into a
    # command string, which is what the old `system("which #{path} ...")` did.
    #
    # This is NOT execvp parity and does not claim to be. It is deliberately
    # wider in one direction and narrower in another, both inherited from the
    # `File.executable?` probe that has always been the first check here:
    #   wider  -- a bare name is resolved against the working directory too,
    #             where execvp searches it only for an empty PATH element;
    #   narrower -- an empty PATH element is dropped rather than walked,
    #             because `File.join("", "dot")` is "/dot", so walking it would
    #             probe the ROOT directory, which is what neither party wants.
    # A candidate that already contains a separator is not PATH-searched at
    # all; that part does match execvp, and it avoids the nonsense
    # `File.join("/opt/bin", "/usr/bin/dot")` -> "/opt/bin/usr/bin/dot".
    # `File::SEPARATOR` is "/" on every platform Ruby runs on, Windows
    # included -- `File::ALT_SEPARATOR` is the "\\" one, and Ruby's own
    # stdlib normalises INTO SEPARATOR, never the other way. Reproduce with
    # `grep -rn 'ALT_SEPARATOR, File::SEPARATOR' "$(ruby -e 'print
    # RbConfig::CONFIG[%q(rubylibdir)]')"`: pathname.rb uses `tr!` and
    # rubygems/installer.rb uses `tr`, both in that direction. Line numbers
    # move between Ruby versions, so they are deliberately not quoted here.
    # Every candidate above is written with "/", so one test covers them all.
    def executable_candidate?(path)
      return true if executable_file?(path)
      return false if path.include?(File::SEPARATOR)

      dirs = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
      dirs.reject(&:empty?).any? do |dir|
        executable_file?(File.join(dir, path))
      end
    end

    # `File.executable?` alone is true for a DIRECTORY, and exec is not. Both
    # arms above ask the same question so the fast path cannot be laxer than
    # the walk.
    def executable_file?(path)
      File.file?(path) && File.executable?(path)
    end

    # Both paths go through `File.path`, which is the conversion
    # `validate_file_exists!` already accepts -- a String, or anything carrying
    # `#to_path` -- and the one `system(*argv)` will not do for us, since argv
    # converts through `#to_str` and Pathname does not define it. Interpolation
    # is NOT interchangeable with it: `#to_s` on a `#to_path` object that is not
    # a Pathname yields "#<Object:0x...>", and dot then writes a file by that
    # name and reports success.
    def build_command(engine, format, input_file, output_file, dpi)
      cmd_parts = [
        @dot_path,
        "-K#{engine}",
        "-T#{format}",
        "-Gdpi=#{dpi}",
      ]

      cmd_parts << "-o#{File.path(output_file)}" if output_file
      cmd_parts << positional_path(File.path(input_file))

      cmd_parts
    end

    # Removing the shell closes command injection but not ARGUMENT injection.
    # `validate_file_exists!` only asks whether the path exists, so a file
    # genuinely named "-ovictim.txt" passes and then reaches dot as a bare
    # positional, where its option parser reads it as a second -o and writes a
    # file the caller never named -- exit 0, success reported. Measured against
    # graphviz 15.1.1: dot rejects the usual end-of-options marker
    # ("dot: option -- unrecognized", rc=1), so "--" is not available. "./"
    # names the same file and dot accepts it.
    def positional_path(path)
      path.start_with?("-") ? File.join(".", path) : path
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
