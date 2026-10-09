# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../algorithm_registry"
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
        # Released public API (1.0.2) that the search no longer uses; keep it
        # unchanged and do not build new search code on it. See SearchNode.
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

        # An immutable A* search record: the point, its parent (for path
        # reconstruction), the cost so far, the estimated total cost, and the
        # direction of travel used to reach it (for the bend penalty). The
        # search's hash keys are `[grid_key, direction]` pairs, or GOAL_KEY for
        # the goal -- never a SearchNode or a point.
        SearchNode = Data.define(:point, :parent, :g_score, :f_score, :direction) do
          # This node extended by one straight leg to `target`: the same node
          # when the leg has no length, otherwise a SearchNode carrying the cost
          # of the leg, a segment penalty per grid step it spans (so a long
          # final hop costs what the same distance in grid steps does), and a
          # bend penalty on a change of direction.
          def extend_to(target, heading, plan)
            return self if SearchPoint.same?(point, target)

            length = SearchPoint.distance(point, target)
            cost = g_score + length + plan.segment_cost(length) + bend_cost(heading, plan)
            SearchNode.new(point: target, parent: self, g_score: cost,
                           f_score: cost + plan.estimate(target), direction: heading)
          end

          # The bend penalty for continuing in direction `heading`: none for
          # the first leg or a straight continuation.
          def bend_cost(heading, plan)
            turned = direction && direction != heading
            turned ? plan.bend : 0
          end

          # This node extended to `target` by two straight legs that meet at
          # `corner`.
          def extend_through(corner, target, plan)
            at_corner = extend_to(corner, heading_to(corner), plan)
            at_corner.extend_to(target, at_corner.heading_to(target), plan)
          end

          # The direction of a straight leg from this node to `target`.
          def heading_to(target)
            point.y == target.y ? :horizontal : :vertical
          end
        end

        # Largest value any numeric libavoid option is read as: far beyond any
        # real coordinate scale, yet small enough that the sums, products and
        # ratios of options and coordinates in the search stay finite.
        OPTION_CEILING = 1e9

        # The open-set key of the goal, which is not on the step grid.
        GOAL_KEY = :goal

        # What one search needs to cost a leg and to estimate the rest: the
        # goal and the three numeric options, read once per search instead of
        # once per step.
        SearchPlan = Data.define(:goal, :step, :segment, :bend) do
          # The cheapest cost of one unit of travel: the distance itself plus
          # its share of the segment penalty. Scaling the distance heuristic
          # by it keeps the heuristic a lower bound while letting it see the
          # penalty, so the search heads for the goal instead of flooding.
          def per_unit
            step.positive? ? 1.0 + (segment / step) : 1.0
          end

          # A lower bound on the cost left from `point`: the Manhattan
          # distance to the goal at the cheapest cost per unit.
          def estimate(point)
            ((point.x - goal.x).abs + (point.y - goal.y).abs) * per_unit
          end

          # The segment penalty for a leg of `length`: one per grid step.
          def segment_cost(length)
            segment * (step.positive? ? length / step : 1)
          end
        end

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

          # A search point is `origin` plus whole grid steps, so its step
          # counts identify it exactly, for any finite positive step size.
          # Rounding the coordinates instead merges distinct points once a
          # step is small. Zero, negative or non-finite steps (a caller
          # error, not a real grid) fall back to the exact offset instead of
          # dividing -- `(x / Float::INFINITY).round` raises FloatDomainError.
          def self.grid_key(point, origin, step)
            offset_x = point.x - origin.x
            offset_y = point.y - origin.y
            return [offset_x, offset_y] unless step.finite? && step.positive?

            [(offset_x / step).round, (offset_y / step).round]
          end

          # True when both points hold the same coordinates.
          def self.same?(first, second)
            first.x == second.x && first.y == second.y
          end

          # Which side of the line from `origin` to `second` the point `first`
          # lies on: positive on one side, negative on the other, zero on the
          # line. Exact, no tolerance.
          def self.cross(origin, first, second)
            origin_x = origin.x
            origin_y = origin.y
            ((first.x - origin_x) * (second.y - origin_y)) -
              ((second.x - origin_x) * (first.y - origin_y))
          end

          # The straight-line distance between two points (of either kind).
          def self.distance(from_pt, to_pt)
            dx = to_pt.x - from_pt.x
            dy = to_pt.y - from_pt.y
            Math.sqrt((dx * dx) + (dy * dy))
          end
        end

        # A straight segment, for the intersection test behind the collision
        # check.
        Segment = Data.define(:from, :to) do
          # True when the two segments cross, touch, or overlap. The strict
          # straddle test alone misses a collinear touch or overlap -- a
          # segment that runs exactly along one of the other's endpoints
          # scores every #side_of as zero and would otherwise be reported
          # clear, letting a search step wide enough to span an obstacle's
          # full width cross its boundary undetected.
          def intersects?(other)
            (straddles?(other) && other.straddles?(self)) ||
              touches?(other) || other.touches?(self)
          end

          # True when the endpoints of `other` lie strictly on opposite sides
          # of the line through this segment.
          def straddles?(other)
            first = side_of(other.from)
            second = side_of(other.to)
            (first.positive? && second.negative?) || (first.negative? && second.positive?)
          end

          # True when an endpoint of `other` lies on this segment.
          def touches?(other)
            endpoint_on?(other.from) || endpoint_on?(other.to)
          end

          # True when `point` is exactly on the line through this segment.
          def on_line?(point)
            side_of(point).zero?
          end

          # Which side of the line through this segment `point` lies on:
          # positive on one side, negative on the other, zero on the line.
          def side_of(point)
            SearchPoint.cross(from, point, to)
          end

          # True when `point` falls within the segment's bounding box. Only
          # meaningful for a point already on its line.
          def covers?(point)
            point.x.between?(*[from.x, to.x].minmax) &&
              point.y.between?(*[from.y, to.y].minmax)
          end

          private

          def endpoint_on?(point)
            on_line?(point) && covers?(point)
          end
        end

        # A rectangle's real footprint, independent of the sign of its
        # width/height. Elkrb::Geometry::Rectangle does not normalize on
        # construction (a node authored with a negative width/height keeps
        # it), so `rect.x + rect.width` can be LESS than `rect.x`; reading it
        # as the right edge directly made the point and segment checks
        # silently miss the obstacle's true footprint.
        Bounds = Data.define(:left, :right, :top, :bottom) do
          def self.of(rect)
            rect.is_a?(self) ? rect : from_rectangle(rect)
          end

          def self.from_rectangle(rect)
            origin_x = rect.x
            origin_y = rect.y
            left, right = [origin_x, origin_x + rect.width].minmax
            top, bottom = [origin_y, origin_y + rect.height].minmax
            new(left: left, right: right, top: top, bottom: bottom)
          end

          # `rect` without its padding when it holds one of the `anchors`: the
          # padding is a preferred clearance, and a neighbour closer than twice
          # the padding would otherwise swallow the edge's own departure or
          # arrival point and leave it no way out.
          def self.relax(rect, padding, anchors)
            bounds = of(rect)
            return rect unless anchors.any? { |anchor| bounds.include?(anchor) }

            bounds.inset(padding).to_rectangle
          end

          # Inclusive of the boundary.
          def include?(point)
            point.x.between?(left, right) && point.y.between?(top, bottom)
          end

          # True when both ends of a segment lie past the same edge, so the
          # segment cannot touch the footprint. A NaN coordinate is never
          # beyond an edge, which leaves it to the full intersection test.
          def beyond?(from, to)
            [[from.x, to.x, left, right], [from.y, to.y, top, bottom]].any? do |one, other, low, high|
              (one < low && other < low) || (one > high && other > high)
            end
          end

          # True when the segment from `from` to `to` crosses or touches a
          # side of the footprint.
          def crossed_by?(from, to)
            return false if beyond?(from, to)

            segment = Segment.new(from: from, to: to)
            sides.any? { |side| segment.intersects?(side) }
          end

          # The four sides, as segments.
          def sides
            corners = [[left, top], [right, top], [right, bottom], [left, bottom]].map do |corner_x, corner_y|
              SearchPoint.new(x: corner_x, y: corner_y)
            end
            corners.zip(corners.rotate).map { |from, to| Segment.new(from: from, to: to) }
          end

          # The footprint shrunk by `amount` on every side.
          def inset(amount)
            with(left: left + amount, right: right - amount,
                 top: top + amount, bottom: bottom - amount)
          end

          def to_rectangle
            Geometry::Rectangle.new(left, top, right - left, bottom - top)
          end
        end

        # The two different nodes of one level an edge joins, directly or
        # through their ports. `resolve` is nil for a self-loop (including a
        # port back to its own node) or an edge that leaves the level.
        EdgeEnds = Data.define(:source, :target) do
          def self.resolve(edge, node_map)
            source, target = ids_to_nodes(edge, node_map)
            new(source: source, target: target) if source && target && !source.equal?(target)
          end

          # True for a self-loop by OWNER identity, not raw endpoint-id
          # equality -- a port back to its own node is one too, even though
          # its source and target ids differ.
          def self.same_owner?(edge, node_map)
            source, target = ids_to_nodes(edge, node_map)
            !!(source && target && source.equal?(target))
          end

          def self.ids_to_nodes(edge, node_map)
            [edge.sources&.first, edge.targets&.first].map { |id| id && node_map.node(id) }
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
          # center_x/y use the SIGNED width/height, same as build_obstacle_map's
          # `node.x + node.width`: (left + right) / 2 equals `x + width / 2`
          # whichever endpoint is smaller. half_width/half_height are stored
          # as magnitudes -- every caller (border_toward's division,
          # #overlaps?) treats them as a positive half-extent, which is also
          # what build_obstacle_map's own `.minmax` normalizes a negative
          # width or height down to, so the box matches the obstacle map's
          # rectangle for the same node.
          def self.of(node)
            width = node.width || 0.0
            height = node.height || 0.0
            new(center_x: (node.x || 0.0) + (width / 2.0),
                center_y: (node.y || 0.0) + (height / 2.0),
                half_width: width.abs / 2.0, half_height: height.abs / 2.0)
          end

          # Where the ray from the center toward `target` crosses the
          # boundary; the center itself when the two coincide -- or when
          # `scale` is zero for any other reason (a zero half-dimension on
          # the binding axis), since `0.0 * offset` should stay the center
          # even for an infinite offset. Ruby's `0.0 * Float::INFINITY` is
          # NaN, not 0.0, so the zero case is special-cased here rather than
          # left to the multiplication.
          def border_toward(target)
            offset_x = target.x - center_x
            offset_y = target.y - center_y
            scale = scale_to_border(offset_x, offset_y)
            return Geometry::Point.new(x: center_x, y: center_y) if scale.zero?

            Geometry::Point.new(x: center_x + (scale * offset_x),
                                y: center_y + (scale * offset_y))
          end

          # The side named `before` or `after` that `offset` points to.
          def self.facing(offset, before, after)
            offset.negative? ? before : after
          end

          # Which of the four sides `anchor` is closest to, as a fraction of
          # the corresponding half extent -- the axis nearer its own edge
          # wins, so a near-corner point still resolves to a single side
          # rather than a diagonal. An exact tie goes to the horizontal axis.
          def side_nearest(anchor)
            offset_x = anchor.x - center_x
            offset_y = anchor.y - center_y
            if x_fraction(offset_x) >= y_fraction(offset_y)
              NodeBox.facing(offset_x, "WEST", "EAST")
            else
              NodeBox.facing(offset_y, "NORTH", "SOUTH")
            end
          end

          private

          # How far `offset` is along a half extent; infinite when the extent
          # is zero, so that axis always wins.
          def x_fraction(offset)
            half_width.zero? ? Float::INFINITY : offset.abs / half_width
          end

          def y_fraction(offset)
            half_height.zero? ? Float::INFINITY : offset.abs / half_height
          end

          # The shortest fraction of the offset that reaches a side; 0 for a
          # zero offset.
          def scale_to_border(offset_x, offset_y)
            x_scale = half_width / offset_x.abs unless offset_x.zero?
            y_scale = half_height / offset_y.abs unless offset_y.zero?
            [x_scale, y_scale].compact.min || 0.0
          end
        end

        # Where an edge meets a node: the point on its border (or a port) and
        # the side of the node that point faces.
        Exit = Data.define(:anchor, :side) do
          # The point `distance` straight out from the anchor on its side
          # (never diagonally -- every segment this algorithm draws is
          # orthogonal). Any side other than WEST, NORTH or SOUTH is EAST.
          def clearance_point(distance)
            offset = %w[WEST NORTH].include?(side) ? -distance : distance
            shift_x, shift_y = %w[NORTH SOUTH].include?(side) ? [0.0, offset] : [offset, 0.0]
            Geometry::Point.new(x: anchor.x + shift_x, y: anchor.y + shift_y)
          end
        end

        # Builds the keys of #routing_diagnostics. ELK ids are arbitrary JSON
        # strings -- nothing in the format excludes "/", so joining hierarchy
        # segments with a bare "/" is not collision-safe: a top-level edge
        # literally named "p/e" and a nested edge "e" under node "p" both
        # produce the unescaped key "p/e". Escaping any "\" or "/" already
        # inside a segment before it is joined means the separator "/" in a
        # built key can only ever be a real hierarchy boundary.
        module DiagnosticsKey
          # The key of the edge `id` under the hierarchy `prefix` ("" at the
          # top level, otherwise the escaped ids of the enclosing nodes, each
          # followed by "/").
          def self.edge(prefix, id)
            "#{prefix}#{segment(id)}"
          end

          def self.segment(id)
            # Block form: a String replacement to gsub interprets leading
            # backslashes as backreferences (\1, \&, ...), so a plain
            # replacement string can't produce a literal "\\" reliably. A
            # block's return value is inserted as-is.
            id.to_s.gsub("\\") { "\\\\" }.gsub("/") { "\\/" }
          end
        end

        # A small binary min-heap over [f_score, sequence, grid_key] tuples:
        # the A* open set. Ties break by `sequence` (push order).
        #
        # Uses lazy deletion, not decrease-key -- #find_path pushes a new
        # tuple on every improvement and leaves the stale one in the heap.
        # Each push for a key carries an f_score no larger than the last,
        # so the best entry for a key always pops before its stale
        # predecessors: #find_path only needs to check whether a popped key
        # is already closed, never compare f_scores on pop.
        class OpenSetHeap
          def initialize
            @entries = []
          end

          def push(f_score, sequence, key)
            @entries << [f_score, sequence, key]
            sift_up(@entries.size - 1)
          end

          def pop
            last = @entries.pop
            return last if @entries.empty?

            replace_root(last)
          end

          def empty?
            @entries.empty?
          end

          private

          # Puts `entry` at the root in place of the smallest entry, which it
          # returns.
          def replace_root(entry)
            top = @entries.first
            @entries[0] = entry
            sift_down(0)
            top
          end

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

        # Tidies the route of one edge.
        module Waypoints
          # `points` without a repeated point or a point that sits on the
          # straight line between its neighbours. A middle point that doubles
          # back along the line (a stub that overshoots the other end's stub
          # in a narrow gap) is dropped too; the shortened line stays inside
          # the original.
          def self.simplify(points)
            points.each_with_object([]) do |point, kept|
              kept.pop while doubles_back?(kept, point)
              kept << point unless repeats?(kept, point)
            end
          end

          # True when the last kept point lies on the line from the one
          # before it to `point`.
          def self.doubles_back?(kept, point)
            kept.size >= 2 && Segment.new(from: kept[-2], to: point).on_line?(kept.last)
          end

          def self.repeats?(kept, point)
            kept.any? && SearchPoint.same?(kept.last, point)
          end
        end

        private_constant :OPTION_CEILING, :SearchNode, :SearchPoint, :EdgeEnds, :SearchBox, :NodeBox, :OpenSetHeap, :SearchPlan, :Segment,
                         :Bounds, :Exit, :DiagnosticsKey, :Waypoints

        def initialize(options = {})
          super
          @routing_diagnostics = {}
        end

        # Routing outcome of the last #layout call, keyed by edge id (a nested
        # edge's id is prefixed with its parent ids, joined by "/"; "\" and "/"
        # inside an id are backslash-escaped): `:found`, `:capped` (search
        # limit hit) or `:no_path` (no path, or a clearance stub blocked by
        # another node). Either fallback is drawn as a direct line and is
        # never overwritten by a later `:found` under the same key. Self-loops
        # and edges leaving their level are not listed.
        # @return [Hash{String => Symbol}] a frozen copy
        # @example
        #   algorithm.layout(graph)
        #   algorithm.routing_diagnostics # => { "e1" => :found }
        def routing_diagnostics
          @routing_diagnostics.dup.freeze
        end

        # Only places and pads nodes. Obstacle routing happens later, in
        # #apply_edge_routing, against every node's FINAL position and
        # size -- never here, where a constraint or a compound node's
        # parent-bound update could still move or resize a node afterward.
        # Edges are left unrouted by this method.
        #
        # @param graph [Elkrb::Graph::Graph] the graph whose children are placed
        # @param _options [Hash] unused
        # @return [Elkrb::Graph::Graph] the same graph
        # @example
        #   Elkrb::Layout::Algorithms::Libavoid.new.layout_flat(graph)
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
        # against that child's own nodes too. `diagnostics_prefix` qualifies
        # `routing_diagnostics` keys by hierarchy level so a nested edge id
        # that repeats a top-level (or sibling) edge id gets a distinct key
        # instead of silently overwriting it -- empty at the top level, so
        # the many existing top-level-only specs that key by a bare edge id
        # are unaffected.
        def route_obstacle_edges(graph, diagnostics_prefix = "")
          children = graph.children
          return unless children&.any?

          if graph.edges&.any?
            route_edges_with_obstacles(graph, build_obstacle_map(children), diagnostics_prefix)
          end
          recurse_into_hierarchical_children(children, diagnostics_prefix)
        end

        # A hierarchical child's own nested level gets the same treatment,
        # against ITS nodes' final positions and sizes, keyed under its own
        # id so a repeated edge id at a deeper level stays distinct too.
        #
        # Skip a node naming its OWN elk.algorithm: the hierarchical
        # processor lays that node out with the algorithm it names
        # (HierarchicalProcessor#child_layout_processor) through
        # #layout_hierarchical, which routes no edges, so the node's inner
        # edges keep no sections.
        def recurse_into_hierarchical_children(children, diagnostics_prefix)
          children.each do |node|
            next unless node.hierarchical?

            child_graph = create_child_graph(node)
            next if different_algorithm?(child_graph)

            route_obstacle_edges(child_graph, "#{diagnostics_prefix}#{DiagnosticsKey.segment(node.id)}/")
          end
        end

        # Read the way HierarchicalProcessor#child_layout_processor reads it.
        def different_algorithm?(child_graph)
          name = Options::Resolver.new.get("elk.algorithm", child_graph, default: nil)
          algorithm_class = name && AlgorithmRegistry.get(name)
          !algorithm_class.nil? && !algorithm_class.equal?(self.class)
        end

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

        # Build the padded obstacle rectangle for every node, keyed by node id.
        # Every node stays an obstacle for every edge, including the edge's own
        # endpoints (see #route_single_edge). Normalizes x/width and y/height
        # to the node's real footprint FIRST: Elkrb::Geometry::Rectangle does
        # not normalize a negative width/height on construction, so padding a
        # negative dimension directly (`width + 2*padding`) shrank and
        # mis-positioned the obstacle instead of expanding its real extent
        # by `padding` on every side.
        def build_obstacle_map(nodes)
          padding = routing_padding

          nodes.to_h do |node|
            left, right = [node.x || 0.0, (node.x || 0.0) + (node.width || 0.0)].minmax
            top, bottom = [node.y || 0.0, (node.y || 0.0) + (node.height || 0.0)].minmax

            [node.id, Geometry::Rectangle.new(
              left - padding,
              top - padding,
              (right - left) + (2 * padding),
              (bottom - top) + (2 * padding),
            )]
          end
        end

        # Route every edge that joins two different nodes of this graph, or
        # their ports, around obstacles. Self-loops (including a port back to
        # its own node) go to the shared router instead, so a loop keeps its
        # rectangular shape instead of collapsing to a single point.
        def route_edges_with_obstacles(graph, obstacle_map, diagnostics_prefix)
          # Raises ValidationError on a duplicate or missing id. Routable
          # edges never reach the shared router, so nothing else would check.
          node_map = NodeIndex.build(graph)
          graph.edges.each do |edge|
            ends = EdgeEnds.resolve(edge, node_map)
            next route_edge_by_owner(edge, graph, node_map) unless ends

            record_routing_status(DiagnosticsKey.edge(diagnostics_prefix, edge.id),
                                  route_single_edge(edge, ends, obstacle_map))
          end
        end

        # Keeps a fallback status when a later edge shares the key and was found.
        def record_routing_status(key, status)
          @routing_diagnostics[key] = status unless @routing_diagnostics.fetch(key, :found) != :found
        end

        # Dispatch for an edge whose ends did not resolve to two different
        # nodes: a self-loop (plain, or a port back to its own node) goes to
        # the shared router's loop routing; anything else (an edge that
        # leaves this level) goes to its ordinary style-based routing.
        def route_edge_by_owner(edge, graph, node_map)
          if EdgeEnds.same_owner?(edge, node_map)
            route_edge_as_self_loop(edge, graph)
          else
            route_edge_without_obstacles(edge, graph)
          end
        end

        # A self-loop, whether on a plain node or a port back to its own node.
        def route_edge_as_self_loop(edge, graph)
          node_map = NodeIndex.build(graph)
          route_self_loop(edge, node_map, graph, get_edge_routing_style(graph))
          pin_port_ends(edge, node_map)
        end

        # The shared router anchors a loop with only one port end (`a_p1 -> a`)
        # on the node itself. Move that end back onto its port, keeping the old
        # anchor as a bend reached through an orthogonal elbow.
        def pin_port_ends(edge, node_map)
          section = edge.sections&.first
          return unless section

          source_port = port_point(edge.sources.first, node_map)
          target_port = port_point(edge.targets.first, node_map)
          bends = section.bend_points || []
          if source_port && !same_point?(source_port, section.start_point)
            bends = [*port_elbow(source_port, section.start_point), section.start_point, *bends]
            section.start_point = source_port
          end
          if target_port && !same_point?(target_port, section.end_point)
            bends = [*bends, section.end_point, *port_elbow(target_port, section.end_point)]
            section.end_point = target_port
          end
          section.bend_points = bends
        end

        def port_point(id, node_map)
          node = node_map.node(id)
          port = node&.ports&.find { |candidate| candidate.id == id }
          port && get_port_absolute_position(port, node)
        end

        def port_elbow(port, anchor)
          return [] if port.x == anchor.x || port.y == anchor.y

          [Geometry::Point.new(x: anchor.x, y: port.y)]
        end

        def same_point?(one, other)
          other && one.x == other.x && one.y == other.y
        end

        # The shared router's own dispatch (self-loop vs styled routing) for
        # an edge that leaves this level entirely -- the id-based self_loop?
        # is correct here since no node_map lookup resolved either endpoint.
        def route_edge_without_obstacles(edge, graph)
          node_index = NodeIndex.build(graph)
          routing_style = get_edge_routing_style(graph)

          if self_loop?(edge)
            route_self_loop(edge, node_index, graph, routing_style)
          else
            route_edge_with_style(edge, node_index, graph, routing_style)
          end
        end

        # Route a single edge around obstacles and return its routing status
        # (`:found`, `:capped` or `:no_path`).
        #
        # Both endpoints keep their own node in the obstacle list, reached
        # by a short stub to a clearance point just outside that node's
        # padding -- excluding it is unsafe even for a plain endpoint, since
        # A* can double back through it once it is no longer in the
        # obstacle set. `clearance_point` already handles a nil port, so
        # ported and plain endpoints share this one path.
        def route_single_edge(edge, ends, obstacle_map)
          source_id = edge.sources.first
          target_id = edge.targets.first
          start_point = endpoint_point(source_id, ends.source, ends.target)
          end_point = endpoint_point(target_id, ends.target, ends.source)
          departure = clearance_point(source_id, start_point, ends.source)
          arrival = clearance_point(target_id, end_point, ends.target)

          bbox = edge_bbox(departure, arrival)
          nearby = obstacle_map.values.select { |rect| bbox.overlaps?(rect) }
          obstacles = nearby.map { |rect| Bounds.relax(rect, routing_padding, [departure, arrival]) }

          path, status = find_path(departure, arrival, obstacles)
          if status == :found && stub_blocked?(ends, [start_point, departure, arrival, end_point], obstacle_map)
            path = [departure, arrival]
            status = :no_path
          end
          unless status == :found
            warn "Libavoid: edge #{edge.id} used fallback routing (#{status})"
          end

          full_path = Waypoints.simplify([start_point, *path, end_point])

          # Create orthogonal segments from path
          bend_points = create_orthogonal_segments(full_path)

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
          status
        end

        # True when a clearance stub (the short leg from an endpoint to its
        # clearance point, which the search never covers) cuts through a node
        # other than the one it leaves. `points` is `[start, departure,
        # arrival, end]`; the other endpoint's node counts as a third node
        # for each stub.
        def stub_blocked?(ends, points, obstacle_map)
          start_point, departure, arrival, end_point = points
          [[start_point, departure, ends.source.id], [arrival, end_point, ends.target.id]]
            .any? { |from, to, owner_id| collides_with_obstacles?(from, to, footprints_except(owner_id, obstacle_map)) }
        end

        def footprints_except(owner_id, obstacle_map)
          obstacle_map.except(owner_id).values.map { |rect| Bounds.of(rect).inset(routing_padding) }
        end

        # A point just beyond `node`'s own padded obstacle rectangle, pushed
        # straight out from `anchor` on whichever side it sits on: the side
        # the port `id` declares when it is a port with one, otherwise
        # derived from `anchor`'s own position relative to the node (a plain
        # border-facing anchor already sits exactly on one side).
        def clearance_point(id, anchor, node)
          port_side = find_port_by_id(id, node)&.side
          side = port_side || NodeBox.of(node).side_nearest(anchor)
          Exit.new(anchor: anchor, side: side).clearance_point(clearance)
        end

        # How far beyond a node's border the edge's first and last point sit.
        # The margin on top of the padding only needs to clear the inclusive
        # boundary check by a positive amount -- a fixed 1.0 unit is fine at
        # the usual coordinate scale (padding defaults to 10), but a graph
        # laid out at a much smaller scale (a fractional step size implies
        # one -- see the "grid step below one hundredth" spec) would have the
        # search cover a margin 100x its own size, and blow the expansion cap
        # on every edge. Never exceed `step_size`.
        def clearance
          routing_padding + [1.0, step_size].min
        end

        # The endpoints' extent plus a margin that grows with their distance,
        # so a detour fits but far-away parts of the graph are never searched.
        def edge_bbox(start_point, end_point)
          margin = [2 * SearchPoint.distance(start_point, end_point), 8 * step_size].max
          SearchBox.around(start_point, end_point, margin)
        end

        # The one reader for every numeric libavoid option, so none reaches
        # the search unchecked. The resolver raises ValidationError on a
        # non-numeric or non-finite value; a finite value outside
        # `floor..OPTION_CEILING` reads as the nearer bound.
        def numeric_option(key, floor:)
          Float(option(key)).clamp(floor, OPTION_CEILING)
        end

        # Zero is the documented no-search case; a negative step would point
        # the clearance stubs back through their own nodes.
        def step_size
          numeric_option("libavoid.stepSize", floor: 0.0)
        end

        # A negative padding would shrink every obstacle below its node and
        # let a route cut through it.
        def routing_padding
          numeric_option("libavoid.routingPadding", floor: 0.0)
        end

        def max_expansions
          numeric_option("libavoid.maxExpansions", floor: 0.0).to_i
        end

        # A negative penalty would reward the segments and bends it prices.
        def segment_penalty
          numeric_option("libavoid.segmentPenalty", floor: 0.0)
        end

        def bend_penalty
          numeric_option("libavoid.bendPenalty", floor: 0.0)
        end

        # A* pathfinding, bounded to the edge's search box and capped at `max_expansions`
        # expansions. Returns `[path_points, status]`, `status` one of
        # `:found`, `:capped` (the cap was hit), or `:no_path` (the goal is
        # unreachable within the bbox even ignoring the cap). A `:capped` or
        # `:no_path` result still returns a direct `[start, goal]` line; the
        # caller decides how to report it.
        def find_path(start, goal, obstacles)
          # A non-finite start or goal (e.g. a node with an Infinity/NaN
          # coordinate) breaks the grid math before any obstacle is even
          # considered: `SearchPoint.grid_key` keys the start against
          # itself, and `Infinity - Infinity` is NaN regardless of step
          # size, well before `numeric_option`'s own sanitizing (which only
          # covers OPTIONS, not node/port geometry) ever applies. Treat it
          # the same as an unreachable goal rather than letting the search
          # raise deep inside the grid math.
          unless start.x.finite? && start.y.finite? && goal.x.finite? && goal.y.finite?
            return [[start, goal], :no_path]
          end

          cap = max_expansions
          return [[start, goal], :capped] if cap.zero?

          bbox = edge_bbox(start, goal)
          # Normalised once: every neighbour test below runs against each one.
          obstacles = obstacles.map { |obstacle| Bounds.of(obstacle) }

          step = step_size
          plan = SearchPlan.new(goal: goal, step: step, segment: segment_penalty, bend: bend_penalty)
          heap = OpenSetHeap.new
          node_for_key = {}
          closed = {}
          sequence = 0

          start_key = [SearchPoint.grid_key(start, start, step), nil]
          start_node = SearchNode.new(point: start, parent: nil, g_score: 0.0,
                                      f_score: plan.estimate(start), direction: nil)
          node_for_key[start_key] = start_node
          heap.push(start_node.f_score, sequence, start_key)

          expansions = 0

          until heap.empty?
            _f, _seq, key = heap.pop
            next if closed[key]

            current = node_for_key[key]
            return [reconstruct_path(current), :found] if key == GOAL_KEY

            closed[key] = true
            expansions += 1
            # The goal is a continuous border point that the step grid rarely
            # contains, so any grid point with a clear L-shaped route to it --
            # not only one a step away -- may finish the search. The hop is
            # costed like any other step.
            corner = clear_corner(current.point, goal, obstacles)
            hop = corner && current.extend_through(corner, goal, plan)
            if hop && hop.g_score < (node_for_key[GOAL_KEY]&.g_score || Float::INFINITY)
              node_for_key[GOAL_KEY] = hop
              sequence += 1
              heap.push(hop.f_score, sequence, GOAL_KEY)
            end
            if expansions >= cap
              best = node_for_key[GOAL_KEY]
              return best ? [reconstruct_path(best), :found] : [[start, goal], :capped]
            end

            get_orthogonal_neighbors(current.point, obstacles, bbox).each do |neighbor_point, direction|
              # The bend penalty depends on how a point was reached, so the
              # same point reached along the other axis is a different state.
              neighbor_key = [SearchPoint.grid_key(neighbor_point, start, step), direction]
              next if closed[neighbor_key]

              neighbor = current.extend_to(neighbor_point, direction, plan)
              existing = node_for_key[neighbor_key]
              next if existing && neighbor.g_score >= existing.g_score

              node_for_key[neighbor_key] = neighbor
              sequence += 1
              heap.push(neighbor.f_score, sequence, neighbor_key)
            end
          end

          [[start, goal], :no_path]
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
          return true if point_in_rectangle?(p1, rect) || point_in_rectangle?(p2, rect)

          Bounds.of(rect).crossed_by?(p1, p2)
        end

        # Check if point is inside rectangle
        def point_in_rectangle?(point, rect)
          Bounds.of(rect).include?(point)
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

        # Where an edge meets `node`: the port's position when `id` is a
        # port, otherwise the node boundary facing `other` -- so a "no bend
        # needed" edge touches the node rather than running through it.
        def endpoint_point(id, node, other)
          return get_port_position(id, node, nil) if find_port_by_id(id, node)

          NodeBox.of(node).border_toward(get_node_center(other))
        end
      end
    end
  end
end
