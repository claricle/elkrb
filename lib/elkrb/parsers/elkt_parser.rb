# frozen_string_literal: true

module Elkrb
  module Parsers
    # Parser for ELKT (ELK Text) format
    # Parses textual graph definitions into ELK graph structures
    class ElktParser
      class ParseError < StandardError; end

      def self.parse(input)
        new(input).parse
      end

      def initialize(input)
        @input = input
        @line_number = 0
        @graph = {
          id: "root",
          layoutOptions: {},
          children: [],
          edges: [],
        }
        @node_map = {}
        @current_context = [@graph]
      end

      def parse
        lines = preprocess(@input)
        parse_lines(lines)
        @graph
      end

      private

      def preprocess(input)
        # Remove block comments
        input = input.gsub(%r{/\*.*?\*/}m, "")

        # Split into lines and remove line comments
        lines = input.split("\n").map do |line|
          line.sub(%r{//.*$}, "").strip
        end

        # Remove empty lines
        lines.reject(&:empty?)
      end

      def parse_lines(lines)
        lines.each_with_index do |line, idx|
          @line_number = idx + 1
          parse_line(line)
        end
      end

      def parse_line(line)
        case line
        when /^algorithm:\s*(.+)$/
          parse_algorithm($1.strip)
        when /^direction:\s*(.+)$/
          parse_direction($1.strip)
        when /^([\w.]+):\s*(.+)$/
          parse_property($1.strip, $2.strip)
        when /^node\s+(\w+)\s*\{/
          parse_node_with_block($1)
        when /^node\s+(\w+)\s*$/
          parse_simple_node($1)
        when /^\}/
          close_block
        when /^edge\s+(.+)$/
          parse_edge($1.strip)
        when /^layout\s*\[\s*(.+?)\s*\]/
          parse_layout_block($1)
        when /^port\s+(\w+)/
          parse_port(line)
        when /^label\s+"([^"]+)"/
          parse_label($1)
        else
          # Ignore unknown lines or handle as needed
        end
      end

      def parse_algorithm(value)
        current_node[:layoutOptions] ||= {}
        current_node[:layoutOptions]["elk.algorithm"] = value
      end

      def parse_direction(value)
        current_node[:layoutOptions] ||= {}
        current_node[:layoutOptions]["elk.direction"] = value
      end

      def parse_property(key, value)
        current_node[:layoutOptions] ||= {}

        # Convert property name to ELK format
        elk_key = key.start_with?("elk.") ? key : "elk.#{key}"

        # Parse value
        parsed_value = parse_value(value)
        current_node[:layoutOptions][elk_key] = parsed_value
      end

      def parse_value(value)
        case value
        when /^-?\d+\.\d+$/
          value.to_f
        when /^-?\d+$/
          value.to_i
        when /^true$/i
          true
        when /^false$/i
          false
        else
          value
        end
      end

      def parse_simple_node(node_id)
        node = create_node(node_id)
        current_node[:children] ||= []
        current_node[:children] << node
        @node_map[node_id] = node
      end

      def parse_node_with_block(node_id)
        node = create_node(node_id)
        current_node[:children] ||= []
        current_node[:children] << node
        @node_map[node_id] = node
        @current_context.push(node)
      end

      def create_node(node_id)
        {
          id: node_id,
          width: 40,
          height: 40,
          layoutOptions: {},
        }
      end

      def parse_layout_block(content)
        # Parse layout [ size: 30, 30 ] or similar
        if content =~ /size:\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)/
          width = $1.to_f
          height = $2.to_f
          current_node[:width] = width
          current_node[:height] = height
        elsif content =~ /position:\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)/
          x = $1.to_f
          y = $2.to_f
          current_node[:x] = x
          current_node[:y] = y
        end
      end

      def parse_edge(edge_spec)
        # Parse: node1 -> node2
        # Or: edge_id: node1 -> node2
        # Or: node1.port1 -> node2.port2

        if edge_spec =~ /^(\w+):\s*(.+)$/
          edge_id = $1
          edge_spec = $2
        else
          edge_id = generate_edge_id
        end

        unless edge_spec =~ /^(.+?)\s*->\s*(.+)$/
          raise ParseError,
                "Invalid edge syntax at line #{@line_number}: #{edge_spec}"
        end

        source_spec = $1.strip
        target_spec = $2.strip

        edge = create_edge(edge_id, source_spec, target_spec)
        current_node[:edges] ||= []
        current_node[:edges] << edge
      end

      def create_edge(edge_id, source_spec, target_spec)
        source_parts = source_spec.split(".")
        target_parts = target_spec.split(".")

        edge = {
          id: edge_id,
          sources: [source_parts[0]],
          targets: [target_parts[0]],
        }

        # Add port references if present
        if source_parts.length > 1
          edge[:sourcePort] = source_parts[1]
        end

        if target_parts.length > 1
          edge[:targetPort] = target_parts[1]
        end

        edge
      end

      def parse_port(line)
        # Parse: port port_id { ... }
        if line =~ /^port\s+(\w+)\s*\{/
          port_id = $1
          port = {
            id: port_id,
            layoutOptions: {},
          }
          current_node[:ports] ||= []
          current_node[:ports] << port
          @current_context.push(port)
        elsif line =~ /^port\s+(\w+)\s*$/
          port_id = $1
          port = {
            id: port_id,
          }
          current_node[:ports] ||= []
          current_node[:ports] << port
        end
      end

      def parse_label(text)
        label = {
          text: text,
          width: text.length * 7.0,
          height: 14.0,
        }
        current_node[:labels] ||= []
        current_node[:labels] << label
      end

      def close_block
        @current_context.pop if @current_context.length > 1
      end

      def current_node
        @current_context.last
      end

      def generate_edge_id
        "e#{current_node[:edges]&.length || 0}"
      end
    end
  end
end
