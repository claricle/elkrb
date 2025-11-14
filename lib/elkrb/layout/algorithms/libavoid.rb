# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../../geometry/point"
require_relative "../../geometry/rectangle"

module Elkrb
  module Layout
    module Algorithms
      # Libavoid connector routing algorithm
      #
      # Routes orthogonal connectors around obstacles (nodes) using A* pathfinding.
      # Minimizes connector length and bends while avoiding overlaps with nodes.
      # Based on the concepts from the libavoid C++ library.
      #
      # Features:
      # - Orthogonal (90-degree) routing
      # - Obstacle avoidance
      # - Bend minimization
      # - Configurable routing padding
      #
      # Options:
      # - libavoid.routingPadding: Padding around obstacles (default: 10)
      # - libavoid.segmentPenalty: Penalty for additional segments (default: 1.0)
      # - libavoid.bendPenalty: Penalty for bends (default: 2.0)
      class Libavoid < BaseAlgorithm
        # Priority queue node for A* algorithm
        class PathNode
          attr_accessor :point, :parent, :g_score, :f_score, :direction

          def initialize(point, parent = nil, g_score = Float::INFINITY,
f_score = Float::INFINITY, direction = nil)
            @point = point
            @parent = parent
            @g_score = g_score
            @f_score = f_score
            @direction = direction # :horizontal or :vertical
          end

          def ==(other)
            other.is_a?(PathNode) && point.x == other.point.x && point.y == other.point.y
          end

          def hash
            [point.x, point.y].hash
          end

          def eql?(other)
            self == other
          end
        end

        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          # Position nodes if not already positioned
          position_nodes_if_needed(graph)

          # Build obstacle map from nodes
          obstacles = build_obstacle_map(graph.children)

          # Route each edge
          route_edges_with_obstacles(graph, obstacles)

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end

        private

        # Position nodes if they don't have positions
        def position_nodes_if_needed(graph)
          return if graph.children.all? { |n| n.x && n.y }

          # Use simple box layout for positioning
          spacing = node_spacing
          max_width = graph.children.map(&:width).max
          max_height = graph.children.map(&:height).max

          cols = Math.sqrt(graph.children.length * 1.6).ceil
          cols = [cols, 1].max

          graph.children.each_with_index do |node, i|
            row = i / cols
            col = i % cols
            node.x = col * (max_width + spacing)
            node.y = row * (max_height + spacing)
          end
        end

        # Build obstacle map from nodes
        def build_obstacle_map(nodes)
          padding = option("libavoid.routingPadding", 10).to_f

          nodes.map do |node|
            Geometry::Rectangle.new(
              (node.x || 0) - padding,
              (node.y || 0) - padding,
              (node.width || 0) + (2 * padding),
              (node.height || 0) + (2 * padding),
            )
          end
        end

        # Route all edges with obstacle avoidance
        def route_edges_with_obstacles(graph, obstacles)
          return unless graph.edges&.any?

          node_map = build_node_map(graph)

          graph.edges.each do |edge|
            route_single_edge(edge, node_map, obstacles)
          end
        end

        # Route a single edge around obstacles
        def route_single_edge(edge, node_map, obstacles)
          return unless edge.sources&.any? && edge.targets&.any?

          source_id = edge.sources.first
          target_id = edge.targets.first

          source_node = node_map[source_id]
          target_node = node_map[target_id]

          return unless source_node && target_node

          # Get start and end points (node centers)
          start_point = get_node_center(source_node)
          end_point = get_node_center(target_node)

          # Find path using A* algorithm
          path = find_path(start_point, end_point, obstacles)

          # Create orthogonal segments from path
          bend_points = create_orthogonal_segments(path)

          # Minimize bends
          bend_points = minimize_bends(bend_points, start_point, end_point,
                                       obstacles)

          # Apply to edge section
          edge.sections ||= []
          if edge.sections.empty?
            edge.sections << Graph::EdgeSection.new(id: "#{edge.id}_section_0")
          end

          section = edge.sections.first
          section.start_point = start_point
          section.end_point = end_point
          section.bend_points = bend_points
        end

        # A* pathfinding algorithm
        def find_path(start, goal, obstacles)
          segment_penalty = option("libavoid.segmentPenalty", 1.0).to_f
          bend_penalty = option("libavoid.bendPenalty", 2.0).to_f

          start_node = PathNode.new(start, nil, 0, heuristic(start, goal))
          open_set = [start_node]
          closed_set = {}
          g_scores = { point_key(start) => 0 }

          while open_set.any?
            # Get node with lowest f_score
            current = open_set.min_by(&:f_score)

            # Goal reached
            if points_equal?(current.point, goal)
              return reconstruct_path(current)
            end

            open_set.delete(current)
            closed_set[point_key(current.point)] = true

            # Explore neighbors (orthogonal directions)
            neighbors = get_orthogonal_neighbors(current.point, goal, obstacles)

            neighbors.each do |neighbor_point, direction|
              key = point_key(neighbor_point)
              next if closed_set[key]

              # Calculate cost with penalties for segments and direction changes
              distance = euclidean_distance(current.point, neighbor_point)
              direction_change_penalty = current.direction && current.direction != direction ? bend_penalty : 0
              tentative_g = current.g_score + distance + segment_penalty + direction_change_penalty

              if !g_scores[key] || tentative_g < g_scores[key]
                g_scores[key] = tentative_g
                f_score = tentative_g + heuristic(neighbor_point, goal)

                neighbor_node = PathNode.new(neighbor_point, current,
                                             tentative_g, f_score, direction)

                # Add or update in open set
                existing = open_set.find do |n|
                  points_equal?(n.point, neighbor_point)
                end
                if existing
                  open_set.delete(existing)
                end
                open_set << neighbor_node
              end
            end
          end

          # No path found, return direct path
          [start, goal]
        end

        # Get orthogonal neighbors (4-directional)
        def get_orthogonal_neighbors(point, _goal, obstacles)
          step_size = option("libavoid.routingPadding", 10).to_f
          neighbors = []

          # Four orthogonal directions
          [
            [step_size, 0, :horizontal],    # right
            [-step_size, 0, :horizontal],   # left
            [0, step_size, :vertical],      # down
            [0, -step_size, :vertical], # up
          ].each do |dx, dy, direction|
            neighbor = Geometry::Point.new(x: point.x + dx, y: point.y + dy)

            # Skip if it collides with obstacles
            unless collides_with_obstacles?(point, neighbor, obstacles)
              neighbors << [neighbor, direction]
            end
          end

          neighbors
        end

        # Check if line segment collides with obstacles
        def collides_with_obstacles?(p1, p2, obstacles)
          obstacles.any? do |obstacle|
            line_intersects_rectangle?(p1, p2, obstacle)
          end
        end

        # Check if line segment intersects rectangle
        def line_intersects_rectangle?(p1, p2, rect)
          # Check if either endpoint is inside rectangle
          return true if point_in_rectangle?(p1,
                                             rect) || point_in_rectangle?(p2,
                                                                          rect)

          # Check if line intersects any edge of rectangle
          rect_edges = [
            [Geometry::Point.new(x: rect.x, y: rect.y),
             Geometry::Point.new(x: rect.x + rect.width, y: rect.y)],
            [Geometry::Point.new(x: rect.x + rect.width, y: rect.y),
             Geometry::Point.new(x: rect.x + rect.width,
                                 y: rect.y + rect.height)],
            [Geometry::Point.new(x: rect.x + rect.width, y: rect.y + rect.height),
             Geometry::Point.new(x: rect.x, y: rect.y + rect.height)],
            [Geometry::Point.new(x: rect.x, y: rect.y + rect.height),
             Geometry::Point.new(x: rect.x, y: rect.y)],
          ]

          rect_edges.any? do |edge_p1, edge_p2|
            segments_intersect?(p1, p2, edge_p1, edge_p2)
          end
        end

        # Check if point is inside rectangle
        def point_in_rectangle?(point, rect)
          point.x.between?(rect.x, rect.x + rect.width) &&
            point.y >= rect.y &&
            point.y <= rect.y + rect.height
        end

        # Check if two line segments intersect
        def segments_intersect?(p1, p2, p3, p4)
          d1 = direction(p3, p4, p1)
          d2 = direction(p3, p4, p2)
          d3 = direction(p1, p2, p3)
          d4 = direction(p1, p2, p4)

          ((d1.positive? && d2.negative?) || (d1.negative? && d2.positive?)) &&
            ((d3.positive? && d4.negative?) || (d3.negative? && d4.positive?))
        end

        # Calculate direction for line segment intersection
        def direction(p1, p2, p3)
          ((p3.x - p1.x) * (p2.y - p1.y)) - ((p2.x - p1.x) * (p3.y - p1.y))
        end

        # Reconstruct path from A* result
        def reconstruct_path(node)
          path = []
          current = node

          while current
            path.unshift(current.point)
            current = current.parent
          end

          path
        end

        # Manhattan distance heuristic for A*
        def heuristic(point, goal)
          (point.x - goal.x).abs + (point.y - goal.y).abs
        end

        # Euclidean distance
        def euclidean_distance(p1, p2)
          dx = p2.x - p1.x
          dy = p2.y - p1.y
          Math.sqrt((dx * dx) + (dy * dy))
        end

        # Create orthogonal segments from path
        def create_orthogonal_segments(path)
          return [] if path.length < 3

          # Path already contains waypoints from A*, convert to bend points
          # (excluding start and end points)
          path[1..-2].map do |point|
            Geometry::Point.new(x: point.x, y: point.y)
          end
        end

        # Minimize bends in path
        def minimize_bends(bend_points, start_point, end_point, obstacles)
          return bend_points if bend_points.empty?

          # Try to remove unnecessary bend points
          all_points = [start_point] + bend_points + [end_point]
          simplified = [all_points.first]

          i = 0
          while i < all_points.length - 1
            j = all_points.length - 1

            # Try to connect point i to furthest visible point
            while j > i + 1
              unless collides_with_obstacles?(all_points[i], all_points[j],
                                              obstacles)
                simplified << all_points[j]
                i = j
                break
              end
              j -= 1
            end

            # If no direct path found, use next point
            if j == i + 1
              simplified << all_points[i + 1]
              i += 1
            end
          end

          # Remove start and end points from result
          simplified[1..-2] || []
        end

        # Helper: create unique key for point
        def point_key(point)
          "#{point.x.round(2)},#{point.y.round(2)}"
        end

        # Helper: check if two points are equal (within tolerance)
        def points_equal?(p1, p2, tolerance = 0.1)
          (p1.x - p2.x).abs < tolerance && (p1.y - p2.y).abs < tolerance
        end

        # Build node map from graph
        def build_node_map(graph)
          map = {}
          graph.children&.each do |node|
            map[node.id] = node
          end
          map
        end

        # Get center point of a node
        def get_node_center(node)
          x = (node.x || 0.0) + ((node.width || 0.0) / 2.0)
          y = (node.y || 0.0) + ((node.height || 0.0) / 2.0)
          Geometry::Point.new(x: x, y: y)
        end
      end
    end
  end
end
