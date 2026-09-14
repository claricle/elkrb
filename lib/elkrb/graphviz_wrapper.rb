# frozen_string_literal: true

module Elkrb
  # Wrapper for optional Graphviz integration
  # Provides graceful degradation when Graphviz is not installed
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
  # :reek:MissingSafeMethod { exclude: [ validate_engine!, validate_file_exists!, validate_format! ] }
  # rubocop:enable Layout/LineLength
  # These three are argument validators, not the dangerous/safe pair the
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

      output = `#{@dot_path} -V 2>&1`
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

      candidates.each do |path|
        if File.executable?(path)
          return path
        elsif system("which #{path} > /dev/null 2>&1")
          return path
        end
      end

      nil
    end

    def build_command(engine, format, input_file, output_file, dpi)
      cmd_parts = [
        @dot_path,
        "-K#{engine}",
        "-T#{format}",
        "-Gdpi=#{dpi}",
      ]

      cmd_parts << "-o#{output_file}" if output_file
      cmd_parts << input_file

      cmd_parts.join(" ")
    end

    def execute_command(cmd)
      success = system(cmd)
      unless success
        raise GraphvizNotFoundError,
              "Graphviz command failed: #{cmd}"
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
