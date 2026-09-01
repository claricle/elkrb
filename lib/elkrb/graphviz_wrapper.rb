# frozen_string_literal: true

require "open3"
require "rbconfig"

module Elkrb
  # Wrapper for optional Graphviz integration.
  #
  # A missing Graphviz is a hard failure, not a degraded render. #available?
  # lets a caller ask first; #render raises GraphvizNotFoundError carrying
  # the install instructions, and the diagram command re-raises it after
  # deleting the half-written file rather than leaving DOT text sitting
  # under a .svg name.
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
    # An override naming NO directory is anchored to the working directory,
    # because a bare name like "dot" resolves two different ways: File.file?
    # reads it against the working directory, while the OS resolves an
    # argv[0] carrying no separator through PATH. Unanchored, this method
    # validated one binary and #render ran another.
    #
    # The chosen candidate is then resolved to a REAL path. Every relative
    # candidate -- a directory-bearing override like "bin/dot", and the
    # entries built from relative PATH components -- otherwise stays
    # relative, and a later `chdir` silently repoints it: measured, a wrapper
    # that validated "bin/dot" in one directory ran a DIFFERENT binary of the
    # same relative name after moving to another.
    #
    # `File.realpath`, not `File.expand_path`. Expansion is lexical and gets
    # a path crossing a symlinked directory into a ".." wrong; realpath asks
    # the filesystem, which is what the kernel will do. If it cannot resolve,
    # the candidate is kept as found rather than discarded.
    def find_graphviz
      override = ENV.fetch("ELKRB_DOT", nil)
      candidates = if override.nil? || override.empty?
                     path_dot_candidates + FALLBACK_DOT_PATHS
                   else
                     [anchor_bare_name(override)]
                   end
      found = candidates.find { |candidate| valid_executable?(candidate) }
      found && resolve_real(found)
    end

    def resolve_real(path)
      File.realpath(path)
    rescue SystemCallError
      path
    end

    # File.basename strips a directory, so a path that already carries one
    # comes back different from itself. Backslash counts as a separator on
    # Windows only, where File::ALT_SEPARATOR is set. On POSIX it is nil, so
    # a backslash is an ordinary character in a name and such a path anchors
    # -- which is right, because there it really is a bare name.
    def anchor_bare_name(path)
      File.basename(path) == path ? File.join(Dir.pwd, path) : path
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

    # dot takes the input as a bare positional and reads the token after -o
    # as the output name, so on either side a path that begins with a dash
    # is taken for an option instead. A file named "-V" made dot print its
    # banner, exit 0 and write nothing, and the wrapper called that a
    # successful render. The output side fails the same way for any name
    # whose leading dash spells a real flag: measured against graphviz
    # 15.1.1, "-o -x.png" and "-o -v.png" both exit 0 and write nothing,
    # because -x and -v are the reduce and verbose flags. -x says nothing
    # while it does it; -v prints a verbose dump. Other names there are
    # merely loud ("Missing argument for -o flag").
    #
    # This closes only the dash-named half of report-success-on-no-output;
    # the input side also has to reject a directory, which
    # #validate_file_exists! does.
    def build_command(engine, format, input_file, output_file, dpi)
      [@dot_path, "-K#{engine}", "-T#{format}", "-Gdpi=#{dpi}",
       "-o", option_safe_path(output_file), option_safe_path(input_file)]
    end

    # Anchors ONLY a name dot would read as an option, and with File.join,
    # which is purely lexical and leaves any ".." in place for the OS to
    # resolve. File.absolute_path collapses ".." itself, without consulting
    # the filesystem, so across a symlinked directory it names a different
    # file than the OS reaches -- and macOS ships /tmp and /var as symlinks,
    # so that needs no hand-made link to hit. Every other path is passed
    # through byte-identical.
    def option_safe_path(path)
      path.start_with?("-") ? File.join(Dir.pwd, path) : path
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

    # Only a readable regular file will do. File.exist? is also true of a
    # directory, and dot handed one exits 0 having written nothing, so the
    # caller printed a render that never happened.
    def validate_file_exists!(file)
      return if File.file?(file) && File.readable?(file)

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
