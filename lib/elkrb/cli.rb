# frozen_string_literal: true

require "thor"
require "json"
require "yaml"

require_relative "errors"
require_relative "best_effort_write"
require_relative "layout_flags"
require_relative "options/resolver"

module Elkrb
  # Command-line interface for elkrb
  #
  # Provides commands for laying out graphs from the command line.
  # Supports JSON and YAML input/output formats, with an ELKT fallback
  # for files whose extension isn't recognized.
  class Cli < Thor
    # Do not restore Thor::Base#start's rescues here. `rescue Thor::Error`
    # either exits the process or swallows the error depending on
    # `exit_on_failure?`, and `rescue Errno::EPIPE; exit(true)` exits
    # unconditionally with no config to suppress it -- so a reader hanging
    # up on `layout | head` would kill a library caller. Dispatching
    # directly lets both propagate as themselves; exe/elkrb, the one entry
    # point allowed to exit, turns them into exit codes.
    def self.start(given_args = ARGV, config = {})
      config[:shell] ||= Thor::Base.shell.new
      dispatch(nil, given_args.dup, nil, config)
    end

    # Never reached: the override above calls #dispatch directly rather
    # than Thor::Base#start, so nothing here consults this. Thor emits a
    # deprecation warning if it is left undefined, so it stays, set to the
    # value that matches this class actually being a library.
    def self.exit_on_failure? = false

    # No Thor default: an absent --algorithm must stay nil so the graph's own
    # elk.algorithm can be read before falling back to layered.
    ALGORITHM_OPTION_DESC = "Layout algorithm to use (default: the graph's " \
                            "own elk.algorithm, else layered)"

    class_option :verbose, type: :boolean, default: false,
                           desc: "Enable verbose output"

    desc "layout FILE", "Layout a graph from a JSON, YAML, or ELKT file"
    option :algorithm, type: :string, desc: ALGORITHM_OPTION_DESC
    option :output, type: :string, aliases: "-o",
                    desc: "Output file (default: stdout)"
    option :format, type: :string, default: "json",
                    enum: %w[json yaml],
                    desc: "Output format"
    option :spacing, type: :numeric,
                     desc: "Node spacing"
    option :layer_spacing, type: :numeric,
                           desc: "Layer spacing (for layered algorithm)"
    option :direction, type: :string,
                       desc: "Layout direction (e.g., DOWN, RIGHT); " \
                             "applied by layered and mrtree algorithms"
    option :edge_routing, type: :string,
                          desc: "Edge routing strategy"
    option :padding_top, type: :numeric,
                         desc: "Top padding"
    option :padding_bottom, type: :numeric,
                            desc: "Bottom padding"
    option :padding_left, type: :numeric,
                          desc: "Left padding"
    option :padding_right, type: :numeric,
                           desc: "Right padding"
    def layout(file)
      verbose_output "Loading graph from #{file}..."

      # Read input file
      graph_data = read_input_file(file)

      # Explicit flags go onto the root graph, where they outrank the file
      graph = LayoutFlags.apply(graph_data, options)

      algorithm = Options::Resolver.new.get("elk.algorithm", graph)
      verbose_output "Using algorithm: #{algorithm}"

      # Perform layout
      result = Layout::LayoutEngine.layout(graph, {})

      # Output result
      output_result(result)

      verbose_output "Layout complete!"
    rescue StandardError => e
      fail_command(e)
    end

    desc "algorithms", "List available layout algorithms"
    def algorithms
      algos = Layout::LayoutEngine.known_layout_algorithms

      say "Available Layout Algorithms:", :green
      say ""

      algos.each do |algo|
        say "  #{algo[:id]}", :cyan
        say "    Name: #{algo[:name]}"
        say "    Description: #{algo[:description]}"
        say "    Category: #{algo[:category]}" if algo[:category] != "general"
        say "    Supports Hierarchy: Yes" if algo[:supports_hierarchy]
        say ""
      end
    end

    desc "diagram FILE", "Create diagram from ELK graph file"
    option :algorithm, type: :string, desc: ALGORITHM_OPTION_DESC
    option :direction, type: :string,
                       desc: "Layout direction (e.g., DOWN, RIGHT); " \
                             "applied by layered and mrtree algorithms"
    option :spacing, type: :numeric,
                     desc: "Node spacing"
    option :edge_routing, type: :string,
                          desc: "Edge routing strategy"
    option :output, type: :string, aliases: "-o", required: true,
                    desc: "Output file path"
    option :format, type: :string,
                    desc: "Output format (auto-detected from extension)"
    option :preview, type: :boolean, default: false,
                     desc: "Open result in default viewer"
    def diagram(file)
      require_relative "commands/diagram_command"
      Commands::DiagramCommand.new(file, options).run
    rescue StandardError => e
      fail_command(e)
    end

    desc "convert FILE", "Convert between formats (JSON/YAML/DOT/ELKT)"
    option :output, type: :string, aliases: "-o", required: true,
                    desc: "Output file path"
    option :format, type: :string,
                    desc: "Output format (auto-detected from extension)"
    def convert(file)
      require_relative "commands/convert_command"
      Commands::ConvertCommand.new(file, options).run
    rescue StandardError => e
      fail_command(e)
    end

    desc "render DOT_FILE", "Render DOT to image (requires Graphviz)"
    option :output, type: :string, aliases: "-o", required: true,
                    desc: "Output image file path"
    option :engine, type: :string, default: "dot",
                    desc: "Graphviz engine (dot, neato, fdp, etc.)"
    option :dpi, type: :numeric, default: 96,
                 desc: "Image resolution in DPI"
    def render(dot_file)
      require_relative "commands/render_command"
      Commands::RenderCommand.new(dot_file, options).run
    rescue StandardError => e
      fail_command(e)
    end

    desc "validate FILE", "Validate ELK graph structure"
    option :strict, type: :boolean, default: false,
                    desc: "Enable strict validation"
    def validate(file)
      require_relative "commands/validate_command"
      Commands::ValidateCommand.new(file, options).run
    rescue StandardError => e
      fail_command(e)
    end

    desc "batch DIR", "Process multiple files in a directory"
    option :output_dir, type: :string, required: true,
                        desc: "Output directory for generated files"
    option :format, type: :string, default: "svg",
                    desc: "Output format for all files"
    option :algorithm, type: :string, desc: ALGORITHM_OPTION_DESC
    option :direction, type: :string,
                       desc: "Layout direction (e.g., DOWN, RIGHT); " \
                             "applied by layered and mrtree algorithms"
    option :edge_routing, type: :string,
                          desc: "Edge routing strategy"
    def batch(directory)
      require_relative "commands/batch_command"
      Commands::BatchCommand.new(directory, options).run
    rescue StandardError => e
      fail_command(e)
    end

    desc "version", "Show elkrb version"
    def version
      say "elkrb version #{Elkrb::VERSION}", :green
    end

    private

    def read_input_file(file)
      require_relative "format_sniffer"
      Elkrb::FormatSniffer.read(File.read(file), File.extname(file).downcase)
    end

    def output_result(result)
      output = case options[:format]
               when "yaml"
                 result.to_yaml
               else
                 result.to_json
               end

      if options[:output]
        File.write(options[:output], output)
        verbose_output "Output written to #{options[:output]}"
      else
        say output
      end
    end

    # Best-effort: this is a progress line, not the result. On a closed
    # stderr it must not take the command down with it -- see
    # Elkrb::BestEffortWrite for why a dead stream here used to mean
    # SystemExit(0) with the real work never attempted.
    #
    # RC10: a progress line is not the result, so it never belongs on
    # stdout next to the JSON. `say_error` is Thor's stderr counterpart to
    # `say` and keeps the same colour helper.
    def verbose_output(message)
      return unless options[:verbose]

      BestEffortWrite.attempt { say_error message, :yellow }
    end

    def error_output(message)
      # Kernel#warn is silent when warnings are off. Measured on ruby 3.4.8:
      # `ruby -W0 -e 'warn "MSG"'` prints nothing, `ruby -W0 -e '$stderr.puts
      # "MSG"'` prints MSG. Every command's rescue reports through here, so
      # this is the one line that has to survive -W0; the cop's suggestion
      # would take it away. It does not rescue the detail lines the commands
      # emit with warn -- those already vanish under -W0.
      # rubocop:disable Style/StderrPuts
      $stderr.puts message
      # rubocop:enable Style/StderrPuts
    rescue Errno::EPIPE
      # Same reason as verbose_output. A closed stderr must not turn a real
      # failure into a different one, or mask the exit status the caller
      # needs to see.
      nil
    end

    # Keep the CommandFailed re-raise: ValidateCommand#run prints its own list
    # of errors, so reporting it again here appends a second, redundant
    # `Error: ...` line AFTER that list on every failed `elkrb validate`.
    #
    # Keep the Errno::EPIPE re-raise: a reader hanging up ends a SUCCESSFUL
    # run (`elkrb layout big.json | head`), and Thor turns a re-raised EPIPE
    # into exit 0. Wrap it instead and that clean pipeline starts exiting 1.
    #
    # The report is best-effort; see Elkrb::BestEffortWrite for why, and wrap
    # any new non-result write -- a report, a progress line, anything that
    # is not the write emitting the command's actual output -- the same way.
    def fail_command(error)
      raise error if error.is_a?(CommandFailed) || error.is_a?(Errno::EPIPE)

      message = error.message
      BestEffortWrite.attempt { error_output "Error: #{message}" }
      raise CommandFailed, message
    end
  end
end
