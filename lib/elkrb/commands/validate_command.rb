# frozen_string_literal: true

require "json"
require "yaml"

require_relative "../errors"
require_relative "../best_effort_write"

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
          summary = "#{@file} has #{errors.length} error(s)"
          BestEffortWrite.attempt do
            $stderr.puts "❌ #{summary}:" # rubocop:disable Style/StderrPuts
            errors.each do |error|
              $stderr.puts "  • #{error}" # rubocop:disable Style/StderrPuts
            end
          end
          raise Elkrb::CommandFailed, summary
        end
      end

      private

      def load_any_format(file)
        raise ArgumentError, "File not found: #{file}" unless File.exist?(file)

        content = File.read(file)

        case File.extname(file).downcase
        when ".json" then parse_json(content)
        when ".yml", ".yaml" then YAML.safe_load(content)
        when ".elkt" then parse_elkt(content)
        else sniff_format(content)
        end
      end

      def parse_json(content)
        JSON.parse(content, symbolize_names: true)
      end

      def parse_elkt(content)
        require_relative "../parsers/elkt_parser"
        Elkrb::Parsers::ElktParser.parse(content)
      end

      def sniff_format(content)
        stripped = content.lstrip

        if stripped.start_with?("{", "[")
          begin
            return parse_json(content)
          rescue JSON::ParserError
            nil
          end
        end

        yaml = YAML.safe_load(content)
        return yaml if yaml.is_a?(Hash) || yaml.is_a?(Array)

        parse_elkt(content)
      rescue Psych::SyntaxError, Elkrb::ParseError
        raise ArgumentError,
              "Unable to parse input file. Supported formats: JSON, YAML, ELKT"
      end

      def validate_graph(graph)
        errors = []

        # Check graph structure
        errors << "Graph must be a Hash" unless graph.is_a?(Hash)
        return errors unless graph.is_a?(Hash)

        # Check required fields
        errors << "Graph missing 'id' field" unless graph[:id] || graph["id"]

        ids, duplicate_errors = collect_ids(graph)
        errors.concat(duplicate_errors)

        # Validate children (nodes)
        children = graph[:children] || graph["children"] || []
        children.each_with_index do |node, idx|
          errors.concat(validate_node(node, "children[#{idx}]", ids))
        end

        # Validate edges
        edges = graph[:edges] || graph["edges"] || []
        edges.each_with_index do |edge, idx|
          errors.concat(validate_edge(edge, "edges[#{idx}]", ids))
        end

        # Strict mode: additional checks
        if @options[:strict]
          errors.concat(validate_strict(graph))
        end

        errors
      end

      def validate_node(node, path, ids)
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
          errors.concat(validate_node(child, "#{path}.children[#{idx}]", ids))
        end

        # Validate ports
        ports = node[:ports] || node["ports"] || []
        ports.each_with_index do |port, idx|
          errors.concat(validate_port(port, "#{path}.ports[#{idx}]"))
        end

        edges = node[:edges] || node["edges"] || []
        edges.each_with_index do |edge, idx|
          errors.concat(validate_edge(edge, "#{path}.edges[#{idx}]", ids))
        end

        errors
      end

      def validate_edge(edge, path, valid_ids)
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

        if sources.is_a?(Array)
          sources.each do |source|
            unless valid_ids.include?(source)
              errors << "#{path}: Edge '#{edge_id}' references unknown " \
                        "source node or port '#{source}'"
            end
          end
        end

        if targets.is_a?(Array)
          targets.each do |target|
            unless valid_ids.include?(target)
              errors << "#{path}: Edge '#{edge_id}' references unknown " \
                        "target node or port '#{target}'"
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

      def collect_ids(graph)
        endpoint_ids = Set.new
        all_ids = Set.new
        errors = []

        collect_container_ids(graph, endpoint_ids, all_ids, errors)

        [endpoint_ids, errors]
      end

      def collect_container_ids(container, endpoint_ids, all_ids, errors)
        children = container[:children] || container["children"] || []
        if children.is_a?(Array)
          children.each do |node|
            collect_node_id(node, endpoint_ids, all_ids, errors)
          end
        end

        edges = container[:edges] || container["edges"] || []
        return unless edges.is_a?(Array)

        edges.each do |edge|
          next unless edge.is_a?(Hash)

          record_id(edge[:id] || edge["id"], all_ids, errors)
        end
      end

      def collect_node_id(node, endpoint_ids, all_ids, errors)
        return unless node.is_a?(Hash)

        record_endpoint_id(node[:id] || node["id"], endpoint_ids,
                           all_ids, errors)

        ports = node[:ports] || node["ports"] || []
        if ports.is_a?(Array)
          ports.each do |port|
            next unless port.is_a?(Hash)

            record_endpoint_id(port[:id] || port["id"], endpoint_ids,
                               all_ids, errors)
          end
        end

        collect_container_ids(node, endpoint_ids, all_ids, errors)
      end

      def record_endpoint_id(id, endpoint_ids, all_ids, errors)
        return unless id

        endpoint_ids.add(id)
        record_id(id, all_ids, errors)
      end

      def record_id(id, all_ids, errors)
        return unless id

        errors << "duplicate id: #{id}" unless all_ids.add?(id)
      end
    end
  end
end
