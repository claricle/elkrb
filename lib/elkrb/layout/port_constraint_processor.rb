# frozen_string_literal: true

module Elkrb
  module Layout
    # Port Constraint Processor
    #
    # This module provides port constraint processing functionality for
    # layout algorithms. It handles:
    # - Automatic port side detection from positions
    # - Port grouping by side
    # - Port ordering within each side
    # - Port positioning on node boundaries
    module PortConstraintProcessor
      # Apply port constraints to all nodes in the graph
      #
      # @param graph [Elkrb::Graph::Graph] The graph to process
      def apply_port_constraints(graph)
        return unless graph.children

        graph.children.each do |node|
          process_node_ports(node)
        end
      end

      private

      # Process ports for a single node
      #
      # @param node [Elkrb::Graph::Node] The node to process
      def process_node_ports(node)
        return unless node.ports && !node.ports.empty?
        return unless node.width && node.height && node.width.positive? && node.height.positive?

        # Detect sides if not specified
        detect_port_sides(node)

        # Group ports by side
        ports_by_side = group_ports_by_side(node.ports)

        # Apply ordering within each side
        ports_by_side.each do |side, ports|
          order_ports_on_side(node, side, ports)
        end

        # Position ports on node boundaries
        position_ports_on_boundaries(node, ports_by_side)
      end

      # Detect port sides for ports with UNDEFINED side
      #
      # @param node [Elkrb::Graph::Node] The node containing the ports
      def detect_port_sides(node)
        node.ports.each do |port|
          if port.side == Graph::Port::UNDEFINED
            detected_side = port.detect_side(node.width, node.height)
            port.side = detected_side
          end
        end
      end

      # Group ports by their side
      #
      # @param ports [Array<Elkrb::Graph::Port>] The ports to group
      # @return [Hash<String, Array<Elkrb::Graph::Port>>] Ports grouped by side
      def group_ports_by_side(ports)
        ports.group_by(&:side)
      end

      # Order ports on a specific side
      #
      # Ports are sorted by:
      # 1. Index (if specified and >= 0)
      # 2. Position along the side (x for horizontal sides, y for vertical)
      #
      # @param node [Elkrb::Graph::Node] The node containing the ports
      # @param side [String] The side to order ports on
      # @param ports [Array<Elkrb::Graph::Port>] The ports on this side
      def order_ports_on_side(_node, side, ports)
        # Sort by index if specified, otherwise by position
        ports.sort_by! do |port|
          if port.index >= 0
            port.index
          elsif [Graph::Port::NORTH, Graph::Port::SOUTH].include?(side)
            # Horizontal sides: sort by x position
            port.x || 0
          else
            # Vertical sides: sort by y position
            port.y || 0
          end
        end

        # Assign sequential indices to ports without explicit index
        ports.each_with_index do |port, idx|
          port.index = idx if port.index.negative?
        end
      end

      # Position ports on node boundaries
      #
      # @param node [Elkrb::Graph::Node] The node containing the ports
      # @param ports_by_side [Hash<String, Array<Elkrb::Graph::Port>>] Ports grouped by side
      def position_ports_on_boundaries(node, ports_by_side)
        # NORTH: top edge, distributed horizontally
        if ports_by_side[Graph::Port::NORTH]
          distribute_ports_horizontally(
            node,
            ports_by_side[Graph::Port::NORTH],
            0,
          )
        end

        # SOUTH: bottom edge, distributed horizontally
        if ports_by_side[Graph::Port::SOUTH]
          distribute_ports_horizontally(
            node,
            ports_by_side[Graph::Port::SOUTH],
            node.height,
          )
        end

        # WEST: left edge, distributed vertically
        if ports_by_side[Graph::Port::WEST]
          distribute_ports_vertically(
            node,
            ports_by_side[Graph::Port::WEST],
            0,
          )
        end

        # EAST: right edge, distributed vertically
        if ports_by_side[Graph::Port::EAST]
          distribute_ports_vertically(
            node,
            ports_by_side[Graph::Port::EAST],
            node.width,
          )
        end
      end

      # Distribute ports horizontally along a horizontal edge
      #
      # @param node [Elkrb::Graph::Node] The node containing the ports
      # @param ports [Array<Elkrb::Graph::Port>] The ports to distribute
      # @param y_pos [Float] The y position of the edge
      def distribute_ports_horizontally(node, ports, y_pos)
        count = ports.length
        spacing = node.width / (count + 1).to_f

        ports.each_with_index do |port, idx|
          port.x = spacing * (idx + 1)
          port.y = y_pos
          port.offset = port.x
        end
      end

      # Distribute ports vertically along a vertical edge
      #
      # @param node [Elkrb::Graph::Node] The node containing the ports
      # @param ports [Array<Elkrb::Graph::Port>] The ports to distribute
      # @param x_pos [Float] The x position of the edge
      def distribute_ports_vertically(node, ports, x_pos)
        count = ports.length
        spacing = node.height / (count + 1).to_f

        ports.each_with_index do |port, idx|
          port.x = x_pos
          port.y = spacing * (idx + 1)
          port.offset = port.y
        end
      end
    end
  end
end
