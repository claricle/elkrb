# frozen_string_literal: true

require_relative "../geometry/point"
require_relative "../geometry/bezier"
require_relative "../geometry/rectangle"
require_relative "../graph/edge"
require_relative "node_index"

module Elkrb
  module Layout
    # Provides edge routing functionality for layout algorithms.
    #
    # The including class sets @resolver (an Options::Resolver), as
    # BaseAlgorithm does; every option read goes through it.
    module EdgeRouter
      # Route edges in a graph using specified routing style
      # @param graph [Graph::Graph] The graph to route edges for
      # @param node_map [NodeIndex] Resolves node/port ids to owning
      #   nodes for this level
      # @param routing_style [String] Routing style (ORTHOGONAL, POLYLINE,
      #   SPLINES)
      # A plain `{id => node}` Hash was the documented node_map before
      # NodeIndex existed, and both public entry points still take one.
      # Only #node is ever asked of a node_map, so that is all this wraps.
      class HashNodeMap
        def initialize(nodes)
          @nodes = nodes
        end

        # A caller-supplied Hash is keyed by node id, but an edge endpoint may
        # name a PORT. Fall back to the node owning that port, the way the
        # pre-NodeIndex router did — otherwise a ported edge silently ends up
        # with no sections at all.
        def node(id)
          @nodes[id] || owner_of_port(id)
        end

        private

        def owner_of_port(id)
          @nodes.each_value.find { |node| owns_port?(node, id) }
        end

        def owns_port?(node, id)
          return false unless node.respond_to?(:ports)

          node.ports&.any? { |port| port.id == id } || false
        end
      end
      private_constant :HashNodeMap

      def coerce_node_map(node_map)
        node_map.is_a?(::Hash) ? HashNodeMap.new(node_map) : node_map
      end

      def route_edges(graph, node_map = nil, routing_style = nil)
        node_map = coerce_node_map(node_map || NodeIndex.build(graph))
        graph.edges&.each do |edge|
          style = routing_style || get_edge_routing_style(graph, edge)
          if self_loop?(edge)
            route_self_loop(edge, node_map, graph, style)
          else
            route_edge_with_style(edge, node_map, graph, style)
          end
        end
      end

      # Route a single edge
      # @param edge [Graph::Edge] The edge to route
      # @param node_map [NodeIndex] Resolves node/port ids to owning
      #   nodes for this level
      # @param graph [Graph::Graph] The containing graph
      def route_edge(edge, node_map, graph, routing_style = nil)
        return unless edge.sources&.any? && edge.targets&.any?

        node_map = coerce_node_map(node_map)

        # Get source and target nodes
        source_id = edge.sources.first
        target_id = edge.targets.first

        source_node = node_map.node(source_id)
        target_node = node_map.node(target_id)

        return unless source_node && target_node

        section = reset_section(edge, graph)
        routing_style ||= get_edge_routing_style(graph, edge)

        # Calculate routing points based on port-awareness
        if edge_uses_ports?(edge, source_node, target_node)
          route_with_ports(section, edge, source_node, target_node,
                           routing_style)
        else
          route_node_to_node(section, source_node, target_node, routing_style)
        end
      end

      private

      # Check if edge should use port-based routing
      def edge_uses_ports?(edge, source_node, target_node)
        find_port_by_id(edge.sources.first, source_node) ||
          find_port_by_id(edge.targets.first, target_node)
      end

      # Route edge using port positions
      def route_with_ports(section, edge, source_node, target_node,
                           routing_style)
        start_point, end_point = endpoint_points(edge, source_node, target_node)

        section.start_point = start_point
        section.end_point = end_point
        section.bend_points = []

        if routing_style == "ORTHOGONAL"
          add_orthogonal_bend_points(section, start_point, end_point)
        end
      end

      # Route edge from source border to target border
      def route_node_to_node(section, source_node, target_node, routing_style)
        source_rect = node_rectangle(source_node)
        target_rect = node_rectangle(target_node)
        source_center = source_rect.center
        target_center = target_rect.center
        start_point = clip_to_border(source_rect, source_center, target_center)
        end_point = clip_to_border(target_rect, target_center, source_center)

        section.start_point = start_point
        section.end_point = end_point
        section.bend_points = []

        if routing_style == "ORTHOGONAL"
          add_orthogonal_bend_points(section, start_point, end_point)
        end
      end

      def node_rectangle(node)
        Geometry::Rectangle.new(
          node.x || 0.0,
          node.y || 0.0,
          node.width || 0.0,
          node.height || 0.0,
        )
      end

      # Intersect the ray from a rectangle's centre towards another point
      # with the rectangle border.
      def clip_to_border(rect, from, to)
        dx = to.x - from.x
        dy = to.y - from.y
        return Geometry::Point.new(x: from.x, y: from.y) if dx.zero? && dy.zero?

        scales = []
        scales << ((rect.width / 2.0) / dx.abs) unless dx.zero?
        scales << ((rect.height / 2.0) / dy.abs) unless dy.zero?
        scale = scales.min

        Geometry::Point.new(
          x: from.x + (dx * scale),
          y: from.y + (dy * scale),
        )
      end

      def reset_section(edge, graph)
        section = Graph::EdgeSection.new(
          id: "#{edge.id}_s0",
          incoming_shape: edge.sources.first,
          outgoing_shape: edge.targets.first,
        )
        edge.sections = [section]
        edge.container ||= graph.id
        section
      end

      # Find port by ID
      def find_port_by_id(port_id, node)
        node.ports&.find { |p| p.id == port_id }
      end

      # Get position of a port or node center
      def get_port_position(port_id, node, _direction)
        # Try to find port
        port = find_port_by_id(port_id, node)

        if port
          # Port position is relative to node position
          Geometry::Point.new(
            x: (node.x || 0.0) + (port.x || 0.0),
            y: (node.y || 0.0) + (port.y || 0.0),
          )
        else
          # Fallback to node center
          get_node_center(node)
        end
      end

      # Get center point of a node
      def get_node_center(node)
        x = (node.x || 0.0) + ((node.width || 0.0) / 2.0)
        y = (node.y || 0.0) + ((node.height || 0.0) / 2.0)
        Geometry::Point.new(x: x, y: y)
      end

      def endpoint_points(edge, source_node, target_node)
        source_id = edge.sources.first
        target_id = edge.targets.first
        source_port = find_port_by_id(source_id, source_node)
        target_port = find_port_by_id(target_id, target_node)
        source_anchor = get_port_position(source_id, source_node, :outgoing)
        target_anchor = get_port_position(target_id, target_node, :incoming)

        start_point = if source_port
                        source_anchor
                      else
                        clip_to_border(node_rectangle(source_node),
                                       source_anchor, target_anchor)
                      end
        end_point = if target_port
                      target_anchor
                    else
                      clip_to_border(node_rectangle(target_node),
                                     target_anchor, source_anchor)
                    end
        [start_point, end_point]
      end

      # Add horizontal bend points (for horizontal connections)
      def add_horizontal_bend_points(section, start_point, end_point)
        mid_x = (start_point.x + end_point.x) / 2.0
        section.add_bend_point(mid_x, start_point.y)
        section.add_bend_point(mid_x, end_point.y)
      end

      # Add vertical bend points (for vertical connections)
      def add_vertical_bend_points(section, start_point, end_point)
        mid_y = (start_point.y + end_point.y) / 2.0
        section.add_bend_point(start_point.x, mid_y)
        section.add_bend_point(end_point.x, mid_y)
      end

      # Add orthogonal (right-angle) bend points
      def add_orthogonal_bend_points(section, start_point, end_point)
        return if start_point.x == end_point.x || start_point.y == end_point.y

        dx = (end_point.x - start_point.x).abs
        dy = (end_point.y - start_point.y).abs
        if dx >= dy
          add_horizontal_bend_points(section, start_point, end_point)
        else
          add_vertical_bend_points(section, start_point, end_point)
        end
      end

      # Get edge routing style from graph options
      #
      # @param graph [Elkrb::Graph::Graph] The graph
      # @return [String] Routing style (ORTHOGONAL, POLYLINE, SPLINES)
      def get_edge_routing_style(graph, edge = nil)
        elements = edge ? [edge, graph] : [graph]
        style = @resolver.get("elk.edgeRouting", *elements)

        style = style.to_s.upcase
        style == "UNDEFINED" ? "ORTHOGONAL" : style
      end

      # Route edge with specified routing style
      def route_edge_with_style(edge, node_map, graph, routing_style)
        case routing_style
        when "SPLINES"
          route_spline_edge(edge, node_map, graph)
        when "POLYLINE"
          route_polyline_edge(edge, node_map, graph)
        else
          route_edge(edge, node_map, graph, "ORTHOGONAL")
        end
      end

      # Route edge with polyline (straight segments) style
      def route_polyline_edge(edge, node_map, graph)
        route_edge(edge, node_map, graph, "POLYLINE")
      end

      # Route edge with spline (curved) style
      def route_spline_edge(edge, node_map, graph)
        return unless edge.sources&.any? && edge.targets&.any?

        source_id = edge.sources.first
        target_id = edge.targets.first

        source_node = node_map.node(source_id)
        target_node = node_map.node(target_id)

        return unless source_node && target_node

        section = reset_section(edge, graph)

        # Calculate spline routing
        if edge_uses_ports?(edge, source_node, target_node)
          route_spline_with_ports(section, edge, source_node, target_node)
        else
          route_spline_node_to_node(section, edge, source_node, target_node)
        end
      end

      # Route spline edge using port positions
      def route_spline_with_ports(section, edge, source_node, target_node)
        start_point, end_point = endpoint_points(edge, source_node, target_node)

        section.start_point = start_point
        section.end_point = end_point

        # Calculate control points for spline
        add_spline_control_points(section, start_point, end_point, edge)
      end

      # Route spline edge from node center to node center
      def route_spline_node_to_node(section, edge, source_node, target_node)
        source_rect = node_rectangle(source_node)
        target_rect = node_rectangle(target_node)
        source_center = source_rect.center
        target_center = target_rect.center
        start_point = clip_to_border(source_rect, source_center, target_center)
        end_point = clip_to_border(target_rect, target_center, source_center)

        section.start_point = start_point
        section.end_point = end_point

        # Calculate control points for spline
        add_spline_control_points(section, start_point, end_point, edge)
      end

      # Add Bezier control points to create smooth spline
      def add_spline_control_points(section, start_point, end_point, edge)
        # Get curvature setting
        curvature = get_spline_curvature(edge)

        # Calculate control points
        control_points = calculate_spline_controls(
          start_point,
          end_point,
          curvature,
          edge,
        )

        # Store control points as bend points
        section.bend_points ||= []
        section.bend_points = control_points
      end

      # Get spline curvature from options
      def get_spline_curvature(edge)
        @resolver.get("elk.spline.curvature", edge)
      end

      # Calculate Bezier control points for smooth curves
      def calculate_spline_controls(start_point, end_point, curvature, edge)
        # Determine routing direction from the edge's options
        direction = get_routing_direction(edge)

        case direction
        when "HORIZONTAL", "RIGHT", "LEFT"
          Geometry::Bezier.horizontal_control_points(
            start_point,
            end_point,
            curvature,
          )
        when "VERTICAL", "DOWN", "UP"
          Geometry::Bezier.vertical_control_points(
            start_point,
            end_point,
            curvature,
          )
        else
          # Default: perpendicular control points
          Geometry::Bezier.calculate_control_points(
            start_point,
            end_point,
            curvature,
          )
        end
      end

      # Get routing direction from edge options
      def get_routing_direction(edge)
        @resolver.get("elk.direction", edge, default: nil)
      end

      # Check if edge is a self-loop (source == target)
      def self_loop?(edge)
        sources = edge.sources || []
        targets = edge.targets || []

        return false if sources.empty? || targets.empty?

        sources.first == targets.first
      end

      # Route a self-loop edge
      def route_self_loop(edge, node_map, graph, routing_style)
        node_id = edge.sources.first
        node = node_map.node(node_id)

        return unless node

        # Get self-loop index for multiple loops on same node
        loop_index = get_self_loop_index(edge, node, graph)

        # Create edge section if not exists
        edge.sections ||= []
        if edge.sections.empty?
          edge.sections << Graph::EdgeSection.new(
            id: "#{edge.id}_section_0",
          )
        end

        section = edge.sections.first

        # Check if edge uses ports
        if edge_uses_ports_for_self_loop?(edge, node)
          route_self_loop_with_ports(section, edge, node, loop_index,
                                     routing_style)
        else
          # Route based on style
          case routing_style
          when "SPLINES"
            route_spline_self_loop(section, edge, node, loop_index)
          when "POLYLINE"
            route_polyline_self_loop(section, edge, node, loop_index)
          else
            route_orthogonal_self_loop(section, edge, node, loop_index)
          end
        end
      end

      # Get self-loop index for multiple loops on same node
      def get_self_loop_index(edge, node, graph)
        return 0 unless graph.edges

        # Find all self-loops on this node
        self_loops = graph.edges.select do |e|
          self_loop?(e) && e.sources&.first == node.id
        end

        # Return index of current edge
        self_loops.index(edge) || 0
      end

      # Route orthogonal self-loop (rectangular path)
      def route_orthogonal_self_loop(section, edge, node, loop_index)
        # Calculate offset based on loop index
        offset = calculate_loop_offset(loop_index)

        # Get self-loop side
        side = get_self_loop_side(edge, node)

        # Calculate dimensions
        width = ((node.width || 50.0) * 0.4) + offset
        height = ((node.height || 50.0) * 0.4) + offset

        # Calculate start/end points based on side
        case side
        when "EAST"
          route_east_self_loop(section, node, width, height)
        when "WEST"
          route_west_self_loop(section, node, width, height)
        when "NORTH"
          route_north_self_loop(section, node, width, height)
        when "SOUTH"
          route_south_self_loop(section, node, width, height)
        else
          # Default: EAST
          route_east_self_loop(section, node, width, height)
        end
      end

      # Route self-loop on EAST side
      def route_east_self_loop(section, node, width, height)
        node_x = node.x || 0.0
        node_y = node.y || 0.0
        node_width = node.width || 50.0
        node_height = node.height || 50.0

        # Start point (right middle of node)
        start_x = node_x + node_width
        start_y = node_y + (node_height / 2.0)

        # End point (slightly below start)
        end_x = start_x
        end_y = start_y + 10.0

        section.start_point = Geometry::Point.new(x: start_x, y: start_y)
        section.end_point = Geometry::Point.new(x: end_x, y: end_y)

        # Bend points forming rectangular loop
        section.bend_points = [
          Geometry::Point.new(x: start_x + width, y: start_y),
          Geometry::Point.new(x: start_x + width, y: start_y - height),
          Geometry::Point.new(x: start_x + width, y: start_y + height),
          Geometry::Point.new(x: end_x, y: end_y - 5.0),
        ]
      end

      # Route self-loop on WEST side
      def route_west_self_loop(section, node, width, height)
        node_x = node.x || 0.0
        node_y = node.y || 0.0
        node_height = node.height || 50.0

        # Start point (left middle of node)
        start_x = node_x
        start_y = node_y + (node_height / 2.0)

        # End point (slightly below start)
        end_x = start_x
        end_y = start_y + 10.0

        section.start_point = Geometry::Point.new(x: start_x, y: start_y)
        section.end_point = Geometry::Point.new(x: end_x, y: end_y)

        # Bend points forming rectangular loop
        section.bend_points = [
          Geometry::Point.new(x: start_x - width, y: start_y),
          Geometry::Point.new(x: start_x - width, y: start_y - height),
          Geometry::Point.new(x: start_x - width, y: start_y + height),
          Geometry::Point.new(x: end_x, y: end_y - 5.0),
        ]
      end

      # Route self-loop on NORTH side
      def route_north_self_loop(section, node, width, height)
        node_x = node.x || 0.0
        node_y = node.y || 0.0
        node_width = node.width || 50.0

        # Start point (top middle of node)
        start_x = node_x + (node_width / 2.0)
        start_y = node_y

        # End point (slightly to the right of start)
        end_x = start_x + 10.0
        end_y = start_y

        section.start_point = Geometry::Point.new(x: start_x, y: start_y)
        section.end_point = Geometry::Point.new(x: end_x, y: end_y)

        # Bend points forming rectangular loop
        section.bend_points = [
          Geometry::Point.new(x: start_x, y: start_y - height),
          Geometry::Point.new(x: start_x - width, y: start_y - height),
          Geometry::Point.new(x: start_x + width, y: start_y - height),
          Geometry::Point.new(x: end_x - 5.0, y: end_y),
        ]
      end

      # Route self-loop on SOUTH side
      def route_south_self_loop(section, node, width, height)
        node_x = node.x || 0.0
        node_y = node.y || 0.0
        node_width = node.width || 50.0
        node_height = node.height || 50.0

        # Start point (bottom middle of node)
        start_x = node_x + (node_width / 2.0)
        start_y = node_y + node_height

        # End point (slightly to the right of start)
        end_x = start_x + 10.0
        end_y = start_y

        section.start_point = Geometry::Point.new(x: start_x, y: start_y)
        section.end_point = Geometry::Point.new(x: end_x, y: end_y)

        # Bend points forming rectangular loop
        section.bend_points = [
          Geometry::Point.new(x: start_x, y: start_y + height),
          Geometry::Point.new(x: start_x - width, y: start_y + height),
          Geometry::Point.new(x: start_x + width, y: start_y + height),
          Geometry::Point.new(x: end_x - 5.0, y: end_y),
        ]
      end

      # Route spline self-loop (curved path)
      def route_spline_self_loop(section, edge, node, loop_index)
        # Calculate offset based on loop index
        offset = calculate_loop_offset(loop_index)

        # Get self-loop side
        side = get_self_loop_side(edge, node)

        node_x = node.x || 0.0
        node_y = node.y || 0.0
        node_width = node.width || 50.0
        node_height = node.height || 50.0

        # Calculate radius based on offset
        radius = ((node_width + node_height) / 4.0) + offset

        case side
        when "EAST"
          start_x = node_x + node_width
          start_y = node_y + (node_height / 2.0)
          end_x = start_x
          end_y = start_y + 10.0

          # Control points for circular arc on right side
          control1 = Geometry::Point.new(
            x: start_x + radius,
            y: start_y - radius,
          )
          control2 = Geometry::Point.new(
            x: start_x + radius,
            y: start_y + radius,
          )
        when "WEST"
          start_x = node_x
          start_y = node_y + (node_height / 2.0)
          end_x = start_x
          end_y = start_y + 10.0

          # Control points for circular arc on left side
          control1 = Geometry::Point.new(
            x: start_x - radius,
            y: start_y - radius,
          )
          control2 = Geometry::Point.new(
            x: start_x - radius,
            y: start_y + radius,
          )
        when "NORTH"
          start_x = node_x + (node_width / 2.0)
          start_y = node_y
          end_x = start_x + 10.0
          end_y = start_y

          # Control points for circular arc on top
          control1 = Geometry::Point.new(
            x: start_x - radius,
            y: start_y - radius,
          )
          control2 = Geometry::Point.new(
            x: start_x + radius,
            y: start_y - radius,
          )
        when "SOUTH"
          start_x = node_x + (node_width / 2.0)
          start_y = node_y + node_height
          end_x = start_x + 10.0
          end_y = start_y

          # Control points for circular arc on bottom
          control1 = Geometry::Point.new(
            x: start_x - radius,
            y: start_y + radius,
          )
          control2 = Geometry::Point.new(
            x: start_x + radius,
            y: start_y + radius,
          )
        else
          # Default: EAST
          start_x = node_x + node_width
          start_y = node_y + (node_height / 2.0)
          end_x = start_x
          end_y = start_y + 10.0

          control1 = Geometry::Point.new(
            x: start_x + radius,
            y: start_y - radius,
          )
          control2 = Geometry::Point.new(
            x: start_x + radius,
            y: start_y + radius,
          )
        end

        section.start_point = Geometry::Point.new(x: start_x, y: start_y)
        section.end_point = Geometry::Point.new(x: end_x, y: end_y)
        section.bend_points = [control1, control2]
      end

      # Route polyline self-loop (simple path)
      def route_polyline_self_loop(section, edge, node, loop_index)
        # For polyline, use orthogonal routing
        route_orthogonal_self_loop(section, edge, node, loop_index)
      end

      # Calculate offset for multiple self-loops on same node
      def calculate_loop_offset(loop_index)
        base_offset = 20.0
        base_offset * (loop_index + 1)
      end

      # Get self-loop side from options or default
      def get_self_loop_side(edge, node)
        @resolver.get("elk.selfLoopSide", edge, node)
      end

      # Check if self-loop edge uses ports
      def edge_uses_ports_for_self_loop?(edge, node)
        return false unless node.ports&.any?

        source_id = edge.sources&.first
        target_id = edge.targets&.first

        return false unless source_id && target_id

        # Check if source or target is a port ID
        source_port = find_port_by_id(source_id, node)
        target_port = find_port_by_id(target_id, node)

        !!(source_port || target_port)
      end

      # Route self-loop with ports
      def route_self_loop_with_ports(section, edge, node, loop_index,
                                      routing_style)
        source_id = edge.sources.first
        target_id = edge.targets.first

        source_port = find_port_by_id(source_id, node)
        target_port = find_port_by_id(target_id, node)

        # Get port positions
        start_point = if source_port
                        get_port_absolute_position(source_port, node)
                      else
                        get_node_center(node)
                      end

        end_point = if target_port
                      get_port_absolute_position(target_port, node)
                    else
                      get_node_center(node)
                    end

        section.start_point = start_point
        section.end_point = end_point

        # Calculate offset
        offset = calculate_loop_offset(loop_index)

        # Route between ports with appropriate style
        if source_port && target_port
          route_port_to_port_self_loop(
            section,
            start_point,
            end_point,
            source_port,
            target_port,
            offset,
            routing_style,
          )
        else
          # Fallback to regular self-loop routing
          case routing_style
          when "SPLINES"
            route_spline_self_loop(section, edge, node, loop_index)
          else
            route_orthogonal_self_loop(section, edge, node, loop_index)
          end
        end
      end

      # Get absolute position of a port
      def get_port_absolute_position(port, node)
        Geometry::Point.new(
          x: (node.x || 0.0) + (port.x || 0.0),
          y: (node.y || 0.0) + (port.y || 0.0),
        )
      end

      # Route self-loop from port to port
      def route_port_to_port_self_loop(section, start_point, end_point,
                                         source_port, target_port, offset,
                                         routing_style)
        # Calculate midpoint for loop
        (start_point.x + end_point.x) / 2.0
        (start_point.y + end_point.y) / 2.0

        # Determine loop direction based on port sides
        source_side = source_port.side || "EAST"
        target_side = target_port.side || "EAST"

        if routing_style == "SPLINES"
          # Create smooth curve between ports
          route_spline_port_self_loop(
            section,
            start_point,
            end_point,
            source_side,
            target_side,
            offset,
          )
        else
          # Create orthogonal path between ports
          route_orthogonal_port_self_loop(
            section,
            start_point,
            end_point,
            source_side,
            target_side,
            offset,
          )
        end
      end

      # Route orthogonal self-loop between ports
      def route_orthogonal_port_self_loop(section, start_point, end_point,
                                            source_side, target_side, offset)
        section.bend_points = []

        # Create bend points based on port sides
        case [source_side, target_side]
        when ["EAST", "EAST"], ["WEST", "WEST"]
          # Both on same vertical side - create horizontal loop
          extension = offset + 30.0
          mid_y = (start_point.y + end_point.y) / 2.0

          if source_side == "EAST"
            section.add_bend_point(start_point.x + extension, start_point.y)
            section.add_bend_point(start_point.x + extension, mid_y)
            section.add_bend_point(end_point.x + extension, end_point.y)
          else
            section.add_bend_point(start_point.x - extension, start_point.y)
            section.add_bend_point(start_point.x - extension, mid_y)
            section.add_bend_point(end_point.x - extension, end_point.y)
          end
        when ["NORTH", "NORTH"], ["SOUTH", "SOUTH"]
          # Both on same horizontal side - create vertical loop
          extension = offset + 30.0
          mid_x = (start_point.x + end_point.x) / 2.0

          if source_side == "NORTH"
            section.add_bend_point(start_point.x, start_point.y - extension)
            section.add_bend_point(mid_x, start_point.y - extension)
            section.add_bend_point(end_point.x, end_point.y - extension)
          else
            section.add_bend_point(start_point.x, start_point.y + extension)
            section.add_bend_point(mid_x, start_point.y + extension)
            section.add_bend_point(end_point.x, end_point.y + extension)
          end
        else
          # Different sides - create L-shaped path
          mid_x = (start_point.x + end_point.x) / 2.0
          section.add_bend_point(mid_x, start_point.y)
          section.add_bend_point(mid_x, end_point.y)
        end
      end

      # Route spline self-loop between ports
      def route_spline_port_self_loop(section, start_point, end_point,
                                        source_side, target_side, offset)
        # Create Bezier curve control points
        extension = offset + 30.0

        case [source_side, target_side]
        when ["EAST", "EAST"]
          control1 = Geometry::Point.new(
            x: start_point.x + extension,
            y: start_point.y,
          )
          control2 = Geometry::Point.new(
            x: end_point.x + extension,
            y: end_point.y,
          )
        when ["WEST", "WEST"]
          control1 = Geometry::Point.new(
            x: start_point.x - extension,
            y: start_point.y,
          )
          control2 = Geometry::Point.new(
            x: end_point.x - extension,
            y: end_point.y,
          )
        when ["NORTH", "NORTH"]
          control1 = Geometry::Point.new(
            x: start_point.x,
            y: start_point.y - extension,
          )
          control2 = Geometry::Point.new(
            x: end_point.x,
            y: end_point.y - extension,
          )
        when ["SOUTH", "SOUTH"]
          control1 = Geometry::Point.new(
            x: start_point.x,
            y: start_point.y + extension,
          )
          control2 = Geometry::Point.new(
            x: end_point.x,
            y: end_point.y + extension,
          )
        else
          # Default perpendicular control points
          mid_x = (start_point.x + end_point.x) / 2.0
          (start_point.y + end_point.y) / 2.0
          control1 = Geometry::Point.new(x: mid_x, y: start_point.y)
          control2 = Geometry::Point.new(x: mid_x, y: end_point.y)
        end

        section.bend_points = [control1, control2]
      end
    end
  end
end
