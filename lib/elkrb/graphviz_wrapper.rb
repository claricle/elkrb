# frozen_string_literal: true

require "open3"
require_relative "atomic_destination"
require_relative "command_resolver"

module Elkrb
  # Wrapper for optional Graphviz integration.
  #
  # A missing Graphviz is a hard failure, not a degraded render. #available?
  # lets a caller ask first; #render raises GraphvizNotFoundError carrying
  # the install instructions, and the diagram command re-raises it after
  # deleting the half-written file rather than leaving DOT text sitting
  # under a .svg name.
  #
  # reek 6.5.0's own directive-comment parser (pinned by the Gemfile's
  # `~> 6.5.0`; re-check this comment on any reek bump) only recognizes a
  # `{ ... }` config hash when it appears on a SINGLE comment line --
  # `Reek::CodeComment::CONFIGURATION_REGEX` has no /m flag, so a `{ }` split
  # across lines silently fails to parse, and reek falls back to disabling
  # the WHOLE detector for this class, which is
  # exactly the whole-class over-reach this is meant to avoid. Measured: a
  # 4th bang method added under the split form was NOT flagged; under this
  # one-line form it IS. Verify with `context.config_for(MissingSafeMethod)`
  # if this line is ever touched -- it must read `{"exclude"=>[...]}`, not
  # `{"enabled"=>false}`.
  # rubocop:disable Layout/LineLength
  # :reek:MissingSafeMethod { exclude: [ validate_engine!, validate_file_exists!, validate_format!, validate_output_file! ] }
  # rubocop:enable Layout/LineLength
  # These four are argument validators, not the dangerous/safe pair the
  # smell looks for; a bang-less companion isn't meaningful for any of them.
  # Scoped to this exact class by reek's inline-comment mechanism, so a new
  # bang method added directly on GraphvizWrapper later is NOT silently
  # exempted. A nested class INHERITS this exclude, though --
  # `CodeContext#config_for` merges the parent's config in -- which is why
  # GraphvizNotFoundError below resets it explicitly rather than relying on
  # this comment's scope.
  class GraphvizWrapper
    # :reek:MissingSafeMethod { exclude: [] } -- resets the exclude this
    # nested class would otherwise inherit from GraphvizWrapper above, so a
    # bang method added here later is not silently exempted by a sibling's
    # unrelated exclusion.
    class GraphvizNotFoundError < StandardError; end

    SUPPORTED_FORMATS = %i[png svg pdf ps eps].freeze
    SUPPORTED_ENGINES = %w[dot neato fdp sfdp twopi circo].freeze

    # "dot" first, so a plain PATH lookup (CommandResolver, PATHEXT-aware on
    # Windows) always gets the first try. The rest are where the package
    # managers put `dot` when it is not on PATH. macOS cron and launchd hand
    # a process /usr/bin:/bin, and Homebrew -- the install route
    # #installation_message recommends -- is on neither.
    CANDIDATES = [
      "dot",
      "/usr/bin/dot",
      "/usr/local/bin/dot",
      "/opt/homebrew/bin/dot",
      "/opt/local/bin/dot",
    ].freeze
    private_constant :CANDIDATES

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

      engine, dpi = command_options(options)

      AtomicDestination.generate(
        output_file, require_nonempty: true
      ) do |scratch|
        execute_command(build_command(engine, format, dot_file, scratch, dpi))
      end
    end

    # `available?` only proves @dot_path resolved to a real, executable file
    # at CONSTRUCTION time. Between then and this call the binary can be
    # deleted or lose its execute bit -- measured, Open3.capture2e raises
    # Errno::ENOENT or Errno::EACCES in exactly those cases, which would
    # otherwise break #version's own documented "nil when not available"
    # contract instead of honoring it.
    def version
      return nil unless available?

      output, = Open3.capture2e(@dot_path, "-V")
      output.match(/version\s+([\d.]+)/i)&.captures&.first
    rescue SystemCallError
      nil
    end

    def supported_formats
      SUPPORTED_FORMATS
    end

    def supported_engines
      SUPPORTED_ENGINES
    end

    private

    def command_options(options)
      engine, dpi = options.values_at(:engine, :dpi)
      engine ||= "dot"
      dpi ||= 96
      validate_engine!(engine)
      [engine, dpi]
    end

    # Finds the Graphviz `dot` executable.
    #
    # @return [String, nil] the path to `dot`, or nil if not found
    #
    # ELKRB_DOT, if set to a non-empty value, is the sole candidate; a bare
    # override with no directory is anchored to the working directory first
    # so it resolves the same way CommandResolver.runnable? checks it.
    # Resolve the chosen candidate with `File.realpath`, not
    # `File.expand_path` -- expansion is lexical and gets a path crossing a
    # symlinked directory wrong.
    def find_graphviz
      override = ENV.fetch("ELKRB_DOT", nil)
      candidates = if override.nil? || override.empty?
                     CANDIDATES
                   else
                     [anchor_bare_name(override)]
                   end
      resolved = candidates.lazy
        .filter_map { |each| CommandResolver.resolved_path(each) }
        .first
      resolved && resolve_real(resolved)
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

    # option_safe_path guards both the input and output paths: dot reads a
    # leading-dash path as an option instead of a positional, so a file
    # named "-V" would make dot print its banner and write nothing while
    # reporting success. Both paths go through `File.path` first -- a
    # `#to_path` object interpolated with `#to_s` instead yields
    # "#<Object:0x...>", which dot then writes by that literal name.
    def build_command(engine, format, input_file, output_file, dpi)
      [@dot_path, "-K#{engine}", "-T#{format}", "-Gdpi=#{dpi}",
       "-o", option_safe_path(File.path(output_file)),
       option_safe_path(File.path(input_file))]
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

      raise GraphvizNotFoundError, "Graphviz command failed: #{argv.inspect}"
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

    # Empty counts as missing; BLANK does not. Measured: `render(input,
    # "   ", :png)` writes a real file named "   ", because three spaces
    # is a legal POSIX filename -- so do not reach for `strip` here. An
    # empty path, by contrast, reaches `dot` as a bare `-o` with nothing
    # after it, which prints its whole usage banner to stderr and then
    # fails as GraphvizNotFoundError, blaming a Graphviz that is installed
    # and working.
    def validate_output_file!(output_file)
      return unless output_file.to_s.empty?

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
