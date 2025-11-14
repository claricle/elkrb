# frozen_string_literal: true

module Elkrb
  module Serializers
    # Serializes ELK graphs to Graphviz DOT format
    #
    # This serializer converts ELK graph structures into DOT format strings
    # that can be rendered by Graphviz. It supports:
    # - Node and edge declarations with attributes
    # - Hierarchical graphs (subgraphs/clusters)
    # - Labels and ports
    # - Layout direction and other properties
    #
    # @example Basic usage
    #   serializer = DotSerializer.new
    #   dot_string = serializer.serialize(graph)
    #   File.write("output.dot", dot_string)
    #
    # @example With options
    #   serializer = DotSerializer.new
    #   dot_string = serializer.serialize(graph,
    #     directed: true,
    #     rankdir: "TB"
    #   )
    class DotSerializer
      # Default indentation width for DOT output
      INDENT_WIDTH = 2

      # @param graph [Elkrb::Graph::Graph] The graph to serialize
      # @param options [Hash] Serialization options
      # @option options [Boolean] :directed (true) Whether graph is directed
      # @option options [String] :rankdir Layout direction (TB, LR, BT, RL)
      # @option options [String] :graph_name Name for the graph
      # @option options [Hash] :graph_attrs Additional graph attributes
      # @option options [Hash] :node_attrs Default node attributes
      # @option options [Hash] :edge_attrs Default edge attributes
      # @return [String] DOT format string
      def serialize(graph, options = {})
        @options = {
          directed: true,
          rankdir: nil,
          graph_name: "G",
          graph_attrs: {},
          node_attrs: {},
          edge_attrs: {},
        }.merge(options)

        @indent_level = 0
        @node_counter = 0
        @cluster_counter = 0

        # Convert hash to Graph if needed
        @graph = graph.is_a?(Hash) ? hash_to_graph(graph) : graph

        lines = []
        lines << graph_declaration
        lines << "{"

        @indent_level += 1

        # Graph attributes
        lines.concat(format_graph_attributes(@graph))

        # Default node and edge attributes
        lines << indent("node #{format_attrs(@options[:node_attrs])}") unless
          @options[:node_attrs].empty?
        lines << indent("edge #{format_attrs(@options[:edge_attrs])}") unless
          @options[:edge_attrs].empty?

        # Process children (nodes)
        if @graph.children && !@graph.children.empty?
          @graph.children.each do |node|
            lines.concat(format_node(node))
          end
        end

        # Process edges
        if @graph.edges && !@graph.edges.empty?
          @graph.edges.each do |edge|
            lines.concat(format_edge(edge))
          end
        end

        @indent_level -= 1
        lines << "}"

        lines.join("\n")
      end

      private

      def hash_to_graph(hash)
        require_relative "../graph/graph"
        Elkrb::Graph::Graph.from_hash(hash)
      end

      # Generate graph declaration
      def graph_declaration
        type = @options[:directed] ? "digraph" : "graph"
        "#{type} #{@options[:graph_name]}"
      end

      # Format graph-level attributes
      def format_graph_attributes(graph)
        attrs = @options[:graph_attrs].dup

        # Add rankdir from options or graph layout options
        if @options[:rankdir]
          attrs[:rankdir] = @options[:rankdir]
        elsif graph.layout_options&.direction
          attrs[:rankdir] = elk_direction_to_rankdir(
            graph.layout_options.direction,
          )
        end

        # Add graph size if specified
        if graph.width && graph.height && graph.width.positive? && graph.height.positive?
          # Convert to inches (DOT uses inches by default)
          attrs[:size] = "#{graph.width / 72},#{graph.height / 72}"
        end

        # Output graph attributes
        attrs.map do |key, value|
          indent("#{key}=#{quote_value(value)}")
        end
      end

      # Format a node with all its properties
      def format_node(node, _parent_id = nil)
        lines = []

        # Hierarchical node - create a subgraph
        if node.hierarchical?
          lines.concat(format_subgraph(node))
        else
          # Simple node
          node_id = sanitize_id(node.id)
          attrs = build_node_attributes(node)

          lines << indent("#{node_id} #{format_attrs(attrs)}")
        end

        # Process child edges if any
        if node.edges && !node.edges.empty?
          node.edges.each do |edge|
            lines.concat(format_edge(edge))
          end
        end

        lines
      end

      # Format a subgraph (hierarchical node)
      def format_subgraph(node)
        lines = []
        cluster_id = "cluster_#{@cluster_counter}"
        @cluster_counter += 1

        lines << indent("subgraph #{cluster_id} {")
        @indent_level += 1

        # Subgraph label
        if node.labels && !node.labels.empty?
          label_text = node.labels.first.text
          lines << indent("label=#{quote_value(label_text)}")
        end

        # Process children
        if node.children && !node.children.empty?
          node.children.each do |child|
            lines.concat(format_node(child, node.id))
          end
        end

        # Process edges within this subgraph
        if node.edges && !node.edges.empty?
          node.edges.each do |edge|
            lines.concat(format_edge(edge))
          end
        end

        @indent_level -= 1
        lines << indent("}")

        lines
      end

      # Build node attribute hash
      def build_node_attributes(node)
        attrs = {}

        # Label
        if node.labels && !node.labels.empty?
          label_text = node.labels.map(&:text).join("\\n")
          attrs[:label] = label_text
        elsif node.id
          attrs[:label] = node.id
        end

        # Size (DOT uses inches)
        if node.width && node.height && node.width.positive? && node.height.positive?
          attrs[:width] = (node.width / 72.0).round(2)
          attrs[:height] = (node.height / 72.0).round(2)
          attrs[:fixedsize] = "true"
        end

        # Position (if laid out)
        if node.x && node.y
          # DOT uses center coordinates, ELK uses top-left
          # Also need to account for height since DOT y goes up
          center_x = node.x + ((node.width || 0) / 2.0)
          center_y = node.y + ((node.height || 0) / 2.0)
          attrs[:pos] = "#{center_x.round(2)},#{center_y.round(2)}!"
        end

        # Shape
        attrs[:shape] = "box" # Default shape for ELK nodes

        # Properties
        if node.properties && node.properties["dot.shape"]
          attrs[:shape] = node.properties["dot.shape"]
        end

        attrs
      end

      # Format an edge
      def format_edge(edge)
        lines = []

        return lines if !edge.sources || edge.sources.empty? ||
          !edge.targets || edge.targets.empty?

        # Get source and target
        source_id = sanitize_id(edge.sources.first)
        target_id = sanitize_id(edge.targets.first)

        # Build edge attributes
        attrs = build_edge_attributes(edge)

        # Edge operator
        op = @options[:directed] ? "->" : "--"

        lines << indent("#{source_id} #{op} #{target_id} #{format_attrs(attrs)}")

        lines
      end

      # Build edge attribute hash
      def build_edge_attributes(edge)
        attrs = {}

        # Label
        if edge.labels && !edge.labels.empty?
          label_text = edge.labels.map(&:text).join("\\n")
          attrs[:label] = label_text
        end

        # Edge routing points
        if edge.sections && !edge.sections.empty?
          section = edge.sections.first
          points = []

          points << section.start_point if section.start_point
          points.concat(section.bend_points) if section.bend_points
          points << section.end_point if section.end_point

          if points.length > 2
            # Build spline path for DOT
            pos_str = points.map do |p|
              "#{p.x.round(2)},#{p.y.round(2)}"
            end.join(" ")
            attrs[:pos] = pos_str
          end
        end

        attrs
      end

      # Format attribute hash to DOT syntax
      def format_attrs(attrs)
        return "" if attrs.empty?

        attr_strs = attrs.map do |key, value|
          "#{key}=#{quote_value(value)}"
        end

        "[#{attr_strs.join(', ')}]"
      end

      # Quote a value appropriately for DOT
      def quote_value(value)
        value_str = value.to_s

        # Check if value needs quoting
        if value_str.match?(/[^a-zA-Z0-9_]/) || value_str.empty?
          # Escape quotes and backslashes
          escaped = value_str.gsub("\\", "\\\\\\\\").gsub('"', '\\"')
          "\"#{escaped}\""
        else
          value_str
        end
      end

      # Sanitize ID for DOT format
      def sanitize_id(id)
        # DOT IDs can contain letters, digits, underscores
        # If ID contains other characters, quote it
        sanitized = id.to_s.gsub(/[^a-zA-Z0-9_]/, "_")

        # If starts with digit, prepend 'n'
        sanitized = "n#{sanitized}" if sanitized.match?(/^[0-9]/)

        sanitized
      end

      # Convert ELK direction to DOT rankdir
      def elk_direction_to_rankdir(direction)
        case direction.to_s.upcase
        when "DOWN"
          "TB"
        when "UP"
          "BT"
        when "RIGHT"
          "LR"
        when "LEFT"
          "RL"
        else
          "TB" # Default
        end
      end

      # Add indentation to a line
      def indent(line)
        (" " * (@indent_level * INDENT_WIDTH)) + line
      end
    end
  end
end
