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
      # - Bounded A* obstacle avoidance, scoped per edge, with an observable
      #   fallback when no path is found within the search limit
      # - Bend minimization
      # - Configurable routing padding, grid step, and search limit
      #
      # Options:
      # - libavoid.routingPadding: Padding around obstacles (default: 10)
      # - libavoid.stepSize: Grid step for the A* search (default: 10,
      #   independent of routingPadding so a padding of 0 cannot collapse it)
      # - libavoid.maxExpansions: Search cap before falling back (default: 2000)
      # - libavoid.segmentPenalty: Penalty for additional segments (default: 1.0)
      # - libavoid.bendPenalty: Penalty for bends (default: 2.0)
      class Libavoid < BaseAlgorithm
        # An immutable A* search record: the point, its parent (for path
        # reconstruction), the cost so far, the estimated total cost, and the
        # direction of travel used to reach it (for the bend penalty). Hash
        # keys are always point-key strings, never a PathNode or a point.
        PathNode = Data.define(:point, :parent, :g_score, :f_score, :direction)

        # A plain x/y pair for points inside the search hot path. Far cheaper
        # to build than Geometry::Point, a lutaml-model object. Every search
        # helper reads only .x and .y, so the two are interchangeable there;
        # only points that leave the search become Geometry::Point.
        SearchPoint = Data.define(:x, :y) do
          # True when the segment between two points (of either kind) is
          # horizontal or vertical. The tolerance only absorbs float drift
          # from summing grid steps; it is far below any visible offset.
          def self.aligned?(from_pt, to_pt)
            (from_pt.x - to_pt.x).abs < 1e-6 || (from_pt.y - to_pt.y).abs < 1e-6
          end
        end

        # One edge's search area. The search never leaves it, and only
        # obstacles overlapping it are checked, so a short edge costs the same
        # however large the rest of the graph is.
        SearchBox = Data.define(:min_x, :min_y, :max_x, :max_y) do
          def self.around(start_point, end_point, margin)
            min_x, max_x = [start_point.x, end_point.x].minmax
            min_y, max_y = [start_point.y, end_point.y].minmax
            new(min_x: min_x - margin, min_y: min_y - margin,
                max_x: max_x + margin, max_y: max_y + margin)
          end

          def contains?(point)
            point.x.between?(min_x, max_x) && point.y.between?(min_y, max_y)
          end

          def overlaps?(rect)
            rect.right >= min_x && rect.left <= max_x &&
              rect.bottom >= min_y && rect.top <= max_y
          end
        end

        # A node's unpadded rectangle, as its center and half sizes.
        NodeBox = Data.define(:center_x, :center_y, :half_width, :half_height) do
          def self.of(node)
            half_width = (node.width || 0.0) / 2.0
            half_height = (node.height || 0.0) / 2.0
            new(center_x: (node.x || 0.0) + half_width,
                center_y: (node.y || 0.0) + half_height,
                half_width: half_width, half_height: half_height)
          end

          # Where the ray from the center toward `target` crosses the
          # boundary; the center itself when the two coincide.
          def border_toward(target)
            offset_x = target.x - center_x
            offset_y = target.y - center_y
            scale = scale_to_border(offset_x, offset_y)
            Geometry::Point.new(x: center_x + (scale * offset_x),
                                y: center_y + (scale * offset_y))
          end

          private

          # The shortest fraction of the offset that reaches a side; 0 for a
          # zero offset.
          def scale_to_border(offset_x, offset_y)
            x_scale = half_width / offset_x.abs unless offset_x.zero?
            y_scale = half_height / offset_y.abs unless offset_y.zero?
            [x_scale, y_scale].compact.min || 0.0
          end
        end

        # A small binary min-heap over [f_score, sequence, point_key] tuples,
        # used as the A* open set. Tuples compare by f_score, then by
        # `sequence`, a monotonic tie-breaker, so equal-cost candidates come
        # out in the order they were pushed.
        #
        # Uses lazy deletion instead of decrease-key: #find_path pushes a new
        # tuple whenever a candidate improves and leaves the superseded one in
        # place. Every push for a given key carries an f_score no larger than
        # any earlier push for that key, so the heap's pop order guarantees
        # the best pending entry for a key always comes out before its
        # now-stale predecessors -- #find_path only needs to check whether a
        # popped key is already closed, never compare f_scores on pop.
        class OpenSetHeap
          def initialize
            @entries = []
          end

          def push(f_score, sequence, key)
            @entries << [f_score, sequence, key]
            sift_up(@entries.size - 1)
          end

          def pop
            return nil if @entries.empty?

            swap(0, @entries.size - 1)
            top = @entries.pop
            sift_down(0)
            top
          end

          def empty?
            @entries.empty?
          end

          private

          def sift_up(index)
            while index.positive?
              parent = (index - 1) / 2
              break unless less?(index, parent)

              swap(index, parent)
              index = parent
            end
          end

          def sift_down(index)
            loop do
              smallest = smallest_of(index)
              break if smallest == index

              swap(index, smallest)
              index = smallest
            end
          end

          # Whichever of `index` and its in-range children holds the smallest
          # tuple.
          def smallest_of(index)
            left = (2 * index) + 1
            children = [left, left + 1].select { |child| child < @entries.size }
            [index, *children].min_by { |position| @entries[position] }
          end

          def less?(first, second)
            (@entries[first] <=> @entries[second]).negative?
          end

          def swap(first, second)
            @entries[first], @entries[second] = @entries[second], @entries[first]
          end
        end

        private_constant :SearchPoint, :SearchBox, :NodeBox, :OpenSetHeap

        # Per-edge routing outcome, keyed by edge id: `:found` (a real
        # obstacle-avoiding path), `:capped` (the search limit was hit) or
        # `:no_path` (no path exists even ignoring the cap). Reset once per
        # #layout call (inside #apply_edge_routing), never per level, so a
        # hierarchical graph's nested edges keep their own diagnostics
        # instead of losing them to the next level's reset.
        attr_reader :routing_diagnostics

        def initialize(options = {})
          super
          @routing_diagnostics = {}
        end

        # Only places and pads nodes. Obstacle routing happens later, in
        # #apply_edge_routing, against every node's FINAL position and
        # size -- never here, where a constraint or a compound node's
        # parent-bound update could still move or resize a node afterward.
        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          position_nodes_if_needed(graph)

          # Pad now: padding shifts every node, and later steps (fixed
          # position, parent bounds) only move or resize individual nodes,
          # never re-run this bulk shift.
          apply_padding(graph)

          graph
        end

        protected

        # Routes every edge in the hierarchy around obstacles, at every
        # level, against nodes' final positions and sizes -- so a fixed
        # node's restored position and a compound node's grown bounds are
        # both already settled by the time an edge is drawn to them.
        def apply_edge_routing(graph)
          @routing_diagnostics = {}
          route_obstacle_edges(graph)
        end

        private

        # Route one level's own edges around its own nodes, then recurse
        # into every hierarchical child so its inner edges are routed
        # against that child's own nodes too.
        def route_obstacle_edges(graph)
          children = graph.children
          return unless children&.any?

          route_edges_with_obstacles(graph, build_obstacle_map(children))
          recurse_into_hierarchical_children(children)
        end

        # A hierarchical child's own nested level gets the same treatment,
        # against ITS nodes' final positions and sizes.
        def recurse_into_hierarchical_children(children)
          children.each do |node|
            next unless node.hierarchical?

            route_obstacle_edges(create_child_graph(node))
          end
        end

        # Position nodes if they don't have positions. Only nodes missing a
        # position are moved; already-positioned nodes are never touched.
        def position_nodes_if_needed(graph)
          unpositioned = graph.children.reject { |n| n.x && n.y }
          return if unpositioned.empty?

          positioned = graph.children.select { |n| n.x && n.y }
          spacing = node_spacing
          origin_x = positioned.any? ? (positioned.map { |n| n.x + n.width }.max + spacing) : 0.0

          max_width = unpositioned.map(&:width).max
          max_height = unpositioned.map(&:height).max
          cols = [Math.sqrt(unpositioned.length * 1.6).ceil, 1].max

          unpositioned.each_with_index do |node, i|
            row = i / cols
            col = i % cols
            node.x = origin_x + (col * (max_width + spacing))
            node.y = row * (max_height + spacing)
          end
        end

        # Build the padded obstacle rectangle for every node, keyed by node
        # id so per-edge exclusion is a plain string compare, never an
        # object or value comparison.
        def build_obstacle_map(nodes)
          padding = option("libavoid.routingPadding", 10).to_f

          nodes.to_h do |node|
            [node.id, Geometry::Rectangle.new(
              (node.x || 0) - padding,
              (node.y || 0) - padding,
              (node.width || 0) + (2 * padding),
              (node.height || 0) + (2 * padding),
            )]
          end
        end

        # Route every edge that joins two different nodes of this graph
        # around obstacles. Self-loops and edges ending on a port go to the
        # shared router instead, so a loop keeps its rectangular shape
        # instead of collapsing to a single point.
        def route_edges_with_obstacles(graph, obstacle_map)
          return unless graph.edges&.any?

          node_map = build_node_map(graph)

          graph.edges.each do |edge|
            if !self_loop?(edge) &&
                node_map.key?(edge.sources&.first) && node_map.key?(edge.targets&.first)
              route_single_edge(edge, node_map, obstacle_map)
            else
              route_edge_without_obstacles(edge, graph)
            end
          end
        end

        # The shared router's own dispatch (self-loop vs styled routing) for
        # a self-loop or an edge that does not join two of this level's own
        # nodes. Kept in step with EdgeRouter#route_edges.
        def route_edge_without_obstacles(edge, graph)
          node_index = NodeIndex.build(graph)
          routing_style = get_edge_routing_style(graph)

          if self_loop?(edge)
            route_self_loop(edge, node_index, graph, routing_style)
          else
            route_edge_with_style(edge, node_index, graph, routing_style)
          end
        end

        # Route a single edge around obstacles
        def route_single_edge(edge, node_map, obstacle_map)
          source_id = edge.sources.first
          target_id = edge.targets.first

          source_node = node_map[source_id]
          target_node = node_map[target_id]

          # Start and end at the node boundary facing the other node, not the
          # center -- so a "no bend needed" edge actually touches the node
          # rather than visibly running through its interior.
          start_point = NodeBox.of(source_node).border_toward(get_node_center(target_node))
          end_point = NodeBox.of(target_node).border_toward(get_node_center(source_node))

          bbox = edge_bbox(start_point, end_point)
          # An edge's own endpoints are never obstacles to it.
          candidates = obstacle_map.except(source_id, target_id).values
          obstacles = candidates.select { |rect| bbox.overlaps?(rect) }

          path, status = find_path(start_point, end_point, obstacles)
          @routing_diagnostics[edge.id] = status
          unless status == :found
            warn "Libavoid: edge #{edge.id} used fallback routing (#{status})"
          end

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

        # The endpoints' extent plus a margin that grows with their distance,
        # so a detour fits but far-away parts of the graph are never searched.
        def edge_bbox(start_point, end_point)
          margin = [2 * euclidean_distance(start_point, end_point), 8 * step_size].max
          SearchBox.around(start_point, end_point, margin)
        end

        def step_size
          option("libavoid.stepSize", 10.0).to_f
        end

        def max_expansions
          option("libavoid.maxExpansions", 2000).to_i
        end

        # A* pathfinding, bounded to the edge's search box and capped at `max_expansions`
        # expansions. Returns `[path_points, status]`, `status` one of
        # `:found`, `:capped` (the cap was hit), or `:no_path` (the goal is
        # unreachable within the bbox even ignoring the cap). A `:capped` or
        # `:no_path` result still returns a direct `[start, goal]` line; the
        # caller decides how to report it.
        def find_path(start, goal, obstacles)
          segment_penalty = option("libavoid.segmentPenalty", 1.0).to_f
          bend_penalty = option("libavoid.bendPenalty", 2.0).to_f
          cap = max_expansions
          bbox = edge_bbox(start, goal)

          heap = OpenSetHeap.new
          node_for_key = {}
          closed = {}
          sequence = 0

          start_key = point_key(start)
          start_node = PathNode.new(point: start, parent: nil, g_score: 0.0,
                                    f_score: heuristic(start, goal), direction: nil)
          node_for_key[start_key] = start_node
          heap.push(start_node.f_score, sequence, start_key)

          expansions = 0

          until heap.empty?
            _f, _seq, key = heap.pop
            next if closed[key]

            current = node_for_key[key]
            final_hop = try_final_hop(current, goal, obstacles)
            return [final_hop, :found] if final_hop

            closed[key] = true
            expansions += 1
            return [[start, goal], :capped] if expansions >= cap

            get_orthogonal_neighbors(current.point, obstacles, bbox).each do |neighbor_point, direction|
              neighbor_key = point_key(neighbor_point)
              next if closed[neighbor_key]

              distance = euclidean_distance(current.point, neighbor_point)
              direction_change_penalty = current.direction && current.direction != direction ? bend_penalty : 0
              tentative_g = current.g_score + distance + segment_penalty + direction_change_penalty

              existing = node_for_key[neighbor_key]
              next if existing && tentative_g >= existing.g_score

              f_score = tentative_g + heuristic(neighbor_point, goal)
              node_for_key[neighbor_key] = PathNode.new(
                point: neighbor_point, parent: current, g_score: tentative_g,
                f_score: f_score, direction: direction
              )
              sequence += 1
              heap.push(f_score, sequence, neighbor_key)
            end
          end

          [[start, goal], :no_path]
        end

        # Try to close the search from `current` straight to the real
        # `goal`, and return the completed path -- or nil when either leg
        # of that shortcut does not hold.
        #
        # `goal` is a border point on a node's edge -- a continuous
        # coordinate almost never an exact multiple of the search step away
        # from `start` in both axes, so an exact match in the caller's loop
        # would otherwise never happen and every edge would exhaust the
        # search cap regardless of obstacles. Accept arrival within one
        # grid step, finishing with a horizontal and a vertical leg through
        # whichever corner is clear -- never a diagonal, and never through
        # an obstacle just because the grid point next to it is close enough.
        def try_final_hop(current, goal, obstacles)
          point = current.point
          corner = clear_corner(point, goal, obstacles) if heuristic(point, goal) <= step_size
          return nil unless corner

          reconstruct_path(current) + [corner, goal]
        end

        # The corner of an L-shaped route from `point` to `goal` whose two
        # legs both miss every obstacle, or nil when neither corner does.
        def clear_corner(point, goal, obstacles)
          [SearchPoint.new(x: goal.x, y: point.y),
           SearchPoint.new(x: point.x, y: goal.y)].find do |corner|
            !collides_with_obstacles?(point, corner, obstacles) &&
              !collides_with_obstacles?(corner, goal, obstacles)
          end
        end

        # Get orthogonal neighbors (4-directional), dropping any candidate
        # outside `bbox` before checking obstacle collision.
        def get_orthogonal_neighbors(point, obstacles, bbox)
          step = step_size
          neighbors = []

          [
            [step, 0, :horizontal],    # right
            [-step, 0, :horizontal],   # left
            [0, step, :vertical],      # down
            [0, -step, :vertical], # up
          ].each do |dx, dy, direction|
            neighbor = SearchPoint.new(x: point.x + dx, y: point.y + dy)
            next unless bbox.contains?(neighbor)

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

          # Check if line intersects any edge of rectangle. SearchPoint, not
          # Geometry::Point: this runs on every collision check.
          rect_edges = [
            [SearchPoint.new(x: rect.x, y: rect.y),
             SearchPoint.new(x: rect.x + rect.width, y: rect.y)],
            [SearchPoint.new(x: rect.x + rect.width, y: rect.y),
             SearchPoint.new(x: rect.x + rect.width,
                             y: rect.y + rect.height)],
            [SearchPoint.new(x: rect.x + rect.width, y: rect.y + rect.height),
             SearchPoint.new(x: rect.x, y: rect.y + rect.height)],
            [SearchPoint.new(x: rect.x, y: rect.y + rect.height),
             SearchPoint.new(x: rect.x, y: rect.y)],
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

            # Try to connect point i to the furthest point it can reach in
            # one horizontal or vertical line without hitting an obstacle
            while j > i + 1
              if SearchPoint.aligned?(all_points[i], all_points[j]) &&
                  !collides_with_obstacles?(all_points[i], all_points[j], obstacles)
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

        # Build node map from graph
        def build_node_map(graph)
          map = {}
          graph.children&.each do |node|
            map[node.id] = node
          end
          map
        end
      end
    end
  end
end
