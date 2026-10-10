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

        errors.concat(validate_container(graph))

        errors
      end

      def validate_container(container, path = nil)
        errors = []
        children = collection(container, :children, path, errors)
        edges = collection(container, :edges, path, errors)
        endpoint_ids = descendant_endpoint_ids(children)

        errors.concat(duplicate_id_errors(children, edges))
        children.each_with_index do |node, idx|
          errors.concat(validate_node(node, child_path(path, idx)))
        end
        edges.each_with_index do |edge, idx|
          errors.concat(validate_edge(edge, edge_path(path, idx), endpoint_ids))
        end
        errors.concat(validate_strict(container, path)) if @options[:strict]
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

          if width && !positive_finite_number?(width)
            errors << "#{path}: Node '#{node_id}' has invalid width: #{width}"
          end

          if height && !positive_finite_number?(height)
            errors << "#{path}: Node '#{node_id}' has invalid height: #{height}"
          end
        end

        # Validate ports
        ports = collection(node, :ports, path, errors)
        ports.each_with_index do |port, idx|
          errors.concat(validate_port(port, "#{path}.ports[#{idx}]"))
        end

        errors.concat(validate_container(node, path))
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

        { source: sources, target: targets }.each do |role, endpoints|
          next unless endpoints.is_a?(Array)

          endpoints.each do |endpoint|
            matches = valid_ids.fetch(endpoint, 0)
            if matches.zero?
              errors << "#{path}: Edge '#{edge_id}' references unknown " \
                        "#{role} node or port '#{endpoint}'"
            elsif matches > 1
              errors << "#{path}: Edge '#{edge_id}' references ambiguous " \
                        "#{role} node or port '#{endpoint}'"
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

      def validate_strict(graph, path)
        errors = []

        # Check for layout options
        layout_options = value(graph, :layoutOptions)
        if !layout_options.nil? && !layout_options.is_a?(Hash)
          prefix = path ? "#{path}." : ""
          errors << "#{prefix}layoutOptions must be a Hash"
        end

        errors
      end

      def collection(container, key, path, errors)
        items = value(container, key)
        return [] if items.nil?
        return items if items.is_a?(Array)

        prefix = path ? "#{path}." : ""
        errors << "#{prefix}#{key} must be an Array"
        []
      end

      def value(hash, key)
        return hash[key] if hash.key?(key)

        hash[key.to_s]
      end

      def child_path(path, index)
        [path, "children[#{index}]"].compact.join(".")
      end

      def edge_path(path, index)
        [path, "edges[#{index}]"].compact.join(".")
      end

      def positive_finite_number?(number)
        number.is_a?(Numeric) && number.finite? && number.positive?
      end

      def descendant_endpoint_ids(children, ids = Hash.new(0))
        children.each do |node|
          next unless node.is_a?(Hash)

          ids[value(node, :id)] += 1 if value(node, :id)
          Array(value(node, :ports)).each do |port|
            id = value(port, :id) if port.is_a?(Hash)
            ids[id] += 1 if id
          end
          descendant_endpoint_ids(Array(value(node, :children)), ids)
        end
        ids
      end

      def duplicate_id_errors(children, edges)
        ids = Set.new
        errors = []
        children.each do |node|
          next unless node.is_a?(Hash)

          record_id(value(node, :id), ids, errors)
          Array(value(node, :ports)).each do |port|
            record_id(value(port, :id), ids, errors) if port.is_a?(Hash)
          end
        end
        edges.each do |edge|
          record_id(value(edge, :id), ids, errors) if edge.is_a?(Hash)
        end
        errors
      end

      def record_id(id, ids, errors)
        errors << "duplicate id: #{id}" if id && !ids.add?(id)
      end
    end
  end
end
