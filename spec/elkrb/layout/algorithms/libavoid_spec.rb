# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe Elkrb::Layout::Algorithms::Libavoid do
  let(:algorithm) { described_class.new }

  # Independent axis-aligned segment/rectangle intersection check, used to
  # verify a routed path avoids an obstacle. Deliberately does NOT call
  # Libavoid's own private `line_intersects_rectangle?` -- a bug shared by
  # both the algorithm and this check would otherwise pass silently. `rect`
  # is a Hash with :x, :y, :width, :height.
  def point_in_rect?(pt_x, pt_y, rect)
    pt_x.between?(rect[:x], rect[:x] + rect[:width]) &&
      pt_y.between?(rect[:y], rect[:y] + rect[:height])
  end

  def rect_edges(rect)
    min_x = rect[:x]
    max_x = rect[:x] + rect[:width]
    min_y = rect[:y]
    max_y = rect[:y] + rect[:height]
    corners = [[min_x, min_y], [max_x, min_y], [max_x, max_y], [min_x, max_y]]

    corners.each_cons(2).to_a << [corners.last, corners.first]
  end

  def segment_intersects_rect?(from_pt, to_pt, rect)
    return true if point_in_rect?(from_pt.x, from_pt.y, rect)
    return true if point_in_rect?(to_pt.x, to_pt.y, rect)

    seg_a = [from_pt.x, from_pt.y]
    seg_b = [to_pt.x, to_pt.y]
    rect_edges(rect).any? { |edge_start, edge_end| segments_cross?(seg_a, seg_b, edge_start, edge_end) }
  end

  # True when the two endpoints of one segment fall on opposite sides of
  # the LINE through the other segment.
  def straddles?(line_start, line_end, point_a, point_b)
    side_a = cross_product(line_start, line_end, point_a)
    side_b = cross_product(line_start, line_end, point_b)

    (side_a.positive? && side_b.negative?) || (side_a.negative? && side_b.positive?)
  end

  # Each argument is a [x, y] pair. Standard orientation-based segment
  # intersection: true only when seg_a straddles seg_b AND seg_b straddles
  # seg_a -- a shared endpoint or collinear touch does not count as crossing.
  def segments_cross?(seg_a_start, seg_a_end, seg_b_start, seg_b_end)
    straddles?(seg_b_start, seg_b_end, seg_a_start, seg_a_end) &&
      straddles?(seg_a_start, seg_a_end, seg_b_start, seg_b_end)
  end

  def cross_product(origin, to_pt, point)
    ((point[0] - origin[0]) * (to_pt[1] - origin[1])) -
      ((to_pt[0] - origin[0]) * (point[1] - origin[1]))
  end

  # The obstacle's padded rectangle, computed independently from the node's
  # own declared attributes and the routingPadding option -- not by calling
  # the algorithm's `build_obstacle_map`.
  def padded_rect(node, padding)
    { x: node.x - padding, y: node.y - padding,
      width: node.width + (2 * padding), height: node.height + (2 * padding) }
  end

  def path_points(section)
    [section.start_point] + (section.bend_points || []) + [section.end_point]
  end

  # True when the segment between two points is horizontal or vertical.
  def straight?(from_pt, to_pt)
    (from_pt.x - to_pt.x).abs < 0.001 || (from_pt.y - to_pt.y).abs < 0.001
  end

  # The segments of a routed section that are neither horizontal nor
  # vertical, as coordinate pairs so a failure prints them readably.
  def diagonal_segments(section)
    diagonals = path_points(section).each_cons(2).reject { |pair| straight?(*pair) }
    diagonals.map { |pair| pair.map { |pt| [pt.x, pt.y] } }
  end

  # True when `point` lies on one of `node`'s four edges (within
  # `tolerance`), as opposed to its interior or somewhere off the node
  # entirely: inside a rectangle grown by `tolerance`, but not inside the
  # same rectangle shrunk by it.
  def on_node_border?(point, node, tolerance = 0.001)
    outer = padded_rect(node, tolerance)
    inner = padded_rect(node, -tolerance)

    point_in_rect?(point.x, point.y, outer) && !point_in_rect?(point.x, point.y, inner)
  end

  describe "the A* open set" do
    let(:heap) { described_class.const_get(:OpenSetHeap).new }

    it "pops the lowest f_score first, and equal scores in push order" do
      # "z" and "a" tie on f_score; "z" was pushed first, so a heap that
      # fell back to comparing keys would put "a" first.
      [[5, 0, "k"], [1, 1, "z"], [3, 2, "m"], [1, 3, "a"], [4, 4, "q"],
       [2, 5, "b"]].each { |f_score, sequence, key| heap.push(f_score, sequence, key) }
      popped = []
      popped << heap.pop.last until heap.empty?

      expect(popped).to eq(%w[z a b m q k])
    end

    it "stays ordered when pushes and pops interleave, as A* uses it" do
      rng = Random.new(42)
      pending_entries = []
      popped = []
      expected = []
      200.times do |sequence|
        if pending_entries.empty? || rng.rand < 0.6
          entry = [rng.rand(0..15), sequence, "k#{sequence}"]
          heap.push(*entry)
          pending_entries << entry
        else
          expected << pending_entries.delete(pending_entries.min)
          popped << heap.pop
        end
      end

      expect(popped).to eq(expected)
    end

    it "pops nil once empty" do
      heap.push(1, 0, "only")
      heap.pop

      expect(heap.pop).to be_nil
    end
  end

  describe "#layout" do
    context "with basic routing (2 nodes, 1 edge)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "libavoid" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n2", x: 200, y: 0, width: 60, height: 40),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(
            id: "e1",
            sources: ["n1"],
            targets: ["n2"],
          ),
        ]
      end

      it "positions nodes if not already positioned" do
        # Reset positions
        graph.children.each do |n|
          n.x = nil
          n.y = nil
        end

        algorithm.layout(graph)

        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
        end
      end

      it "sets graph dimensions" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0
      end
    end

    context "with multiple edges" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "libavoid" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n2", x: 200, y: 0, width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n3", x: 100, y: 100, width: 60,
                                 height: 40),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"], targets: ["n2"]),
          Elkrb::Graph::Edge.new(id: "e2", sources: ["n2"], targets: ["n3"]),
          Elkrb::Graph::Edge.new(id: "e3", sources: ["n3"], targets: ["n1"]),
        ]
      end

      it "routes all edges" do
        algorithm.layout(graph)

        graph.edges.each do |edge|
          expect(edge.sections).not_to be_empty
          section = edge.sections.first
          expect(section.start_point).to be_a(Elkrb::Geometry::Point)
          expect(section.end_point).to be_a(Elkrb::Geometry::Point)
        end
      end

      it "creates valid routing for each edge" do
        algorithm.layout(graph)

        graph.edges.each do |edge|
          section = edge.sections.first
          expect(section.start_point.x).to be_a(Numeric)
          expect(section.end_point.x).to be_a(Numeric)
        end
      end
    end

    context "routing around a real obstacle (the reported defect's own repro)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root")
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "b", x: 200, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "c", x: 100, y: -20, width: 50, height: 90),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"]),
        ]
      end

      it "finds a real path, not the fallback" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics["e"]).to eq(:found)
      end

      it "never crosses the obstacle it was asked to avoid" do
        algorithm.layout(graph)

        obstacle = graph.children.find { |n| n.id == "c" }
        rect = padded_rect(obstacle, 10.0)
        section = graph.edges.first.sections.first
        points = path_points(section)

        points.each_cons(2) do |p1, p2|
          expect(segment_intersects_rect?(p1, p2, rect)).to be false
        end
      end

      it "produces at least one bend to get around the obstacle" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        expect(section.bend_points.size).to be >= 1
      end

      it "goes around with horizontal and vertical segments only" do
        algorithm.layout(graph)

        expect(diagonal_segments(graph.edges.first.sections.first)).to eq([])
      end

      it "stays silent on stderr when a real path is found" do
        expect { algorithm.layout(graph) }.not_to output.to_stderr
      end
    end

    context "with a fixed-position node (the reported defect's own repro)" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 100, y: 100, width: 40, height: 40,
              constraints: { "fixedPosition" => true } },
            { id: "b", x: 300, y: 100, width: 40, height: 40 },
          ],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      it "keeps the edge attached to the fixed node's final border" do
        algorithm.layout(graph)

        node_a = graph.children.find { |n| n.id == "a" }
        start = graph.edges.first.sections.first.start_point

        # The constraint must actually have held -- otherwise the border
        # check below is meaningless.
        expect([node_a.x, node_a.y]).to eq([100.0, 100.0])
        expect(on_node_border?(start, node_a)).to be true
      end
    end

    context "with a compound node that grows after its top-level edge routes" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "p", x: 0, y: 0, width: 50, height: 50,
              children: [
                { id: "c1", x: 0, y: 0, width: 20, height: 20 },
                { id: "c2", x: 300, y: 300, width: 20, height: 20 },
              ] },
            { id: "q", x: 500, y: 0, width: 50, height: 50 },
          ],
          edges: [{ id: "e", sources: ["p"], targets: ["q"] }],
        )
      end

      it "attaches to p's grown border, not its pre-resize size" do
        algorithm.layout(graph)

        node_p = graph.children.find { |n| n.id == "p" }
        start = graph.edges.first.sections.first.start_point

        # p must actually have grown to contain c2 -- otherwise the border
        # check below is meaningless.
        expect(node_p.width).to be > 50.0
        expect(on_node_border?(start, node_p)).to be true
      end
    end

    context "with edges at two different hierarchy levels" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "p", x: 0, y: 0, width: 300, height: 300,
              children: [
                { id: "c1", x: 0, y: 0, width: 20, height: 20 },
                { id: "c2", x: 200, y: 0, width: 20, height: 20 },
              ],
              edges: [{ id: "e_nested", sources: ["c1"], targets: ["c2"] }] },
            { id: "q", x: 500, y: 0, width: 50, height: 50 },
          ],
          edges: [{ id: "e_top", sources: ["p"], targets: ["q"] }],
        )
      end

      it "keeps diagnostics for both the top-level and the nested edge" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics.keys).to contain_exactly("e_top", "e_nested")
        expect(algorithm.routing_diagnostics.values).to all(eq(:found))
      end
    end

    context "with a self-loop on a port (not a plain owned-node edge)" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50,
              ports: [{ id: "a_p1", x: 50, y: 25, width: 1, height: 1 }] },
          ],
          edges: [{ id: "e", sources: ["a_p1"], targets: ["a_p1"] }],
        )
      end

      it "gets bend points away from its start, not a single collapsed point" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        start = section.start_point

        expect(section.bend_points).not_to be_empty
        expect(section.bend_points).to all(
          satisfy { |bend| (bend.x - start.x).abs > 0.001 || (bend.y - start.y).abs > 0.001 },
        )
      end
    end

    context "with a self-loop on a plain node" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 50, height: 50 }],
          edges: [{ id: "e", sources: ["a"], targets: ["a"] }],
        )
      end

      it "gets a real loop from the shared router, not a single collapsed point" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        start = section.start_point

        expect(algorithm.routing_diagnostics).not_to have_key("e")
        expect(section.bend_points).not_to be_empty
        expect(section.bend_points).to all(
          satisfy { |bend| (bend.x - start.x).abs > 0.001 || (bend.y - start.y).abs > 0.001 },
        )
      end
    end

    context "with two nodes that share no row or column" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50 },
            { id: "b", x: 200, y: 40, width: 50, height: 50 },
          ],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      it "turns one corner instead of drawing one diagonal line" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        expect(algorithm.routing_diagnostics["e"]).to eq(:found)
        expect(diagonal_segments(section)).to eq([])
        expect(section.bend_points.size).to eq(1)
      end
    end

    context "with two nodes whose borders fall between grid steps" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50 },
            { id: "b", x: 203, y: 47, width: 50, height: 50 },
          ],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      it "still reaches the goal with horizontal and vertical segments only" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics["e"]).to eq(:found)
        expect(diagonal_segments(graph.edges.first.sections.first)).to eq([])
      end
    end

    context "with an off-grid goal and no obstacles" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root")
      end

      before do
        # Border-to-border distance here is not an exact multiple of the
        # default 10-unit step in either axis.
        graph.children = [
          Elkrb::Graph::Node.new(id: "n1", x: 10, y: 10, width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n2", x: 200, y: 100, width: 60,
                                 height: 40),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"], targets: ["n2"]),
        ]
      end

      it "resolves to a real path quickly instead of exhausting the search cap" do
        elapsed = Benchmark.realtime { algorithm.layout(graph) }

        expect(algorithm.routing_diagnostics["e1"]).to eq(:found)
        expect(elapsed).to be < 1.0
      end
    end

    context "when the search cap is hit" do
      let(:algorithm) { described_class.new("libavoid.maxExpansions" => 1) }
      let(:graph) { Elkrb::Graph::Graph.new(id: "root") }

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "b", x: 200, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "c", x: 100, y: -20, width: 50, height: 90),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"]),
        ]
      end

      it "reports :capped, distinctly from :found or silence" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics["e"]).to eq(:capped)
      end

      it "warns on stderr so the fallback is observable to a caller" do
        expect { algorithm.layout(graph) }.to output(/fallback routing \(capped\)/).to_stderr
      end
    end

    context "when the goal is genuinely unreachable" do
      let(:graph) { Elkrb::Graph::Graph.new(id: "root") }

      before do
        # `s` is boxed in on all four orthogonal sides; `t` is far away and
        # unreachable regardless of the search cap.
        graph.children = [
          Elkrb::Graph::Node.new(id: "s", x: 100, y: 100, width: 40, height: 40),
          Elkrb::Graph::Node.new(id: "t", x: 500, y: 100, width: 40, height: 40),
          Elkrb::Graph::Node.new(id: "north", x: 70, y: 40, width: 100, height: 50),
          Elkrb::Graph::Node.new(id: "south", x: 70, y: 150, width: 100, height: 50),
          Elkrb::Graph::Node.new(id: "east", x: 150, y: 70, width: 50, height: 100),
          Elkrb::Graph::Node.new(id: "west", x: 20, y: 70, width: 50, height: 100),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["s"], targets: ["t"]),
        ]
      end

      it "reports :no_path, distinctly from :capped" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics["e"]).to eq(:no_path)
      end

      it "warns on stderr so the fallback is observable to a caller" do
        expect { algorithm.layout(graph) }.to output(/fallback routing \(no_path\)/).to_stderr
      end
    end

    describe "#find_path's near-goal shortcut" do
      # Calls the private search directly: it is the only way to place an
      # obstacle exactly where the shortcut -- not a normal grid step --
      # would otherwise cut through it.
      it "never accepts the shortcut when the direct hop to goal is blocked" do
        start = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
        goal = Elkrb::Geometry::Point.new(x: 13.0, y: 9.0)
        # Reachable from (10, 10) -- within one grid step of goal by the
        # Manhattan heuristic -- but the straight line from there to goal,
        # and goal itself, sit inside this obstacle.
        obstacle = Elkrb::Geometry::Rectangle.new(11.0, 8.0, 14.0, 17.0)

        _path, status = algorithm.send(:find_path, start, goal, [obstacle])

        expect(status).to eq(:no_path)
      end

      it "turns at the other corner when the first corner's leg is blocked" do
        start = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
        goal = Elkrb::Geometry::Point.new(x: 6.0, y: 4.0)
        # Blocks only the horizontal leg from start toward the (6, 0) corner.
        obstacle = Elkrb::Geometry::Rectangle.new(2.0, -1.0, 2.0, 2.0)

        path, status = algorithm.send(:find_path, start, goal, [obstacle])

        expect(status).to eq(:found)
        expect(path.map { |pt| [pt.x, pt.y] }).to eq([[0.0, 0.0], [0.0, 4.0], [6.0, 4.0]])
      end
    end

    context "a graph too large for a linear-scan open set" do
      # 4-column grid, 150px spacing, chain n0 -> n1 -> ... -> n9 -- the
      # scenario measured during planning to hang for 20+ seconds against
      # the original Array-based open set once the root-cause exclusion fix
      # alone was applied.
      let(:graph) { Elkrb::Graph::Graph.new(id: "root") }

      before do
        nodes = (0...10).map do |i|
          col = i % 4
          row = i / 4
          Elkrb::Graph::Node.new(id: "n#{i}", x: col * 150.0, y: row * 150.0,
                                 width: 60, height: 40)
        end
        graph.children = nodes
        graph.edges = (0...9).map do |i|
          Elkrb::Graph::Edge.new(id: "e#{i}", sources: ["n#{i}"], targets: ["n#{i + 1}"])
        end
      end

      it "completes the whole graph in bounded time" do
        elapsed = Benchmark.realtime { algorithm.layout(graph) }

        # Every edge must really route, or a search that gives up at once
        # would pass on speed alone. The count guards against an empty
        # diagnostics hash trivially satisfying "all found".
        expect(algorithm.routing_diagnostics.size).to eq(9)
        expect(algorithm.routing_diagnostics.values).to all(eq(:found))
        # Generous for slow machines; a linear-scan open set takes over 20s.
        expect(elapsed).to be < 5.0
      end
    end

    context "routing one edge in a graph with many unrelated, far-away nodes" do
      # Same near-field problem (source, target, one blocking obstacle) in
      # two graphs that differ only in how much unrelated, far-away extra
      # graph surrounds it. Regression guard for the per-edge obstacle-list
      # scoping: without it, cost scales with total node count even though
      # nothing about this one edge's own geometry changed.
      def far_away_nodes(count)
        Array.new(count) do |i|
          Elkrb::Graph::Node.new(id: "far#{i}", x: 5000.0 + (i * 100),
                                 y: 5000.0 + (i * 100), width: 40, height: 40)
        end
      end

      def build_graph(extra_node_count)
        graph = Elkrb::Graph::Graph.new(id: "root")
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "b", x: 200, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "c", x: 100, y: -20, width: 50, height: 90),
        ] + far_away_nodes(extra_node_count)
        graph.edges = [Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"])]
        graph
      end

      def fastest_layout_time(node_count)
        Array.new(3) { Benchmark.realtime { described_class.new.layout(build_graph(node_count)) } }.min
      end

      it "does not slow down as unrelated graph size grows" do
        # The large graph must still route for real, or giving up early
        # would pass on speed alone.
        algorithm.layout(build_graph(400))
        expect(algorithm.routing_diagnostics).to eq("e" => :found)

        small_time = fastest_layout_time(0)
        large_time = fastest_layout_time(400)

        # Minimum of 3 runs each, to absorb one-off GC/scheduling noise.
        # A 5x+0.5s margin still catches the regression this guards
        # against: without per-edge obstacle scoping, cost tracks total
        # node count, and 400 unrelated nodes is a ~134x growth from 3.
        expect(large_time).to be < (small_time * 5) + 0.5
      end
    end

    context "with two nodes side by side" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 50, height: 50 },
                     { id: "b", x: 200, y: 0, width: 50, height: 50 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      it "starts and ends on the facing borders, not the centers" do
        algorithm.layout(graph)

        source, target = graph.children
        section = graph.edges.first.sections.first
        expect([section.start_point.x, section.start_point.y])
          .to eq([source.x + 50, source.y + 25])
        expect([section.end_point.x, section.end_point.y])
          .to eq([target.x, target.y + 25])
      end
    end

    context "when the only way round lies outside the edge's search box" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 20, height: 20 },
                     { id: "b", x: 60, y: 0, width: 20, height: 20 },
                     { id: "wall", x: 35, y: -500, width: 10, height: 1000 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      it "gives up inside the box and reports :no_path" do
        expect { algorithm.layout(graph) }.to output(/no_path/).to_stderr
        expect(algorithm.routing_diagnostics).to eq("e" => :no_path)
      end
    end

    context "with an edge that ends on a port" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50,
              ports: [{ id: "a_p1", x: 50, y: 25, width: 1, height: 1 }] },
            { id: "b", x: 200, y: 0, width: 50, height: 50 },
          ],
          edges: [{ id: "e", sources: ["a_p1"], targets: ["b"] }],
        )
      end

      it "still routes it, starting at the port" do
        algorithm.layout(graph)

        node = graph.children.first
        start = graph.edges.first.sections.first.start_point
        expect([start.x, start.y]).to eq([node.x + 50, node.y + 25])
      end
    end

    context "with two positioned nodes and one unpositioned sibling" do
      let(:graph) { Elkrb::Graph::Graph.new(id: "root") }

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "n1", x: 10, y: 20, width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n2", x: 300, y: 150, width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n3", width: 60, height: 40),
        ]
        graph.edges = []
      end

      it "never moves the already-positioned siblings" do
        # Exercises #position_nodes_if_needed directly, not the full
        # #layout -- #layout's later apply_padding step legitimately
        # renormalizes every node's coordinates to the graph's bounding
        # box, which shifts even untouched nodes by a constant amount
        # once a third node is added. That renormalization is correct,
        # pre-existing behavior, unrelated to this fix; the property this
        # fix owns is narrower: positioning the missing node must not
        # rewrite x/y on nodes that already had them.
        algorithm.send(:position_nodes_if_needed, graph)

        n1_after = graph.children.find { |n| n.id == "n1" }
        n2_after = graph.children.find { |n| n.id == "n2" }
        n3_after = graph.children.find { |n| n.id == "n3" }

        expect(n1_after.x).to eq(10)
        expect(n1_after.y).to eq(20)
        expect(n2_after.x).to eq(300)
        expect(n2_after.y).to eq(150)
        expect(n3_after.x).to be_a(Numeric)
        expect(n3_after.y).to be_a(Numeric)
      end

      it "places the unpositioned node to the right of every positioned one" do
        algorithm.send(:position_nodes_if_needed, graph)

        n3_after = graph.children.find { |n| n.id == "n3" }

        # origin_x is the rightmost positioned edge (n2 at x=300, width=60)
        # plus the default 20px node spacing -- not the node's own width,
        # not zero, and not n1's edge.
        expect(n3_after.x).to eq(380.0)
        expect(n3_after.y).to eq(0.0)
      end
    end

    context "with a custom libavoid.stepSize" do
      let(:algorithm) { described_class.new("libavoid.stepSize" => 37.5) }
      let(:graph) { Elkrb::Graph::Graph.new(id: "root") }

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "b", x: 200, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "c", x: 100, y: -20, width: 50, height: 90),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"]),
        ]
      end

      it "reads the option instead of the hardcoded default" do
        expect(algorithm.send(:step_size)).to eq(37.5)
      end

      it "searches the A* grid at the configured step, not the 10-unit default" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        start = section.start_point

        expect(section.bend_points).not_to be_empty
        section.bend_points.each do |bend|
          nearest_x = start.x + (((bend.x - start.x) / 37.5).round * 37.5)
          nearest_y = start.y + (((bend.y - start.y) / 37.5).round * 37.5)

          expect(bend.x).to be_within(0.01).of(nearest_x)
          expect(bend.y).to be_within(0.01).of(nearest_y)
        end
      end
    end

    context "with routingPadding set to 0" do
      let(:algorithm) { described_class.new("libavoid.routingPadding" => 0) }
      let(:graph) { Elkrb::Graph::Graph.new(id: "root") }

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "b", x: 200, y: 0, width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "c", x: 100, y: -20, width: 50, height: 90),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"]),
        ]
      end

      it "does not collapse the search step to zero" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics["e"]).to eq(:found)
        expect(graph.edges.first.sections.first.bend_points.size).to be >= 1
      end

      it "still avoids the obstacle" do
        algorithm.layout(graph)

        obstacle = graph.children.find { |n| n.id == "c" }
        rect = padded_rect(obstacle, 0.0)
        section = graph.edges.first.sections.first

        path_points(section).each_cons(2) do |p1, p2|
          expect(segment_intersects_rect?(p1, p2, rect)).to be false
        end
      end
    end

    context "with edge sections created properly" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "libavoid" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n2", x: 200, y: 100, width: 60,
                                 height: 40),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"], targets: ["n2"]),
        ]
      end

      it "creates edge sections with correct structure" do
        algorithm.layout(graph)

        edge = graph.edges.first
        expect(edge.sections).to be_an(Array)
        expect(edge.sections.size).to eq(1)

        section = edge.sections.first
        expect(section).to be_a(Elkrb::Graph::EdgeSection)
        expect(section.id).to be_a(String)
      end

      it "initializes bend_points array" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        expect(section.bend_points).to be_an(Array)
      end

      it "sets start and end points correctly" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        n1 = graph.children[0]
        n2 = graph.children[1]

        # Start point should be at or near center of n1
        expected_start_x = n1.x + (n1.width / 2.0)
        expected_start_y = n1.y + (n1.height / 2.0)

        # Allow larger tolerance since nodes may be repositioned
        expect(section.start_point.x).to be_within(50.0).of(expected_start_x)
        expect(section.start_point.y).to be_within(50.0).of(expected_start_y)

        # End point should be at or near center of n2
        expected_end_x = n2.x + (n2.width / 2.0)
        expected_end_y = n2.y + (n2.height / 2.0)

        expect(section.end_point.x).to be_within(50.0).of(expected_end_x)
        expect(section.end_point.y).to be_within(50.0).of(expected_end_y)
      end
    end

    context "with different node layouts" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: {
            "algorithm" => "libavoid",
            "elk.spacing.nodeNode" => 30.0,
          },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "n1", width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n2", width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n3", width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n4", width: 60, height: 40),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"], targets: ["n2"]),
          Elkrb::Graph::Edge.new(id: "e2", sources: ["n2"], targets: ["n3"]),
        ]
      end

      it "positions nodes when not pre-positioned" do
        algorithm.layout(graph)

        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end
      end

      it "routes edges after positioning nodes" do
        algorithm.layout(graph)

        graph.edges.each do |edge|
          expect(edge.sections).not_to be_empty
          section = edge.sections.first
          expect(section.start_point).to be_a(Elkrb::Geometry::Point)
          expect(section.end_point).to be_a(Elkrb::Geometry::Point)
        end
      end
    end

    context "with graph bounds calculation" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "libavoid" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "n1", x: 10, y: 10, width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n2", x: 200, y: 100, width: 60,
                                 height: 40),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"], targets: ["n2"]),
        ]
      end

      it "calculates graph bounds to contain all nodes" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0

        # Graph should contain all nodes
        graph.children.each do |node|
          expect(node.x + node.width).to be <= graph.width
          expect(node.y + node.height).to be <= graph.height
        end
      end

      it "includes padding in graph dimensions" do
        algorithm.layout(graph)

        # Graph dimensions should be larger than just the nodes
        max_x = graph.children.map { |n| n.x + n.width }.max
        max_y = graph.children.map { |n| n.y + n.height }.max

        expect(graph.width).to be >= max_x
        expect(graph.height).to be >= max_y
      end
    end

    context "with empty graph" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "libavoid" },
        )
      end

      before do
        graph.children = []
        graph.edges = []
      end

      it "handles empty graph gracefully" do
        expect { algorithm.layout(graph) }.not_to raise_error
      end
    end

    context "with no edges" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "libavoid" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "n1", width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "n2", width: 60, height: 40),
        ]
        graph.edges = []
      end

      it "positions nodes even without edges" do
        algorithm.layout(graph)

        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
        end
      end
    end
  end
end
