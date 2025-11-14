# frozen_string_literal: true

require "json"

module Elkrb
  module Serializers
    # Serializer for ELKT (ELK Text) format
    # Converts ELK graph structures to textual ELKT representation
    class ElktSerializer
      def initialize(options = {})
        @indent_size = options[:indent_size] || 2
        @include_comments = options.fetch(:include_comments, true)
      end

      def serialize(graph, _options = {})
        @indent_level = 0
        @output = []

        # Convert to hash using JSON round-trip for Lutaml models
        @graph_hash = if graph.is_a?(Hash)
                        graph
                      elsif graph.respond_to?(:to_json)
                        JSON.parse(graph.to_json, symbolize_names: true)
                      else
                        graph
                      end

        serialize_graph(@graph_hash)

        "#{@output.join("\n")}\n"
      end

      private

      def serialize_graph(graph)
        # Serialize graph-level layout options
        layout_opts = graph[:layoutOptions] || graph["layoutOptions"] || {}
        serialize_layout_options(layout_opts)

        # Add blank line after options if present
        @output << "" if (graph[:layoutOptions] || {}).any?

        # Serialize nodes
        (graph[:children] || []).each do |node|
          serialize_node(node)
        end

        # Add blank line before edges if both nodes and edges exist
        if (graph[:children] || []).any? && (graph[:edges] || []).any?
          @output << ""
        end

        # Serialize edges
        (graph[:edges] || []).each do |edge|
          serialize_edge(edge)
        end
      end

      def serialize_layout_options(options)
        return if options.empty?

        options.each do |key, value|
          # Remove elk. prefix for cleaner output
          display_key = key.to_s.start_with?("elk.") ? key.to_s[4..] : key.to_s

          # Special handling for algorithm and direction
          @output << if display_key == "algorithm"
                       "algorithm: #{value}"
                     elsif display_key == "direction"
                       "direction: #{value}"
                     else
                       "#{display_key}: #{format_value(value)}"
                     end
        end
      end

      def serialize_node(node)
        indent = " " * (@indent_level * @indent_size)

        # Check if node has attributes to serialize in a block
        has_block = node_has_block?(node)

        if has_block
          @output << "#{indent}node #{node[:id]} {"
          @indent_level += 1

          serialize_node_block(node)

          @indent_level -= 1
          @output << "#{indent}}"
        else
          @output << "#{indent}node #{node[:id]}"
        end
      end

      def node_has_block?(node)
        # Node needs a block if it has:
        # - Layout attributes (size, position)
        # - Labels
        # - Ports
        # - Children (nested nodes)
        # - Non-default dimensions

        has_layout = node[:width] && node[:height] &&
          (node[:width] != 40 || node[:height] != 40)
        has_position = node[:x] || node[:y]
        has_labels = (node[:labels] || []).any?
        has_ports = (node[:ports] || []).any?
        has_children = (node[:children] || []).any?
        has_edges = (node[:edges] || []).any?

        has_layout || has_position || has_labels || has_ports ||
          has_children || has_edges
      end

      def serialize_node_block(node)
        indent = " " * (@indent_level * @indent_size)

        # Serialize layout attributes
        if node[:width] && node[:height]
          width = format_number(node[:width])
          height = format_number(node[:height])
          @output << "#{indent}layout [ size: #{width}, #{height} ]"
        end

        if node[:x] && node[:y]
          x = format_number(node[:x])
          y = format_number(node[:y])
          @output << "#{indent}layout [ position: #{x}, #{y} ]"
        end

        # Serialize labels
        (node[:labels] || []).each do |label|
          @output << "#{indent}label \"#{label[:text]}\""
        end

        # Serialize ports
        (node[:ports] || []).each do |port|
          serialize_port(port)
        end

        # Serialize nested nodes
        (node[:children] || []).each do |child|
          serialize_node(child)
        end

        # Serialize nested edges
        (node[:edges] || []).each do |edge|
          serialize_edge(edge)
        end
      end

      def serialize_port(port)
        indent = " " * (@indent_level * @indent_size)

        if port_has_block?(port)
          @output << "#{indent}port #{port[:id]} {"
          @indent_level += 1

          serialize_port_block(port)

          @indent_level -= 1
          @output << "#{indent}}"
        else
          @output << "#{indent}port #{port[:id]}"
        end
      end

      def port_has_block?(port)
        (port[:layoutOptions] || {}).any? ||
          (port[:labels] || []).any?
      end

      def serialize_port_block(port)
        indent = " " * (@indent_level * @indent_size)

        # Serialize port layout options
        (port[:layoutOptions] || {}).each do |key, value|
          display_key = key.to_s.start_with?("elk.") ? key.to_s[4..] : key.to_s
          @output << "#{indent}#{display_key}: #{format_value(value)}"
        end

        # Serialize port labels
        (port[:labels] || []).each do |label|
          @output << "#{indent}label \"#{label[:text]}\""
        end
      end

      def serialize_edge(edge)
        indent = " " * (@indent_level * @indent_size)

        source = edge[:sources]&.first || edge[:source]
        target = edge[:targets]&.first || edge[:target]

        # Add port references if present
        source_ref = if edge[:sourcePort]
                       "#{source}.#{edge[:sourcePort]}"
                     else
                       source
                     end

        target_ref = if edge[:targetPort]
                       "#{target}.#{edge[:targetPort]}"
                     else
                       target
                     end

        # Include edge ID if it's not auto-generated
        @output << if edge[:id] && !edge[:id].to_s.match?(/^e\d+$/)
                     "#{indent}edge #{edge[:id]}: #{source_ref} -> #{target_ref}"
                   else
                     "#{indent}edge #{source_ref} -> #{target_ref}"
                   end
      end

      def format_value(value)
        case value
        when Float
          format_number(value)
        when Integer
          value
        when TrueClass, FalseClass
          value
        else
          value.to_s
        end
      end

      def format_number(num)
        # Remove trailing zeros and decimal point if integer
        formatted = format("%.2f", num).sub(/\.?0+$/, "")
        formatted.empty? ? "0" : formatted
      end
    end
  end
end
