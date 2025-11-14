# frozen_string_literal: true

module Elkrb
  module Layout
    # Module to add automatic label placement to layout algorithms.
    # Handles positioning of node labels, edge labels, and port labels.
    module LabelPlacer
      # Place all labels in the graph after layout is complete.
      #
      # @param graph [Graph::Graph] The laid out graph
      def place_labels(graph)
        return unless graph

        # Place node labels
        place_node_labels(graph) if graph.children

        # Place edge labels
        place_edge_labels(graph) if graph.edges

        # Recursively place labels in hierarchical graphs
        place_hierarchical_labels(graph) if graph.hierarchical?
      end

      private

      # Place labels for all nodes in the graph.
      def place_node_labels(graph)
        graph.children.each do |node|
          next unless node.labels && !node.labels.empty?

          node.labels.each_with_index do |label, index|
            place_node_label(node, label, index)
          end

          # Place port labels if node has ports
          place_port_labels(node) if node.ports && !node.ports.empty?
        end
      end

      # Place a single node label.
      def place_node_label(node, label, index = 0)
        placement = label_placement_option(node, "node.label.placement") ||
          "INSIDE CENTER"

        case placement.upcase
        when /INSIDE/
          place_label_inside_node(node, label, placement, index)
        when /OUTSIDE/
          place_label_outside_node(node, label, placement, index)
        else
          # Default: center inside
          place_label_center(node, label)
        end
      end

      # Place label inside the node bounds.
      def place_label_inside_node(node, label, placement, index)
        case placement.upcase
        when /TOP/
          place_label_inside_top(node, label, index)
        when /BOTTOM/
          place_label_inside_bottom(node, label, index)
        when /LEFT/
          place_label_inside_left(node, label, index)
        when /RIGHT/
          place_label_inside_right(node, label, index)
        else
          place_label_center(node, label)
        end
      end

      # Place label outside the node bounds.
      def place_label_outside_node(node, label, placement, _index)
        margin = label_margin_option(node)

        case placement.upcase
        when /TOP/
          label.x = node.x + ((node.width - label.width) / 2.0)
          label.y = node.y - label.height - margin
        when /BOTTOM/
          label.x = node.x + ((node.width - label.width) / 2.0)
          label.y = node.y + node.height + margin
        when /LEFT/
          label.x = node.x - label.width - margin
          label.y = node.y + ((node.height - label.height) / 2.0)
        when /RIGHT/
          label.x = node.x + node.width + margin
          label.y = node.y + ((node.height - label.height) / 2.0)
        end
      end

      # Place label at various inside positions.
      def place_label_inside_top(node, label, index)
        padding = label_padding_option(node)
        y_offset = index * (label.height + padding)

        label.x = node.x + ((node.width - label.width) / 2.0)
        label.y = node.y + padding + y_offset
      end

      def place_label_inside_bottom(node, label, index)
        padding = label_padding_option(node)
        y_offset = index * (label.height + padding)

        label.x = node.x + ((node.width - label.width) / 2.0)
        label.y = node.y + node.height - label.height - padding - y_offset
      end

      def place_label_inside_left(node, label, index)
        padding = label_padding_option(node)
        y_offset = index * (label.height + padding)

        label.x = node.x + padding
        label.y = node.y + padding + y_offset
      end

      def place_label_inside_right(node, label, index)
        padding = label_padding_option(node)
        y_offset = index * (label.height + padding)

        label.x = node.x + node.width - label.width - padding
        label.y = node.y + padding + y_offset
      end

      def place_label_center(node, label)
        label.x = node.x + ((node.width - label.width) / 2.0)
        label.y = node.y + ((node.height - label.height) / 2.0)
      end

      # Place labels for all ports on a node.
      def place_port_labels(node)
        node.ports.each do |port|
          next unless port.labels && !port.labels.empty?

          port.labels.each_with_index do |label, index|
            place_port_label(node, port, label, index)
          end
        end
      end

      # Place a port label.
      def place_port_label(node, port, label, _index)
        # Port position relative to node
        port_x = node.x + (port.x || 0)
        port_y = node.y + (port.y || 0)

        placement = label_placement_option(port, "port.label.placement") ||
          "OUTSIDE"

        margin = label_margin_option(port)

        case placement.upcase
        when /INSIDE/
          # Place inside port (if port is large enough)
          label.x = port_x + ((port.width - label.width) / 2.0)
          label.y = port_y + ((port.height - label.height) / 2.0)
        else
          # Default: outside, positioned based on port side
          side = port_side(node, port)
          place_port_label_by_side(label, port_x, port_y, port, side, margin)
        end
      end

      # Determine which side of the node the port is on.
      def port_side(node, port)
        port_x = port.x || 0
        port_y = port.y || 0

        # Check which edge the port is closest to
        left_dist = port_x
        right_dist = node.width - port_x
        top_dist = port_y
        bottom_dist = node.height - port_y

        min_dist = [left_dist, right_dist, top_dist, bottom_dist].min

        case min_dist
        when left_dist then :left
        when right_dist then :right
        when top_dist then :top
        else :bottom
        end
      end

      # Place port label based on port side.
      def place_port_label_by_side(label, port_x, port_y, port, side, margin)
        case side
        when :left
          label.x = port_x - label.width - margin
          label.y = port_y + ((port.height - label.height) / 2.0)
        when :right
          label.x = port_x + port.width + margin
          label.y = port_y + ((port.height - label.height) / 2.0)
        when :top
          label.x = port_x + ((port.width - label.width) / 2.0)
          label.y = port_y - label.height - margin
        when :bottom
          label.x = port_x + ((port.width - label.width) / 2.0)
          label.y = port_y + port.height + margin
        end
      end

      # Place labels for all edges in the graph.
      def place_edge_labels(graph)
        graph.edges.each do |edge|
          next unless edge.labels && !edge.labels.empty?

          edge.labels.each_with_index do |label, index|
            place_edge_label(edge, label, index)
          end
        end
      end

      # Place a single edge label.
      def place_edge_label(edge, label, index)
        # Get edge path (sections with bend points)
        if edge.sections && !edge.sections.empty?
          place_edge_label_on_section(edge.sections.first, label, index)
        else
          # No sections, estimate from source/target
          place_edge_label_estimated(edge, label, index)
        end
      end

      # Place edge label on an edge section.
      def place_edge_label_on_section(section, label, index)
        # Calculate center point of the edge path
        center = calculate_edge_center(section)

        placement = "CENTER" # Could be configurable

        offset = index * (label.height + 2) # Stack multiple labels

        case placement.upcase
        when /CENTER/
          label.x = center[:x] - (label.width / 2.0)
          label.y = center[:y] - (label.height / 2.0) + offset
        when /HEAD/
          label.x = section.end_point.x - (label.width / 2.0)
          label.y = section.end_point.y - label.height - 5 + offset
        when /TAIL/
          label.x = section.start_point.x - (label.width / 2.0)
          label.y = section.start_point.y - label.height - 5 + offset
        end
      end

      # Calculate the center point of an edge section.
      def calculate_edge_center(section)
        points = [section.start_point]
        points.concat(section.bend_points) if section.bend_points
        points << section.end_point

        # Find midpoint along the path
        total_length = 0.0
        lengths = []

        (0...(points.length - 1)).each do |i|
          p1 = points[i]
          p2 = points[i + 1]
          length = Math.sqrt(((p2.x - p1.x)**2) + ((p2.y - p1.y)**2))
          lengths << length
          total_length += length
        end

        # Find point at half the total length
        target_length = total_length / 2.0
        current_length = 0.0

        (0...lengths.length).each do |i|
          if current_length + lengths[i] >= target_length
            # Interpolate between points[i] and points[i+1]
            ratio = (target_length - current_length) / lengths[i]
            p1 = points[i]
            p2 = points[i + 1]

            return {
              x: p1.x + (ratio * (p2.x - p1.x)),
              y: p1.y + (ratio * (p2.y - p1.y)),
            }
          end
          current_length += lengths[i]
        end

        # Fallback: use middle point
        mid_point = points[points.length / 2]
        { x: mid_point.x, y: mid_point.y }
      end

      # Estimate edge label position when no sections available.
      def place_edge_label_estimated(_edge, label, _index)
        # This is a fallback - in practice edges should have sections
        # after routing, but we handle the case anyway
        label.x = 0
        label.y = 0
      end

      # Place labels in hierarchical child nodes.
      def place_hierarchical_labels(graph)
        return unless graph.children

        graph.children.each do |node|
          next unless node.hierarchical?

          # Create temporary graph for children
          child_graph = Graph::Graph.new(
            children: node.children,
            edges: node.edges,
          )

          # Recursively place labels
          place_labels(child_graph)
        end
      end

      # Get label placement option from node/port layout options.
      def label_placement_option(element, option_key)
        return nil unless element.layout_options

        element.layout_options.properties&.[](option_key) ||
          element.layout_options.properties&.[]("label.placement")
      end

      # Get label padding option.
      def label_padding_option(element)
        return 5.0 unless element.layout_options

        element.layout_options.properties&.[]("label.padding") || 5.0
      end

      # Get label margin option.
      def label_margin_option(element)
        return 5.0 unless element.layout_options

        element.layout_options.properties&.[]("label.margin") || 5.0
      end
    end
  end
end
