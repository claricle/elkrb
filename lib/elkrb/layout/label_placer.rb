# frozen_string_literal: true

require_relative "../options/resolver"

module Elkrb
  module Layout
    # Module to add automatic label placement to layout algorithms.
    # Handles positioning of node labels, edge labels, and port labels.
    # The including class sets @resolver, as BaseAlgorithm does.
    module LabelPlacer
      OPPOSITE_SIDE = { left: :right, right: :left, top: :bottom, bottom: :top }.freeze
      private_constant :OPPOSITE_SIDE

      # Place all labels in the graph after layout is complete.
      #
      # @param graph [Graph::Graph] The laid out graph
      def place_labels(graph)
        return unless graph

        # Place node labels
        place_node_labels(graph) if graph.children

        # Place edge labels
        place_edge_labels(graph) if graph.edges
      end

      private

      # ELK treats a missing width/height as 0 (compound nodes and
      # deserialized labels commonly omit size).
      def width_of(element)
        element.width || 0.0
      end

      def height_of(element)
        element.height || 0.0
      end

      # Place labels for all nodes in the graph. Node and port labels are
      # owner-relative: (0, 0) is the owner's top-left corner.
      def place_node_labels(graph)
        graph.children.each do |node|
          if node.labels && !node.labels.empty?
            node.labels.each_with_index do |label, index|
              place_node_label(node, label, index)
            end
          end

          place_port_labels(node) if node.ports && !node.ports.empty?
        end
      end

      # Place a single node label. Without a placement option the label is
      # not moved, as in ELK: it keeps its coordinates, or (0, 0) if it has
      # none.
      def place_node_label(node, label, index = 0)
        placement = label_placement_option(node, "elk.nodeLabels.placement")
        tokens = placement_tokens(placement)
        if tokens.empty?
          label.x ||= 0.0
          label.y ||= 0.0
          return
        end

        vertical = vertical_of(tokens)
        horizontal = horizontal_of(tokens)

        if tokens.include?("OUTSIDE")
          place_label_outside_node(node, label, vertical, horizontal, index)
        else
          place_label_inside_node(node, label, vertical, horizontal, index)
        end
      end

      # The upcased tokens of a placement value. Accepts ELK's
      # "[H_CENTER,V_CENTER,INSIDE]" and the space-separated
      # "INSIDE V_CENTER H_CENTER".
      def placement_tokens(placement)
        placement.to_s.upcase.split(/[\s,\[\]]+/).reject(&:empty?)
      end

      # :top, :center or :bottom. V_TOP is also spelled TOP.
      def vertical_of(tokens)
        return :top if tokens.intersect?(%w[V_TOP TOP])
        return :bottom if tokens.intersect?(%w[V_BOTTOM BOTTOM])

        :center
      end

      # :left, :center or :right. H_LEFT is also spelled LEFT.
      def horizontal_of(tokens)
        return :left if tokens.intersect?(%w[H_LEFT LEFT])
        return :right if tokens.intersect?(%w[H_RIGHT RIGHT])

        :center
      end

      # Place a label inside the node, relative to the node's origin.
      def place_label_inside_node(node, label, vertical, horizontal, index)
        padding = label_padding_option(node)
        offset = index * (height_of(label) + padding)

        label.x = inside_x(node, label, horizontal, padding)
        label.y =
          case vertical
          when :top then padding + offset
          when :bottom then height_of(node) - height_of(label) - padding - offset
          else (height_of(node) - height_of(label)) / 2.0
          end
      end

      def inside_x(node, label, horizontal, padding)
        case horizontal
        when :left then padding
        when :right then width_of(node) - width_of(label) - padding
        else (width_of(node) - width_of(label)) / 2.0
        end
      end

      # Place a label outside the node, relative to the node's origin. Above
      # or below when a vertical side is named, otherwise beside. Naming no
      # side at all places it above.
      def place_label_outside_node(node, label, vertical, horizontal, index)
        margin = label_margin_option(node)
        offset = index * (height_of(label) + margin)

        if vertical == :center && horizontal != :center
          place_label_beside_node(node, label, horizontal, margin)
        elsif vertical == :bottom
          label.x = outside_x(node, label, horizontal)
          label.y = height_of(node) + margin + offset
        else
          label.x = outside_x(node, label, horizontal)
          label.y = -height_of(label) - margin - offset
        end
      end

      def outside_x(node, label, horizontal)
        case horizontal
        when :left then 0.0
        when :right then width_of(node) - width_of(label)
        else (width_of(node) - width_of(label)) / 2.0
        end
      end

      def place_label_beside_node(node, label, horizontal, margin)
        label.x =
          if horizontal == :left
            -width_of(label) - margin
          else
            width_of(node) + margin
          end
        label.y = (height_of(node) - height_of(label)) / 2.0
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

      # Place a port label, relative to the port's origin. OUTSIDE (the
      # default) puts it beside the port away from the node, INSIDE on the
      # node's side of the port.
      def place_port_label(node, port, label, index)
        placement = label_placement_option(port, "elk.portLabels.placement") ||
          "OUTSIDE"
        side = port_side(node, port)
        side = OPPOSITE_SIDE.fetch(side) if placement_tokens(placement).include?("INSIDE")

        place_port_label_by_side(label, port, side, label_margin_option(port), index)
      end

      # Determine which side of the node the port is on.
      def port_side(node, port)
        port_x = port.x || 0
        port_y = port.y || 0

        # Check which edge the port is closest to
        left_dist = port_x
        right_dist = width_of(node) - port_x
        top_dist = port_y
        bottom_dist = height_of(node) - port_y

        min_dist = [left_dist, right_dist, top_dist, bottom_dist].min

        case min_dist
        when left_dist then :left
        when right_dist then :right
        when top_dist then :top
        else :bottom
        end
      end

      # Place a port label on the given side of the port. Stacked labels
      # step along the side by their own height.
      def place_port_label_by_side(label, port, side, margin, index)
        step = index * (height_of(label) + margin)

        case side
        when :left, :right
          label.x = side == :left ? -width_of(label) - margin : width_of(port) + margin
          label.y = ((height_of(port) - height_of(label)) / 2.0) + step
        when :top
          label.x = (width_of(port) - width_of(label)) / 2.0
          label.y = -height_of(label) - margin - step
        when :bottom
          label.x = (width_of(port) - width_of(label)) / 2.0
          label.y = height_of(port) + margin + step
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
          place_edge_label_on_section(edge, edge.sections.first, label, index)
        else
          # No sections, estimate from source/target
          place_edge_label_estimated(edge, label, index)
        end
      end

      # Place an edge label on an edge section, in the section's frame. The
      # label's own elk.edgeLabels.placement wins over the edge's.
      def place_edge_label_on_section(edge, section, label, index)
        tokens = placement_tokens(
          @resolver.get("elk.edgeLabels.placement", label, edge),
        )
        offset = index * (height_of(label) + 2) # Stack multiple labels

        anchor =
          if tokens.include?("HEAD")
            above(section.end_point, label)
          elsif tokens.include?("TAIL")
            above(section.start_point, label)
          else
            calculate_edge_center(section)
          end

        label.x = anchor[:x] - (width_of(label) / 2.0)
        label.y = anchor[:y] - (height_of(label) / 2.0) + offset
      end

      # HEAD and TAIL labels sit just above the end point they name.
      def above(point, label)
        { x: point.x, y: point.y - (height_of(label) / 2.0) - 5 }
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

        return { x: points.first.x, y: points.first.y } if total_length.zero?

        # Find point at half the total length
        target_length = total_length / 2.0
        current_length = 0.0

        (0...lengths.length).each do |i|
          if current_length + lengths[i] >= target_length
            # Interpolate between points[i] and points[i+1]
            ratio = lengths[i].zero? ? 0.0 : (target_length - current_length) / lengths[i]
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

      # Get the label placement an element names, or nil. The element's own
      # options come before the call's: for a port, `label.placement` is one
      # of them, though the registry aliases it to nodes. Because it is that
      # alias, a port that names elk.nodeLabels.placement is read the same way.
      def label_placement_option(element, option_id)
        [option_id, "label.placement"].each do |id|
          own = own_option(id, element)
          return own if own
        end
        @resolver.get(option_id, element, default: nil)
      end

      # An element's own option, ignoring the call's options.
      def own_option(id, element)
        (@own_options ||= Options::Resolver.new).get(id, element, default: nil)
      end

      # Get label padding option.
      def label_padding_option(element)
        @resolver.get("label.padding", element)
      end

      # Get label margin option.
      def label_margin_option(element)
        @resolver.get("label.margin", element)
      end
    end
  end
end
