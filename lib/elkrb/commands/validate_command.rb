# frozen_string_literal: true

require "json"
require "yaml"

module Elkrb
  module Commands
    # Command for validating ELK graph structure
    # Checks for required fields, valid relationships, and structural integrity
    class ValidateCommand
      def initialize(file, options)
        @file = file
        @options = options
      end

      def run
        # Load and validate graph
        graph = load_any_format(@file)
        errors = validate_graph(graph)

        if errors.empty?
          puts "✅ #{@file} is valid"
        else
          puts "❌ #{@file} has #{errors.length} error(s):"
          errors.each { |e| puts "  • #{e}" }
          exit 1
        end
      end

      private

      def load_any_format(file)
        raise ArgumentError, "File not found: #{file}" unless File.exist?(file)

        require_relative "../graph/graph"
        content = File.read(file)
        ext = File.extname(file).downcase

        graph = case ext
                when ".json"
                  Elkrb::Graph::Graph.from_json(content)
                when ".yml", ".yaml"
                  Elkrb::Graph::Graph.from_yaml(content)
                when ".elkt"
                  require_relative "../parsers/elkt_parser"
                  Elkrb::Parsers::ElktParser.parse(content)
                else
                  detect_and_parse(content)
                end

        # Convert to hash for validation
        if graph.is_a?(Hash)
          graph
        else
          JSON.parse(graph.to_json,
                     symbolize_names: true)
        end
      end

      def detect_and_parse(content)
        require_relative "../graph/graph"

        # Try JSON first
        begin
          return Elkrb::Graph::Graph.from_json(content)
        rescue JSON::ParserError
          # Not JSON
        end

        # Try YAML
        begin
          return Elkrb::Graph::Graph.from_yaml(content)
        rescue Psych::SyntaxError
          # Not YAML
        end

        # Try ELKT
        begin
          require_relative "../parsers/elkt_parser"
          Elkrb::Parsers::ElktParser.parse(content)
        rescue StandardError
          raise ArgumentError, "Unable to parse input file"
        end
      end

      def validate_graph(graph)
        errors = []

        # Check graph structure
        errors << "Graph must be a Hash" unless graph.is_a?(Hash)
        return errors unless graph.is_a?(Hash)

        # Check required fields
        errors << "Graph missing 'id' field" unless graph[:id] || graph["id"]

        # Validate children (nodes)
        children = graph[:children] || graph["children"] || []
        children.each_with_index do |node, idx|
          errors.concat(validate_node(node, "children[#{idx}]"))
        end

        # Validate edges
        edges = graph[:edges] || graph["edges"] || []
        edges.each_with_index do |edge, idx|
          errors.concat(validate_edge(edge, "edges[#{idx}]",
                                      collect_node_ids(graph)))
        end

        # Strict mode: additional checks
        if @options[:strict]
          errors.concat(validate_strict(graph))
        end

        errors
      end

      def validate_node(node, path)
        errors = []

        errors << "#{path}: Node must be a Hash" unless node.is_a?(Hash)
        return errors unless node.is_a?(Hash)

        # Check required fields
        node_id = node[:id] || node["id"]
        errors << "#{path}: Node missing 'id' field" unless node_id

        # Check dimensions (recommended but not required unless strict)
        if @options[:strict]
          width = node[:width] || node["width"]
          height = node[:height] || node["height"]

          errors << "#{path}: Node '#{node_id}' missing 'width'" unless width
          errors << "#{path}: Node '#{node_id}' missing 'height'" unless height

          if width && (!width.is_a?(Numeric) || width <= 0)
            errors << "#{path}: Node '#{node_id}' has invalid width: #{width}"
          end

          if height && (!height.is_a?(Numeric) || height <= 0)
            errors << "#{path}: Node '#{node_id}' has invalid height: #{height}"
          end
        end

        # Validate nested children
        children = node[:children] || node["children"] || []
        children.each_with_index do |child, idx|
          errors.concat(validate_node(child, "#{path}.children[#{idx}]"))
        end

        # Validate ports
        ports = node[:ports] || node["ports"] || []
        ports.each_with_index do |port, idx|
          errors.concat(validate_port(port, "#{path}.ports[#{idx}]"))
        end

        errors
      end

      def validate_edge(edge, path, valid_node_ids)
        errors = []

        errors << "#{path}: Edge must be a Hash" unless edge.is_a?(Hash)
        return errors unless edge.is_a?(Hash)

        # Check required fields
        edge_id = edge[:id] || edge["id"]
        sources = edge[:sources] || edge["sources"]
        targets = edge[:targets] || edge["targets"]

        errors << "#{path}: Edge missing 'id' field" unless edge_id
        errors << "#{path}: Edge '#{edge_id}' missing 'sources' field" unless sources
        errors << "#{path}: Edge '#{edge_id}' missing 'targets' field" unless targets

        # Validate sources and targets are arrays
        if sources && !sources.is_a?(Array)
          errors << "#{path}: Edge '#{edge_id}' sources must be an array"
        end

        if targets && !targets.is_a?(Array)
          errors << "#{path}: Edge '#{edge_id}' targets must be an array"
        end

        # Check that sources and targets reference valid nodes (in strict mode)
        if @options[:strict] && sources.is_a?(Array) && targets.is_a?(Array)
          sources.each do |source|
            unless valid_node_ids.include?(source)
              errors << "#{path}: Edge '#{edge_id}' references unknown source node '#{source}'"
            end
          end

          targets.each do |target|
            unless valid_node_ids.include?(target)
              errors << "#{path}: Edge '#{edge_id}' references unknown target node '#{target}'"
            end
          end
        end

        errors
      end

      def validate_port(port, path)
        errors = []

        errors << "#{path}: Port must be a Hash" unless port.is_a?(Hash)
        return errors unless port.is_a?(Hash)

        # Check required fields
        port_id = port[:id] || port["id"]
        errors << "#{path}: Port missing 'id' field" unless port_id

        errors
      end

      def validate_strict(graph)
        errors = []

        # Check for layout options
        layout_options = graph[:layoutOptions] || graph["layoutOptions"]
        if layout_options && !layout_options.is_a?(Hash)
          errors << "layoutOptions must be a Hash"
        end

        errors
      end

      def collect_node_ids(graph, ids = [])
        children = graph[:children] || graph["children"] || []

        children.each do |node|
          node_id = node[:id] || node["id"]
          ids << node_id if node_id

          # Recursively collect from nested children
          collect_node_ids(node, ids)
        end

        ids
      end
    end
  end
end
