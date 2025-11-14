# frozen_string_literal: true

require "thor"
require "json"
require "yaml"

module Elkrb
  # Command-line interface for elkrb
  #
  # Provides commands for laying out graphs from the command line.
  # Supports JSON and YAML input/output formats.
  class Cli < Thor
    class_option :verbose, type: :boolean, default: false,
                           desc: "Enable verbose output"

    desc "layout FILE", "Layout a graph from a JSON or YAML file"
    option :algorithm, type: :string, default: "layered",
                       desc: "Layout algorithm to use"
    option :output, type: :string, aliases: "-o",
                    desc: "Output file (default: stdout)"
    option :format, type: :string, default: "json",
                    enum: %w[json yaml],
                    desc: "Output format"
    option :spacing, type: :numeric,
                     desc: "Node spacing"
    option :layer_spacing, type: :numeric,
                           desc: "Layer spacing (for layered algorithm)"
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

      # Build layout options
      layout_options = build_layout_options

      verbose_output "Using algorithm: #{layout_options[:algorithm]}"

      # Perform layout
      result = Layout::LayoutEngine.layout(graph_data, layout_options)

      # Output result
      output_result(result)

      verbose_output "Layout complete!"
    rescue StandardError => e
      error_output "Error: #{e.message}"
      exit 1
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
    option :algorithm, type: :string, default: "layered",
                       desc: "Layout algorithm to use"
    option :direction, type: :string,
                       desc: "Layout direction (e.g., DOWN, RIGHT)"
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
      error_output "Error: #{e.message}"
      exit 1
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
      error_output "Error: #{e.message}"
      exit 1
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
      error_output "Error: #{e.message}"
      exit 1
    end

    desc "validate FILE", "Validate ELK graph structure"
    option :strict, type: :boolean, default: false,
                    desc: "Enable strict validation"
    def validate(file)
      require_relative "commands/validate_command"
      Commands::ValidateCommand.new(file, options).run
    rescue StandardError => e
      error_output "Error: #{e.message}"
      exit 1
    end

    desc "batch DIR", "Process multiple files in a directory"
    option :output_dir, type: :string, required: true,
                        desc: "Output directory for generated files"
    option :format, type: :string, default: "svg",
                    desc: "Output format for all files"
    option :algorithm, type: :string, default: "layered",
                       desc: "Layout algorithm to use"
    def batch(directory)
      require_relative "commands/batch_command"
      Commands::BatchCommand.new(directory, options).run
    rescue StandardError => e
      error_output "Error: #{e.message}"
      exit 1
    end

    desc "version", "Show elkrb version"
    def version
      say "elkrb version #{Elkrb::VERSION}", :green
    end

    private

    def read_input_file(file)
      require_relative "graph/graph"
      content = File.read(file)

      case File.extname(file).downcase
      when ".json"
        Elkrb::Graph::Graph.from_json(content)
      when ".yml", ".yaml"
        Elkrb::Graph::Graph.from_yaml(content)
      else
        # Try JSON first, then YAML
        begin
          Elkrb::Graph::Graph.from_json(content)
        rescue JSON::ParserError
          Elkrb::Graph::Graph.from_yaml(content)
        end
      end
    end

    def build_layout_options
      opts = { algorithm: options[:algorithm] }

      # Add spacing options
      opts[:spacing_node_node] = options[:spacing] if options[:spacing]
      opts[:layer_spacing] = options[:layer_spacing] if options[:layer_spacing]

      # Add padding options
      if options[:padding_top] || options[:padding_bottom] ||
          options[:padding_left] || options[:padding_right]
        opts[:padding] = {
          top: options[:padding_top] || 12,
          bottom: options[:padding_bottom] || 12,
          left: options[:padding_left] || 12,
          right: options[:padding_right] || 12,
        }
      end

      opts
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

    def verbose_output(message)
      say message, :yellow if options[:verbose]
    end

    def error_output(message)
      say message, :red
    end
  end
end
