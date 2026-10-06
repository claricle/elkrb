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

        placed_port_order.clear
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
        # Skip zero and non-finite dimensions: a zero axis has nothing to
        # distribute along, and `[0, NaN].min` raises. Negative is fine.
        return unless [node.width, node.height].all? { |dim| dim&.finite? && !dim.zero? }

        # Detect sides if not specified
        detect_port_sides(node)

        # Group ports by side
        ports_by_side = group_ports_by_side(node.ports)

        # Apply ordering within each side
        ports_by_side.each do |side, ports|
          order_ports_on_side(node, side, ports)
        end

        placed_port_order[node] = ports_by_side

        # Position ports on node boundaries
        position_ports_on_boundaries(node, ports_by_side)
      end

      # Place a node's ports again after its size changed. A node that
      # #process_node_ports already ordered keeps that order: indices cannot
      # be sorted a second time (an explicit and an assigned one collide)
      # and positions cannot be read back (they tie when the size is
      # subnormal). A node it skipped gets the one full pass instead.
      #
      # @param node [Elkrb::Graph::Node] The node whose ports to place again
      def replace_node_ports(node)
        ports_by_side = placed_port_order[node]
        return process_node_ports(node) unless ports_by_side
        return unless [node.width, node.height].all? { |dim| dim&.finite? && !dim.zero? }

        position_ports_on_boundaries(node, ports_by_side)
      end

      # Each node's ports per side, in the order #process_node_ports gave
      # them. Keyed by identity: equal nodes would share one entry by value.
      #
      # @return [Hash{Elkrb::Graph::Node => Hash}]
      def placed_port_order
        @placed_port_order ||= {}.compare_by_identity
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
        # The real top/bottom and left/right local offsets -- for a negative
        # height/width, local 0 is the real BOTTOM/RIGHT edge, so NORTH and
        # SOUTH (and WEST/EAST) must pick whichever of 0/height (0/width) is
        # actually the min/max, not always 0 for the "near" side.
        top, bottom, left, right = [0, node.height].minmax + [0, node.width].minmax

        # NORTH: top edge, distributed horizontally
        if ports_by_side[Graph::Port::NORTH]
          distribute_ports_horizontally(node, ports_by_side[Graph::Port::NORTH], top)
        end

        # SOUTH: bottom edge, distributed horizontally
        if ports_by_side[Graph::Port::SOUTH]
          distribute_ports_horizontally(node, ports_by_side[Graph::Port::SOUTH], bottom)
        end

        # WEST: left edge, distributed vertically
        if ports_by_side[Graph::Port::WEST]
          distribute_ports_vertically(node, ports_by_side[Graph::Port::WEST], left)
        end

        # EAST: right edge, distributed vertically
        if ports_by_side[Graph::Port::EAST]
          distribute_ports_vertically(node, ports_by_side[Graph::Port::EAST], right)
        end
      end

      # Distribute ports horizontally along a horizontal edge
      #
      # @param node [Elkrb::Graph::Node] The node containing the ports
      # @param ports [Array<Elkrb::Graph::Port>] The ports to distribute
      # @param y_pos [Float] The y position of the edge
      def distribute_ports_horizontally(node, ports, y_pos)
        count = ports.length
        # Walk from the real left edge rightwards, so the ascending order
        # #order_ports_on_side just sorted into is the order they land in --
        # starting at local 0 reverses it when node.width is negative.
        width = node.width
        left = [0, width].min
        spacing = (width.abs / (count + 1).to_f)

        ports.each_with_index do |port, idx|
          port.x = left + (spacing * (idx + 1))
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
        # Same reason as #distribute_ports_horizontally: start at the real
        # top edge so a negative node.height does not reverse the order.
        height = node.height
        top = [0, height].min
        spacing = (height.abs / (count + 1).to_f)

        ports.each_with_index do |port, idx|
          port.x = x_pos
          port.y = top + (spacing * (idx + 1))
          port.offset = port.y
        end
      end
    end
  end
end
