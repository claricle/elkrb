# frozen_string_literal: true

require "spec_helper"
require "timeout"

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

    it "stays usable after a pop on an empty heap" do
      heap.pop
      heap.push(1, 0, "only")

      expect([heap.pop, heap.empty?]).to eq([[1, 0, "only"], true])
    end
  end

  describe "SearchPoint.grid_key" do
    let(:search_point_class) { described_class.const_get(:SearchPoint) }
    let(:origin) { search_point_class.new(x: 0.0, y: 0.0) }

    it "keys by whole step counts from the origin, for a finite positive step" do
      point = search_point_class.new(x: 25.0, y: -10.0)

      expect(search_point_class.grid_key(point, origin, 5.0)).to eq([5, -2])
    end

    it "keys by exact offset, not division, for a non-finite step" do
      point = search_point_class.new(x: 25.0, y: -10.0)

      expect(search_point_class.grid_key(point, origin, Float::INFINITY))
        .to eq([25.0, -10.0])
    end

    it "does not raise FloatDomainError for an infinite step and an infinite offset" do
      point = search_point_class.new(x: -Float::INFINITY, y: 0.0)

      expect { search_point_class.grid_key(point, origin, Float::INFINITY) }
        .not_to raise_error
    end
  end

  describe "EdgeEnds.same_owner?" do
    let(:edge_ends_class) { described_class.const_get(:EdgeEnds) }
    let(:graph) do
      Elkrb::Graph::Graph.from_hash(
        id: "root",
        children: [{ id: "a", x: 0, y: 0, width: 50, height: 50 }],
      )
    end
    let(:node_map) { Elkrb::Layout::NodeIndex.build(graph) }

    it "is true when both ends resolve to the same node" do
      edge = Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["a"])

      expect(edge_ends_class.same_owner?(edge, node_map)).to be true
    end

    it "is false when only the target fails to resolve" do
      edge = Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["ghost"])

      expect(edge_ends_class.same_owner?(edge, node_map)).to be false
    end

    # `nil.equal?(nil)` is true, so a guard that drops the `source &&`
    # nil-check (leaving only `source.equal?(target)`) passes this case by
    # accident -- both ends must be unresolvable for the guard's nil-check
    # to matter on its own, not just one.
    it "is false when NEITHER end resolves to any node" do
      edge = Elkrb::Graph::Edge.new(id: "e", sources: ["ghost1"], targets: ["ghost2"])

      expect(edge_ends_class.same_owner?(edge, node_map)).to be false
    end
  end

  describe "NodeBox#border_toward" do
    let(:node_box_class) { described_class.const_get(:NodeBox) }

    it "returns the center, not NaN, when a half-dimension is zero and the offset is infinite" do
      # half_width 0 makes x_scale 0; multiplying that 0 by an infinite
      # offset_x is IEEE-754 NaN unless the zero-scale case short-circuits
      # before the multiplication.
      box = node_box_class.new(center_x: 5.0, center_y: 5.0, half_width: 0.0,
                               half_height: 10.0)
      target = Elkrb::Geometry::Point.new(x: Float::INFINITY, y: 5.0)

      border = box.border_toward(target)

      expect(border.x).to eq(5.0)
      expect(border.y).to eq(5.0)
    end
  end

  describe "SearchBox#overlaps?" do
    let(:search_box_class) { described_class.const_get(:SearchBox) }
    let(:box) do
      search_box_class.new(min_x: 0.0, min_y: 0.0, max_x: 100.0, max_y: 100.0)
    end

    it "is true when the rectangle's x AND y ranges both genuinely overlap the box" do
      rect = Elkrb::Geometry::Rectangle.new(10.0, 10.0, 10.0, 10.0)

      expect(box.overlaps?(rect)).to be true
    end

    it "is false when the x ranges overlap but the y ranges do not (rect entirely below the box)" do
      rect = Elkrb::Geometry::Rectangle.new(10.0, 200.0, 10.0, 10.0)

      expect(box.overlaps?(rect)).to be false
    end
  end

  describe "#recurse_into_hierarchical_children honouring a node's own elk.algorithm" do
    # A hierarchical child naming its own elk.algorithm is laid out by that
    # algorithm (HierarchicalProcessor#child_layout_processor), so Libavoid
    # must not reroute its inner edges (a "fixed" edge routed straight must
    # not gain Libavoid's clearance bends).
    let(:inner_edge) do
      Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"])
    end

    let(:inner_children) do
      [
        Elkrb::Graph::Node.new(id: "a", x: 0.0, y: 0.0, width: 10.0, height: 10.0),
        Elkrb::Graph::Node.new(id: "b", x: 50.0, y: 50.0, width: 10.0, height: 10.0),
      ]
    end

    before do
      sentinel = Elkrb::Graph::EdgeSection.new(id: "e_s1")
      sentinel.start_point = Elkrb::Geometry::Point.new(x: 1.0, y: 1.0)
      sentinel.end_point = Elkrb::Geometry::Point.new(x: 2.0, y: 2.0)
      inner_edge.sections = [sentinel]
    end

    it "leaves a node's edges untouched when it names a different registered algorithm" do
      node = Elkrb::Graph::Node.new(
        id: "p", x: 0.0, y: 0.0, width: 100.0, height: 100.0,
        layout_options: { "elk.algorithm" => "fixed" },
        children: inner_children, edges: [inner_edge]
      )

      algorithm.send(:recurse_into_hierarchical_children, [node], "")

      expect(inner_edge.sections.first.start_point.x).to eq(1.0)
    end

    it "still routes a node's edges with Libavoid when it names no algorithm of its own" do
      node = Elkrb::Graph::Node.new(
        id: "p", x: 0.0, y: 0.0, width: 100.0, height: 100.0,
        children: inner_children, edges: [inner_edge]
      )

      algorithm.send(:recurse_into_hierarchical_children, [node], "")

      expect(inner_edge.sections.first.start_point.x).not_to eq(1.0)
    end

    it "still routes a node's edges with Libavoid when it names libavoid itself" do
      # A node naming a different algorithm ("fixed", above) and a node
      # naming none (above) do not tell "same class" from "different class"
      # apart; this one does.
      node = Elkrb::Graph::Node.new(
        id: "p", x: 0.0, y: 0.0, width: 100.0, height: 100.0,
        layout_options: { "elk.algorithm" => "libavoid" },
        children: inner_children, edges: [inner_edge]
      )

      algorithm.send(:recurse_into_hierarchical_children, [node], "")

      expect(inner_edge.sections.first.start_point.x).not_to eq(1.0)
    end
  end

  describe "the options libavoid reads" do
    %w[libavoid.stepSize libavoid.maxExpansions libavoid.routingPadding
       libavoid.segmentPenalty libavoid.bendPenalty].each do |key|
      it "lists #{key} among the algorithm's supported options" do
        info = Elkrb::Layout::AlgorithmRegistry.algorithm_info("libavoid")

        expect(info[:supported_options]).to include(key)
      end
    end
  end

  describe "#layout" do
    context "when a node has a non-finite coordinate" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          layout_options: { "algorithm" => "libavoid" },
          children: [
            { id: "a", x: Float::INFINITY, y: 50.0, width: 20, height: 20 },
            { id: "b", x: 200.0, y: 50.0, width: 20, height: 20 },
          ],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      # Keep: guards find_path's non-finite start/goal return; it is the only check if that guard moves out of find_path.
      it "does not crash with a NaN comparison" do
        expect { algorithm.layout(graph) }.not_to raise_error
      end
    end
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

      # Keep: guards the orthogonal L-shaped hop in SearchNode#extend_through; it is the only check that no route turns diagonal.
      it "goes around with horizontal and vertical segments only" do
        algorithm.layout(graph)

        expect(diagonal_segments(graph.edges.first.sections.first)).to eq([])
      end

      # Keep: guards that route_single_edge warns only on a fallback; it is the only check that a found path prints nothing.
      it "stays silent on stderr when a real path is found" do
        expect { algorithm.layout(graph) }.not_to output.to_stderr
      end
    end

    # Libavoid draws every edge between two nodes of a level itself, as an
    # orthogonal route around the nodes. It does not hand those edges to the
    # shared router, so neither edgeRouting nor an edge's own elk.direction
    # reshapes them (the shared router would redraw them through the obstacle).
    context "with an edgeRouting style and an edge direction set" do
      let(:routed_points) do
        lambda do |style, direction|
          graph = Elkrb::Graph::Graph.new(id: "root")
          graph.layout_options = { "elk.edgeRouting" => style } if style
          graph.children = [
            Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 50, height: 50),
            Elkrb::Graph::Node.new(id: "b", x: 200, y: 0, width: 50, height: 50),
            Elkrb::Graph::Node.new(id: "c", x: 100, y: -20, width: 50, height: 90),
          ]
          edge = Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"])
          edge.layout_options = { "elk.direction" => direction } if direction
          graph.edges = [edge]
          described_class.new.layout(graph)
          [graph, path_points(graph.edges.first.sections.first)]
        end
      end
      let(:plain_route) { routed_points.call(nil, nil).last.map { |pt| [pt.x, pt.y] } }

      %w[ORTHOGONAL POLYLINE SPLINES].product([nil, "RIGHT", "DOWN"]).each do |style, direction|
        it "keeps the obstacle-avoiding route under #{style} with direction #{direction.inspect}" do
          graph, points = routed_points.call(style, direction)
          obstacle = padded_rect(graph.children.find { |n| n.id == "c" }, 10.0)

          expect(points.map { |pt| [pt.x, pt.y] }).to eq(plain_route)
          expect(points.each_cons(2).map { |from, to| segment_intersects_rect?(from, to, obstacle) })
            .to all(be(false))
        end
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

      it "keeps diagnostics for both the top-level and the nested edge, the nested one qualified by its parent node id" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics.keys).to contain_exactly("e_top", "p/e_nested")
        expect(algorithm.routing_diagnostics.values).to all(eq(:found))
      end
    end

    context "with a nested edge and an obstacle at the same nested level" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "p", x: 0, y: 0, width: 400, height: 300,
              children: [
                { id: "c1", x: 0, y: 40, width: 20, height: 20 },
                { id: "wall", x: 100, y: 0, width: 20, height: 100 },
                { id: "c2", x: 200, y: 40, width: 20, height: 20 },
              ],
              edges: [{ id: "e", sources: ["c1"], targets: ["c2"] }] },
          ],
        )
      end

      it "routes the nested edge around the nested obstacle" do
        algorithm.layout(graph)

        parent = graph.children.first
        wall = parent.children.find { |n| n.id == "wall" }
        section = parent.edges.first.sections.first

        expect(algorithm.routing_diagnostics["p/e"]).to eq(:found)
        expect(route_interior_crossings(section, wall)).to be_empty
        expect(section.bend_points).not_to be_empty
      end
    end

    context "with a top-level edge and a nested edge that share the SAME id" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "p", x: 0, y: 0, width: 300, height: 300,
              children: [
                { id: "c1", x: 0, y: 0, width: 20, height: 20 },
                { id: "c2", x: 200, y: 0, width: 20, height: 20 },
              ],
              edges: [{ id: "e", sources: ["c1"], targets: ["c2"] }] },
            { id: "q", x: 500, y: 0, width: 50, height: 50 },
          ],
          edges: [{ id: "e", sources: ["p"], targets: ["q"] }],
        )
      end

      it "keeps both the top-level and nested edge's diagnostics distinct, instead of the nested one overwriting the top-level one" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics.keys).to contain_exactly("e", "p/e")
        expect(algorithm.routing_diagnostics.values).to all(eq(:found))
      end
    end

    context "with a top-level edge id that itself contains the hierarchy separator" do
      # A top-level edge literally named "p/e" and a nested edge "e" under
      # node "p" would both key to the unescaped string "p/e" if the
      # separator were not distinguished from a "/" occurring inside an id
      # -- ELK ids are arbitrary JSON strings, so "/" is not excluded by the
      # format and must be escaped before being used as a join character.
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "p", x: 0, y: 0, width: 300, height: 300,
              children: [
                { id: "c1", x: 0, y: 0, width: 20, height: 20 },
                { id: "c2", x: 200, y: 0, width: 20, height: 20 },
              ],
              edges: [{ id: "e", sources: ["c1"], targets: ["c2"] }] },
            { id: "q", x: 500, y: 0, width: 50, height: 50 },
          ],
          edges: [{ id: "p/e", sources: ["p"], targets: ["q"] }],
        )
      end

      it "keeps the literal top-level id and the nested edge's qualified key distinct" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics.keys.uniq.size).to eq(2)
        expect(algorithm.routing_diagnostics.values).to all(eq(:found))
      end
    end

    context "with a parent node id that itself contains a literal backslash" do
      # A node id containing a backslash (here, the literal 2-character id
      # "p\") must have ITS OWN backslash escaped too, not just "/" --
      # otherwise the nested edge's qualified key ("p\" escaped-as-node +
      # "/" + "e") collides with a differently-parented top-level edge id
      # whose only escaped character is "/". Concretely: escaping only "/"
      # turns node id "p\" + edge "e" into the same string "p\/e" that
      # escaping only "/" also produces for the top-level edge id "p/e" --
      # escaping the backslash too (so the nested key becomes "p\\/e",
      # doubled backslash) is what keeps them apart.
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "p\\", x: 0, y: 0, width: 300, height: 300,
              children: [
                { id: "c1", x: 0, y: 0, width: 20, height: 20 },
                { id: "c2", x: 200, y: 0, width: 20, height: 20 },
              ],
              edges: [{ id: "e", sources: ["c1"], targets: ["c2"] }] },
            { id: "q", x: 500, y: 0, width: 50, height: 50 },
          ],
          edges: [{ id: "p/e", sources: ["p\\"], targets: ["q"] }],
        )
      end

      it "keeps the literal top-level id and the nested edge's qualified key distinct" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics.keys.uniq.size).to eq(2)
        expect(algorithm.routing_diagnostics.values).to all(eq(:found))
      end
    end

    context "with a self-loop on a port (not a plain owned-node edge)" do
      # The port sits on the WEST side, x:0 -- the EAST side (x: width)
      # coincides with the node-center routing fallback's own default
      # anchor, so a fixture routed only through that side cannot tell
      # the port fix from the fallback it is meant to replace.
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50,
              ports: [{ id: "a_p1", x: 0, y: 25, width: 1, height: 1, side: "WEST" }] },
          ],
          edges: [{ id: "e", sources: ["a_p1"], targets: ["a_p1"] }],
        )
      end

      # Keep: guards self-loop dispatch in route_edge_by_owner; it is the only check on a loop's port ends if the shared router changes.
      it "starts and ends at the port's own position, not the node center" do
        algorithm.layout(graph)

        node = graph.children.first
        port = node.ports.first
        section = graph.edges.first.sections.first

        expect([section.start_point.x, section.start_point.y]).to eq([node.x + port.x, node.y + port.y])
        expect([section.end_point.x, section.end_point.y]).to eq([node.x + port.x, node.y + port.y])
      end

      # Keep: guards self-loop dispatch in route_edge_by_owner; it is the only check that a loop keeps its shape.
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

    context "with an edge from a port back to its own owning node" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50,
              ports: [{ id: "a_p1", x: 0, y: 25, width: 1, height: 1, side: "WEST" }] },
          ],
          edges: [{ id: "e", sources: ["a_p1"], targets: ["a"] }],
        )
      end

      it "gets a real loop, not a straight line through the node" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        start = section.start_point

        expect(section.bend_points).not_to be_empty
        expect(section.bend_points).to all(
          satisfy { |bend| (bend.x - start.x).abs > 0.001 || (bend.y - start.y).abs > 0.001 },
        )
      end

      # Keep: guards self-loop dispatch in route_edge_by_owner; it is the only check that a loop is not retraced.
      it "traces a real loop, not an out-and-back retrace of the same line" do
        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        distinct = section.bend_points.uniq { |bend| [bend.x, bend.y] }

        expect(distinct.size).to eq(section.bend_points.size)
      end
    end

    context "with a loop between an off-centre port and its own node" do
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 100, height: 60,
              ports: [{ id: "a_p1", x: 20, y: 0, width: 0, height: 0, side: "NORTH" }] },
          ],
          edges: [
            { id: "out", sources: ["a_p1"], targets: ["a"] },
            { id: "in", sources: ["a"], targets: ["a_p1"] },
          ],
        )
      end

      { "out" => :start_point, "in" => :end_point }.each do |edge_id, port_end|
        it "keeps the #{port_end} of #{edge_id} on the port" do
          algorithm.layout(graph)

          node = graph.children.first
          port = node.ports.first
          point = graph.edges.find { |edge| edge.id == edge_id }.sections.first.public_send(port_end)

          expect([point.x, point.y]).to eq([node.x + port.x, node.y + port.y])
        end
      end
    end

    context "with two port-loops on the same node" do
      # Both ports are distinct from each other AND from the plain-node
      # self-loop's default anchor, so the two loops sharing a node can
      # only render identically if get_self_loop_index's owner-identity
      # counting or the port-anchoring logic regresses.
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50,
              ports: [
                { id: "a_p1", x: 0, y: 10, width: 1, height: 1, side: "WEST" },
                { id: "a_p2", x: 0, y: 40, width: 1, height: 1, side: "WEST" },
              ] },
          ],
          edges: [
            { id: "e1", sources: ["a_p1"], targets: ["a_p1"] },
            { id: "e2", sources: ["a_p2"], targets: ["a_p2"] },
          ],
        )
      end

      # Keep: guards self-loop dispatch in route_edge_by_owner; it is the only check that port loops stay apart.
      it "draws each loop at its own port, not on top of each other" do
        algorithm.layout(graph)

        section1 = graph.edges.find { |e| e.id == "e1" }.sections.first
        section2 = graph.edges.find { |e| e.id == "e2" }.sections.first

        expect(section1.start_point.y).not_to eq(section2.start_point.y)
        expect(section1.bend_points.map { |b| [b.x, b.y] })
          .not_to eq(section2.bend_points.map { |b| [b.x, b.y] })
      end
    end

    context "with an edge whose target leaves this level entirely" do
      # Neither source-equals-target nor a shared owner: the target id
      # names nothing in this level's node map (not a node, not a port).
      # Correct behaviour is no section at all, the same as any edge whose
      # endpoint cannot be resolved -- NOT a self-loop drawn on the source.
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 50, height: 50 }],
          edges: [{ id: "e", sources: ["a"], targets: ["ghost"] }],
        )
      end

      # Keep: guards route_edge_without_obstacles for an edge leaving the level; it is the only check that such an edge is not routed as a loop.
      it "gets no section, not a self-loop on the source node" do
        algorithm.layout(graph)

        sections = graph.edges.first.sections
        expect(sections).to(satisfy { |s| s.nil? || s.empty? })
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
        expect(section.bend_points).not_to be_empty

        # A plain endpoint's route never re-enters its OWN node's interior.
        # A bend-point COUNT would lock the clearance-stub shape instead.
        node_a = graph.children.find { |n| n.id == "a" }
        expect(route_interior_crossings(section, node_a)).to be_empty
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
        elapsed = elapsed_seconds { algorithm.layout(graph) }

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
    end

    context "when the search cap is zero" do
      let(:algorithm) { described_class.new("libavoid.maxExpansions" => 0) }
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 50, height: 50 },
                     { id: "b", x: 200, y: 0, width: 50, height: 50 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      it "falls back without expanding even when the first hop is clear" do
        expect { algorithm.layout(graph) }.to output(/fallback routing \(capped\)/).to_stderr
        expect(algorithm.routing_diagnostics).to eq("e" => :capped)
      end
    end

    context "when :capped and departure/arrival coincide exactly with the endpoints" do
      # At the default padding 10 and step size 10 `clearance_point` never
      # lands exactly on `start_point`/`end_point`. Padding 0 and step size 0
      # make its margin exactly 0, the one combination where departure and
      # arrival DO coincide with the
      # raw endpoints -- the same shape the existing ":no_path direct line"
      # spec covers, for the OTHER fallback status that returns `path` as a
      # direct [departure, arrival] line.
      let(:algorithm) do
        described_class.new("libavoid.maxExpansions" => 1, "libavoid.routingPadding" => 0,
                            "libavoid.stepSize" => 0)
      end
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

      it "wraps the :capped direct line without duplicating an endpoint" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics["e"]).to eq(:capped)

        section = graph.edges.first.sections.first
        points = path_points(section)

        expect(points.each_cons(2).none? { |from, to| from.x == to.x && from.y == to.y }).to be(true)
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

    describe "collision detection against a boundary-collinear crossing" do
      # A segment that runs exactly along an obstacle's edge -- both
      # endpoints strictly outside the rectangle, the segment collinear with
      # one of its four sides -- must still count as a collision. A search
      # step wide enough to clear an obstacle's full width in one hop
      # produces this for real.
      it "flags a segment that runs exactly along the obstacle's top edge" do
        obstacle = Elkrb::Geometry::Rectangle.new(52.0, 17.0, 30.0, 30.0)
        p1 = Elkrb::Geometry::Point.new(x: 33.0, y: 17.0)
        p2 = Elkrb::Geometry::Point.new(x: 101.0, y: 17.0)

        expect(algorithm.send(:collides_with_obstacles?, p1, p2,
                              [obstacle])).to be true
      end

      it "flags a segment that crosses through a zero-area obstacle" do
        obstacle = Elkrb::Geometry::Rectangle.new(50.0, 20.0, 0.0, 0.0)
        p1 = Elkrb::Geometry::Point.new(x: 40.0, y: 20.0)
        p2 = Elkrb::Geometry::Point.new(x: 60.0, y: 20.0)

        expect(algorithm.send(:collides_with_obstacles?, p1, p2,
                              [obstacle])).to be true
      end
    end

    describe "NodeBox#side_nearest" do
      let(:node_box_class) { described_class.const_get(:NodeBox) }
      let(:box) { node_box_class.new(center_x: 0.0, center_y: 0.0, half_width: 5.0, half_height: 5.0) }
      # half_width 20 / half_height 5: |offset_x| 6 > |offset_y| 4, but
      # 6 / 20 < 4 / 5, so a wide box puts the point nearer its bottom side.
      let(:wide_box) { node_box_class.new(center_x: 0.0, center_y: 0.0, half_width: 20.0, half_height: 5.0) }
      let(:zero_width_box) { node_box_class.new(center_x: 0.0, center_y: 0.0, half_width: 0.0, half_height: 5.0) }
      let(:zero_height_box) { node_box_class.new(center_x: 0.0, center_y: 0.0, half_width: 5.0, half_height: 0.0) }

      [
        ["a purely horizontal positive offset", :box, 3.0, 0.0, "EAST"],
        ["a purely horizontal negative offset", :box, -3.0, 0.0, "WEST"],
        ["a purely vertical positive offset", :box, 0.0, 3.0, "SOUTH"],
        ["a purely vertical negative offset", :box, 0.0, -3.0, "NORTH"],
        # half_width == half_height and |offset_x| == |offset_y|, so the
        # ratios are exactly equal -- the >= in the source must pick x.
        ["an exact tie on a square box (toward the horizontal axis)", :box, 4.0, 4.0, "EAST"],
        ["each axis measured against its own half extent", :wide_box, 6.0, 4.0, "SOUTH"],
        ["a zero half_width (the x axis always wins, even off-axis)", :zero_width_box, 0.0, 3.0, "EAST"],
        ["a zero half_height (the y axis always wins, even off-axis)", :zero_height_box, 3.0, 0.0, "SOUTH"],
      ].each do |description, box_name, offset_x, offset_y, expected|
        it "picks #{expected} for #{description}" do
          anchor = Elkrb::Geometry::Point.new(x: offset_x, y: offset_y)

          expect(public_send(box_name).side_nearest(anchor)).to eq(expected)
        end
      end
    end

    describe "Segment#covers?" do
      let(:segment_class) { described_class.const_get(:Segment) }
      let(:p1) { Elkrb::Geometry::Point.new(x: 0.0, y: 0.0) }
      let(:p2) { Elkrb::Geometry::Point.new(x: 10.0, y: 10.0) }
      let(:segment) { segment_class.new(from: p1, to: p2) }

      it "is true for a point exactly at one endpoint" do
        expect(segment.covers?(p1)).to be true
      end

      it "is false when the x coordinate falls outside the segment's bounding box" do
        outside = Elkrb::Geometry::Point.new(x: 11.0, y: 5.0)

        expect(segment.covers?(outside)).to be false
      end

      it "is false when x is in range but y falls outside the segment's bounding box" do
        outside_y = Elkrb::Geometry::Point.new(x: 5.0, y: 11.0)

        expect(segment.covers?(outside_y)).to be false
      end
    end

    describe "Segment#side_of (cross-product orientation)" do
      let(:segment_class) { described_class.const_get(:Segment) }
      let(:segment) do
        segment_class.new(from: Elkrb::Geometry::Point.new(x: 0.0, y: 0.0),
                          to: Elkrb::Geometry::Point.new(x: 10.0, y: 0.0))
      end

      it "is negative for a point to one side of the segment's line" do
        expect(segment.side_of(Elkrb::Geometry::Point.new(x: 5.0, y: 5.0))).to be < 0
      end

      it "is positive for a point to the other side of the segment's line" do
        expect(segment.side_of(Elkrb::Geometry::Point.new(x: 5.0, y: -5.0))).to be > 0
      end

      it "is exactly zero for a collinear point" do
        expect(segment.side_of(Elkrb::Geometry::Point.new(x: 5.0, y: 0.0))).to eq(0.0)
      end
    end

    describe "Bounds.of" do
      let(:bounds_class) { described_class.const_get(:Bounds) }

      it "returns left, right, top, bottom unchanged for a positive-width/height rect" do
        rect = Elkrb::Geometry::Rectangle.new(10.0, 20.0, 30.0, 40.0)

        expect(bounds_class.of(rect).to_h).to eq(left: 10.0, right: 40.0, top: 20.0, bottom: 60.0)
      end

      it "swaps left/right and top/bottom for a negative-width/height rect" do
        rect = Elkrb::Geometry::Rectangle.new(40.0, 60.0, -30.0, -40.0)

        expect(bounds_class.of(rect).to_h).to eq(left: 10.0, right: 40.0, top: 20.0, bottom: 60.0)
      end
    end

    describe "Bounds.of given a Bounds" do
      it "returns the same object, so a normalised footprint is not rebuilt per test" do
        bounds = described_class.const_get(:Bounds).of(Elkrb::Geometry::Rectangle.new(10.0, 20.0, 30.0, 40.0))

        expect(described_class.const_get(:Bounds).of(bounds)).to equal(bounds)
      end
    end

    describe "Bounds#beyond?" do
      let(:bounds) { described_class.const_get(:Bounds).new(left: 10.0, right: 20.0, top: 10.0, bottom: 20.0) }
      let(:point_class) { described_class.const_get(:SearchPoint) }

      [
        ["both ends left of the footprint", [0.0, 15.0], [5.0, 30.0], true],
        ["both ends right of the footprint", [25.0, 0.0], [30.0, 40.0], true],
        ["both ends above the footprint", [0.0, 5.0], [40.0, 9.0], true],
        ["both ends below the footprint", [0.0, 25.0], [40.0, 30.0], true],
        ["ends on opposite sides of the footprint", [0.0, 15.0], [30.0, 15.0], false],
        ["a diagonal that passes the corner at a distance", [0.0, 5.0], [30.0, 25.0], false],
        ["one end exactly on an edge", [10.0, 0.0], [10.0, 40.0], false],
        ["a corner touched by a diagonal", [0.0, 10.0], [10.0, 0.0], false],
        ["a NaN coordinate that decides the answer", [Float::NAN, 15.0], [0.0, 15.0], false],
      ].each do |name, from, to, expected|
        it "is #{expected} for #{name}" do
          result = bounds.beyond?(point_class.new(x: from[0], y: from[1]), point_class.new(x: to[0], y: to[1]))

          expect(result).to be(expected)
        end
      end
    end

    describe "#line_intersects_rectangle? with a far-away obstacle" do
      it "answers from the bounding test without building any segment" do
        bounds_class = described_class.const_get(:Bounds)
        point_class = described_class.const_get(:SearchPoint)
        far = bounds_class.of(Elkrb::Geometry::Rectangle.new(500.0, 500.0, 10.0, 10.0))
        allow(described_class.const_get(:Segment)).to receive(:new).and_call_original

        crossing = algorithm.send(:line_intersects_rectangle?, point_class.new(x: 0.0, y: 0.0),
                                  point_class.new(x: 10.0, y: 0.0), far)

        expect(crossing).to be false
        expect(described_class.const_get(:Segment)).not_to have_received(:new)
      end
    end

    describe "Exit#clearance_point" do
      let(:exit_class) { described_class.const_get(:Exit) }
      let(:anchor) { Elkrb::Geometry::Point.new(x: 5.0, y: 5.0) }

      [
        ["WEST", [-6.0, 5.0]],
        ["NORTH", [5.0, -6.0]],
        ["SOUTH", [5.0, 16.0]],
        ["EAST", [16.0, 5.0]],
        ["BOGUS", [16.0, 5.0]],
      ].each do |side, expected|
        it "pushes #{side} to #{expected.inspect}, EAST being the default for any other side" do
          exit_point = exit_class.new(anchor: anchor, side: side)

          point = exit_point.clearance_point(11.0)

          expect([point.x, point.y]).to eq(expected)
        end
      end
    end

    describe "#clearance_point" do
      let(:port) { Elkrb::Graph::Port.new(id: "p", side: "NORTH") }
      let(:node) do
        Elkrb::Graph::Node.new(id: "n", x: 0.0, y: 0.0, width: 10.0, height: 10.0, ports: [port])
      end

      it "pushes out of the side a port declares, by padding plus the clamped margin" do
        anchor = Elkrb::Geometry::Point.new(x: 5.0, y: 0.0)

        point = algorithm.send(:clearance_point, "p", anchor, node)

        expect([point.x, point.y]).to eq([5.0, -11.0])
      end

      it "prefers the side a port declares over the side its position suggests" do
        east_anchor = Elkrb::Geometry::Point.new(x: 10.0, y: 5.0)

        point = algorithm.send(:clearance_point, "p", east_anchor, node)

        expect([point.x, point.y]).to eq([10.0, -6.0])
      end

      it "derives the side from the anchor's position when the id is not a port" do
        anchor = Elkrb::Geometry::Point.new(x: 10.0, y: 5.0)

        point = algorithm.send(:clearance_point, "n", anchor, node)

        expect([point.x, point.y]).to eq([21.0, 5.0])
      end

      it "clamps the margin to the configured step_size when it is below 1.0" do
        small_step_algorithm = described_class.new("libavoid.stepSize" => 0.2)
        anchor = Elkrb::Geometry::Point.new(x: 10.0, y: 5.0)

        point = small_step_algorithm.send(:clearance_point, "n", anchor, node)

        expect(point.x).to eq(20.2)
      end
    end

    describe "#point_in_rectangle? boundary inclusivity" do
      let(:rect) { Elkrb::Geometry::Rectangle.new(10.0, 10.0, 20.0, 20.0) }

      # Keep: guards the inclusive left/top bound of Bounds#include?; it is the only check on that boundary.
      it "includes a point exactly on the left/top corner" do
        expect(algorithm.send(:point_in_rectangle?,
                              Elkrb::Geometry::Point.new(x: 10.0, y: 10.0), rect)).to be true
      end

      # Keep: guards the inclusive right/bottom bound of Bounds#include?; it is the only check on that boundary.
      it "includes a point exactly on the right/bottom corner" do
        expect(algorithm.send(:point_in_rectangle?,
                              Elkrb::Geometry::Point.new(x: 30.0, y: 30.0), rect)).to be true
      end

      # Keep: guards the right bound of Bounds#include?; it is the only check that a point past it is outside.
      it "excludes a point just past the right edge" do
        expect(algorithm.send(:point_in_rectangle?,
                              Elkrb::Geometry::Point.new(x: 30.1, y: 20.0), rect)).to be false
      end

      # Keep: guards the bottom bound of Bounds#include?; it is the only check that a point past it is outside.
      it "excludes a point just past the bottom edge" do
        expect(algorithm.send(:point_in_rectangle?,
                              Elkrb::Geometry::Point.new(x: 20.0, y: 30.1), rect)).to be false
      end
    end

    describe "#segment_penalty and #bend_penalty read custom finite options" do
      it "reads a custom segmentPenalty instead of the 1.0 default" do
        custom = described_class.new("libavoid.segmentPenalty" => 7.5)

        expect(custom.send(:segment_penalty)).to eq(7.5)
      end

      it "reads a custom bendPenalty instead of the 2.0 default" do
        custom = described_class.new("libavoid.bendPenalty" => 9.5)

        expect(custom.send(:bend_penalty)).to eq(9.5)
      end

      it "reads a custom maxExpansions instead of the 2000 default" do
        custom = described_class.new("libavoid.maxExpansions" => 42)

        expect(custom.send(:max_expansions)).to eq(42)
      end
    end

    describe "penalties steer the route, not just the option reader" do
      let(:start) { Elkrb::Geometry::Point.new(x: 0.0, y: 0.0) }
      let(:goal) { Elkrb::Geometry::Point.new(x: 80.0, y: 20.0) }
      # Two walls leave two ways round: over the top (2 bends, 140 long) or
      # down the middle (4 bends, 120 long).
      let(:walls) do
        [Elkrb::Geometry::Rectangle.new(45.0, -15.0, 30.0, 40.0),
         Elkrb::Geometry::Rectangle.new(5.0, 15.0, 30.0, 50.0)]
      end

      def route(options)
        path, status = described_class.new(options).send(:find_path, start, goal, walls)
        expect(status).to eq(:found)
        path.map { |pt| [pt.x, pt.y] }
      end

      def bends(path)
        path.each_cons(3).count { |a, b, c| (a[0] == b[0]) != (b[0] == c[0]) }
      end

      it "takes the fewer-bend route when bends are expensive" do
        expect(bends(route("libavoid.bendPenalty" => 60.0))).to eq(2)
      end

      it "takes the shorter route when bends are free" do
        expect(bends(route("libavoid.bendPenalty" => 0.0))).to be > 2
      end

      it "takes the shorter route when segments are expensive" do
        path = route("libavoid.bendPenalty" => 60.0, "libavoid.segmentPenalty" => 200.0)

        expect(path.each_cons(2).sum { |a, b| (a[0] - b[0]).abs + (a[1] - b[1]).abs }).to eq(120.0)
      end

      it "takes the fewer-bend route when segments are cheap" do
        path = route("libavoid.bendPenalty" => 60.0, "libavoid.segmentPenalty" => 0.0)

        expect(path.each_cons(2).sum { |a, b| (a[0] - b[0]).abs + (a[1] - b[1]).abs }).to eq(140.0)
      end
    end

    describe "SearchNode#extend_to" do
      let(:search_point_class) { described_class.const_get(:SearchPoint) }
      let(:plan_class) { described_class.const_get(:SearchPlan) }
      let(:goal) { Elkrb::Geometry::Point.new(x: 100.0, y: 0.0) }
      let(:plan) { plan_class.new(goal: goal, step: 10.0, segment: 5.0, bend: 7.0) }

      let(:origin) { search_point_class.new(x: 0.0, y: 0.0) }
      let(:fresh_node) do
        ->(point, direction) { described_class.const_get(:SearchNode).new(point: point, parent: nil, g_score: 0.0, f_score: 0.0, direction: direction) }
      end

      [
        ["costs its length plus one segment penalty per grid step on a first leg", nil, [30.0, 0.0], :horizontal, 45.0],
        ["adds no bend penalty when it continues in the same direction", :horizontal, [30.0, 0.0], :horizontal, 45.0],
        ["adds the bend penalty when it changes direction", :vertical, [30.0, 0.0], :horizontal, 52.0],
        ["charges a segment penalty per fractional step, so a long hop is not discounted", nil, [25.0, 0.0], :horizontal,
         37.5],
      ].each do |description, direction, (target_x, target_y), heading, expected_cost|
        it description do
          from = fresh_node.call(origin, direction)
          target = search_point_class.new(x: target_x, y: target_y)

          extended = from.extend_to(target, heading, plan)

          expect(extended.g_score).to eq(expected_cost)
        end
      end

      it "records the parent, the direction and an f_score of cost plus the plan's estimate" do
        from = fresh_node.call(origin, nil)
        target = search_point_class.new(x: 30.0, y: 0.0)

        extended = from.extend_to(target, :horizontal, plan)

        expect([extended.parent, extended.direction, extended.f_score])
          .to eq([from, :horizontal, 45.0 + plan.estimate(target)])
      end

      it "charges the segment penalty once when the step is not positive" do
        flat_plan = plan_class.new(goal: goal, step: 0.0, segment: 5.0, bend: 7.0)
        from = fresh_node.call(origin, nil)

        extended = from.extend_to(search_point_class.new(x: 12.0, y: 0.0), :horizontal, flat_plan)

        expect(extended.g_score).to eq(17.0)
      end

      it "returns the same node when the target is where it already is" do
        from = fresh_node.call(search_point_class.new(x: 4.0, y: 4.0), :vertical)

        expect(from.extend_to(Elkrb::Geometry::Point.new(x: 4.0, y: 4.0), :horizontal, plan)).to equal(from)
      end
    end

    describe "SearchNode#heading_to" do
      let(:search_point_class) { described_class.const_get(:SearchPoint) }
      let(:node) do
        described_class.const_get(:SearchNode).new(point: search_point_class.new(x: 5.0, y: 5.0), parent: nil,
                                                   g_score: 0.0, f_score: 0.0, direction: nil)
      end

      { "level with the node" => [30.0, 5.0, :horizontal],
        "above the node" => [5.0, 30.0, :vertical],
        "off both axes" => [30.0, 30.0, :vertical] }.each do |where, (target_x, target_y, heading)|
        it "is #{heading} for a target #{where}" do
          expect(node.heading_to(search_point_class.new(x: target_x, y: target_y))).to eq(heading)
        end
      end
    end

    describe "SearchPoint.aligned?" do
      let(:search_point_class) { described_class.const_get(:SearchPoint) }

      [
        ["share an x", [3.0, 0.0], [3.0, 40.0], true],
        ["share a y", [0.0, 3.0], [40.0, 3.0], true],
        ["differ by float drift on one axis", [3.0, 0.0], [3.0 + 1e-9, 40.0], true],
        ["differ visibly on both axes", [3.0, 0.0], [3.001, 40.0], false],
      ].each do |name, from, to, expected|
        it "is #{expected} for points that #{name}" do
          result = search_point_class.aligned?(search_point_class.new(x: from[0], y: from[1]),
                                               search_point_class.new(x: to[0], y: to[1]))

          expect(result).to be(expected)
        end
      end
    end

    describe "Bounds#crossed_by?" do
      let(:bounds) { described_class.const_get(:Bounds).new(left: 10.0, right: 20.0, top: 10.0, bottom: 20.0) }
      let(:point_class) { described_class.const_get(:SearchPoint) }

      [
        ["a diagonal through the footprint", [0.0, 0.0], [30.0, 30.0], true],
        ["a diagonal that cuts past a corner without touching it", [0.0, 15.0], [15.0, 0.0], false],
        ["a segment ending inside the footprint", [0.0, 15.0], [15.0, 15.0], true],
      ].each do |name, from, to, expected|
        it "is #{expected} for #{name}" do
          result = bounds.crossed_by?(point_class.new(x: from[0], y: from[1]), point_class.new(x: to[0], y: to[1]))

          expect(result).to be(expected)
        end
      end
    end

    describe "Segment#intersects?" do
      let(:segment_class) { described_class.const_get(:Segment) }

      # Every row is checked in both argument orders: the touch tests are
      # one-directional, so a T-junction only shows up from one side.
      [
        ["cross", [[0, 0], [10, 10]], [[0, 10], [10, 0]], true],
        ["meet in a T-junction", [[0, 0], [10, 0]], [[5, 0], [5, 5]], true],
        ["share an endpoint", [[0, 0], [5, 5]], [[5, 5], [10, 0]], true],
        ["overlap along one line", [[0, 0], [10, 0]], [[5, 0], [15, 0]], true],
        ["lie on one line without overlapping", [[0, 0], [4, 0]], [[6, 0], [10, 0]], false],
        ["are parallel", [[0, 0], [10, 0]], [[0, 1], [10, 1]], false],
        ["have lines that cross beyond one segment's end", [[0, 0], [4, 0]], [[6, -5], [6, 5]], false],
        ["have one segment's line crossing the other but not the reverse", [[0, 0], [10, 0]], [[5, 1], [5, 5]], false],
      ].each do |description, first, second, expected|
        it "is #{expected} for segments that #{description}" do
          to_segment = lambda do |(from_x, from_y), (to_x, to_y)|
            segment_class.new(from: Elkrb::Geometry::Point.new(x: from_x.to_f, y: from_y.to_f),
                              to: Elkrb::Geometry::Point.new(x: to_x.to_f, y: to_y.to_f))
          end
          one = to_segment.call(*first)
          other = to_segment.call(*second)

          expect([one.intersects?(other), other.intersects?(one)]).to eq([expected, expected])
        end
      end
    end

    describe "Waypoints.simplify" do
      let(:waypoints) { described_class.const_get(:Waypoints) }

      [
        ["a repeated first point", [[0, 0], [0, 0]], [[0, 0]]],
        ["a repeated point before a bend", [[0, 0], [0, 0], [0, 5]], [[0, 0], [0, 5]]],
        ["a point on the line between its neighbours", [[0, 0], [5, 0], [10, 0]], [[0, 0], [10, 0]]],
        ["a point that doubles back along the line", [[0, 0], [10, 0], [5, 0]], [[0, 0], [5, 0]]],
        ["nothing at a real bend", [[0, 0], [10, 0], [10, 10]], [[0, 0], [10, 0], [10, 10]]],
      ].each do |description, points, expected|
        it "drops #{description}" do
          input = points.map { |x, y| Elkrb::Geometry::Point.new(x: x.to_f, y: y.to_f) }

          result = waypoints.simplify(input)

          expect(result.map { |point| [point.x, point.y] }).to eq(expected.map { |pair| pair.map(&:to_f) })
        end
      end
    end

    describe "the search heads for the goal" do
      # Every step costs its length plus a segment penalty, so a distance-only
      # heuristic under-estimates and the search floods the box: several
      # times the collision checks on this row of nodes. A point is a search
      # state once per arrival heading, so the bound allows for that.
      it "does not flood the search box on a row of nodes" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: (0..4).map { |k| { id: "n#{k}", x: k * 100, y: 0, width: 40, height: 40 } } +
            (0..4).map { |k| { id: "m#{k}", x: k * 100, y: 100, width: 40, height: 40 } },
          edges: [{ id: "e", sources: ["n0"], targets: ["n4"] }],
        )
        checks = 0
        allow(algorithm).to receive(:collides_with_obstacles?).and_wrap_original do |original, *args|
          checks += 1
          original.call(*args)
        end

        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics["e"]).to eq(:found)
        expect(checks).to be < 1200
      end

      describe "SearchPlan#per_unit" do
        let(:plan_class) { described_class.const_get(:SearchPlan) }

        [
          ["one plus the segment penalty per step", 10.0, 5.0, 1.5],
          ["one when the segment penalty is zero", 10.0, 0.0, 1.0],
          ["one when the step is not positive", 0.0, 5.0, 1.0],
        ].each do |description, step, segment, expected|
          it "is #{description}" do
            plan = plan_class.new(goal: nil, step: step, segment: segment, bend: 2.0)

            expect(plan.per_unit).to eq(expected)
          end
        end
      end
    end

    describe "#routing_diagnostics" do
      context "when two edges share one id and only one of them has no path" do
        def wall_graph(first_edge_unreachable:)
          unreachable = { id: "dup", sources: ["a"], targets: ["b"] }
          reachable = { id: "dup", sources: ["c"], targets: ["d"] }
          Elkrb::Graph::Graph.from_hash(
            id: "root",
            children: [{ id: "a", x: 0, y: 0, width: 20, height: 20 },
                       { id: "b", x: 60, y: 0, width: 20, height: 20 },
                       { id: "wall", x: 35, y: -500, width: 10, height: 1000 },
                       { id: "c", x: 300, y: 0, width: 20, height: 20 },
                       { id: "d", x: 400, y: 0, width: 20, height: 20 }],
            edges: first_edge_unreachable ? [unreachable, reachable] : [reachable, unreachable],
          )
        end

        [true, false].each do |first|
          it "reports the fallback whichever edge comes first (unreachable first: #{first})" do
            graph = wall_graph(first_edge_unreachable: first)

            expect { algorithm.layout(graph) }.to output(/no_path/).to_stderr
            expect(algorithm.routing_diagnostics).to eq("dup" => :no_path)
          end
        end
      end

      it "returns a frozen copy, so a caller cannot rewrite the algorithm's record" do
        diagnostics = algorithm.routing_diagnostics

        expect(diagnostics).to be_frozen
        expect(diagnostics).not_to equal(algorithm.routing_diagnostics)
      end
    end

    describe "SearchBox#contains? and #overlaps?" do
      let(:search_box_class) { described_class.const_get(:SearchBox) }
      let(:box) { search_box_class.around(Elkrb::Geometry::Point.new(x: 0.0, y: 0.0), Elkrb::Geometry::Point.new(x: 10.0, y: 10.0), 5.0) }

      it "contains a point exactly on its boundary" do
        point = described_class.const_get(:SearchPoint).new(x: -5.0, y: 0.0)

        expect(box.contains?(point)).to be true
      end

      it "does not contain a point just outside its boundary" do
        point = described_class.const_get(:SearchPoint).new(x: -5.1, y: 0.0)

        expect(box.contains?(point)).to be false
      end

      it "overlaps a rectangle whose left edge is the box's right edge" do
        rect = Elkrb::Geometry::Rectangle.new(15.0, 0.0, 10.0, 10.0)

        expect(box.overlaps?(rect)).to be true
      end

      it "overlaps a rectangle whose right edge is the box's left edge" do
        rect = Elkrb::Geometry::Rectangle.new(-15.0, 0.0, 10.0, 10.0)

        expect(box.overlaps?(rect)).to be true
      end

      it "does not overlap a rectangle entirely past its right edge" do
        rect = Elkrb::Geometry::Rectangle.new(15.1, 0.0, 10.0, 10.0)

        expect(box.overlaps?(rect)).to be false
      end
    end

    describe "collision detection against a negative-width/height obstacle" do
      # Elkrb::Geometry::Rectangle does not normalize x/width or y/height on
      # construction, so a Rectangle authored with a negative width/height
      # (its real footprint is x[0,100] y[0,100] here) keeps it that way.
      # Reading rect.x/rect.y/rect.x+rect.width directly, as both helpers
      # used to, silently missed the obstacle entirely.
      it "flags a point strictly inside the obstacle's real (negative-authored) footprint" do
        obstacle = Elkrb::Geometry::Rectangle.new(100.0, 100.0, -100.0, -100.0)

        expect(algorithm.send(:point_in_rectangle?,
                              Elkrb::Geometry::Point.new(x: 50.0, y: 50.0),
                              obstacle)).to be true
      end

      # Keep: guards Bounds.from_rectangle normalising a negative width/height; it is the only check on crossing detection for such an obstacle.
      it "flags a segment that crosses a negative-authored obstacle without an endpoint inside it" do
        obstacle = Elkrb::Geometry::Rectangle.new(100.0, 100.0, -100.0, -100.0)
        p1 = Elkrb::Geometry::Point.new(x: 50.0, y: -10.0)
        p2 = Elkrb::Geometry::Point.new(x: 50.0, y: 110.0)

        expect(algorithm.send(:collides_with_obstacles?, p1, p2,
                              [obstacle])).to be true
      end
    end

    describe "#build_obstacle_map with a negative-width/height node" do
      it "pads the node's real footprint, not its raw (negative) one" do
        node = Elkrb::Graph::Node.new(id: "wall", x: 200, y: 90, width: -100,
                                      height: -140)

        rect = algorithm.send(:build_obstacle_map, [node])["wall"]
        padding = 10.0

        expect([rect.x, rect.y, rect.width, rect.height]).to eq(
          [100.0 - padding, -50.0 - padding, 100.0 + (2 * padding),
           140.0 + (2 * padding)],
        )
      end
    end

    describe "NodeBox.of with a negative-width node" do
      # NodeBox's half-extents are magnitudes, matching
      # #build_obstacle_map's always-normalized rectangle for the same
      # node. x=12, width=-20 -- build_obstacle_map's own [12, 12-20].minmax
      # gives the real footprint [-8, 12]; NodeBox.of must describe the
      # SAME rectangle, just as center +/- half-extent.
      it "describes the same real footprint build_obstacle_map normalizes to" do
        node_box_class = described_class.const_get(:NodeBox)
        node = Elkrb::Graph::Node.new(id: "n", x: 12.0, y: 0.0, width: -20.0,
                                      height: 10.0)

        box = node_box_class.of(node)

        expect([box.center_x - box.half_width, box.center_x + box.half_width])
          .to eq([-8.0, 12.0])
        expect(box.half_width).to be >= 0.0
      end
    end

    describe "#find_path expanding grid points" do
      it "expands each grid point at most once per arrival heading" do
        expanded = []
        allow(algorithm).to receive(:get_orthogonal_neighbors).and_wrap_original do |original, point, *rest|
          expanded << [point.x, point.y]
          original.call(point, *rest)
        end
        obstacles = [Elkrb::Geometry::Rectangle.new(30.0, -10.0, 30.0, 60.0),
                     Elkrb::Geometry::Rectangle.new(20.0, 20.0, 10.0, 10.0)]

        _path, status = algorithm.send(:find_path, Elkrb::Geometry::Point.new(x: 0.0, y: 0.0),
                                       Elkrb::Geometry::Point.new(x: 90.0, y: 40.0), obstacles)

        expect(status).to eq(:found)
        expect(expanded.tally.values.max).to be <= 4
      end

      it "takes the route with fewer bends when two routes are equally long" do
        obstacles = [Elkrb::Geometry::Rectangle.new(120.0, 20.0, 20.0, 40.0),
                     Elkrb::Geometry::Rectangle.new(0.0, 70.0, 30.0, 10.0),
                     Elkrb::Geometry::Rectangle.new(60.0, -20.0, 30.0, 30.0)]

        path, _status = algorithm.send(:find_path, Elkrb::Geometry::Point.new(x: 0.0, y: 0.0),
                                       Elkrb::Geometry::Point.new(x: 150.0, y: 20.0), obstacles)
        headings = path.each_cons(2).map { |from, to| [to.x <=> from.x, to.y <=> from.y] } - [[0, 0]]

        expect(headings.each_cons(2).count { |one, other| one != other }).to eq(4)
      end
    end

    describe "#find_path's near-goal shortcut" do
      # Calls the private search directly: it is the only way to place an
      # obstacle exactly where the shortcut -- not a normal grid step --
      # would otherwise cut through it. The Timeout turns a search that never
      # terminates (an unbounded grid walk) into a failure instead of a hang.
      it "never accepts the shortcut when the direct hop to goal is blocked" do
        start = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
        goal = Elkrb::Geometry::Point.new(x: 13.0, y: 9.0)
        # Reachable from (10, 10) -- within one grid step of goal by the
        # Manhattan heuristic -- but the straight line from there to goal,
        # and goal itself, sit inside this obstacle.
        obstacle = Elkrb::Geometry::Rectangle.new(11.0, 8.0, 14.0, 17.0)

        _path, status = Timeout.timeout(10.0) { algorithm.send(:find_path, start, goal, [obstacle]) }

        expect(status).to eq(:no_path)
      end

      it "turns at the other corner when the first corner's leg is blocked" do
        start = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
        goal = Elkrb::Geometry::Point.new(x: 6.0, y: 4.0)
        # Blocks only the horizontal leg from start toward the (6, 0) corner.
        obstacle = Elkrb::Geometry::Rectangle.new(2.0, -1.0, 2.0, 2.0)

        path, status = Timeout.timeout(10.0) { algorithm.send(:find_path, start, goal, [obstacle]) }

        expect(status).to eq(:found)
        expect(path.map { |pt| [pt.x, pt.y] }).to eq([[0.0, 0.0], [0.0, 4.0], [6.0, 4.0]])
      end

      it "returns the hop it already found when the expansion cap is reached" do
        capped = described_class.new("libavoid.maxExpansions" => 1)
        start = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
        goal = Elkrb::Geometry::Point.new(x: 50.0, y: 30.0)

        path, status = capped.send(:find_path, start, goal, [])

        expect(status).to eq(:found)
        expect(path.map { |pt| [pt.x, pt.y] }).to eq([[0.0, 0.0], [50.0, 0.0], [50.0, 30.0]])
      end
    end

    context "a graph too large for a linear-scan open set" do
      # 4-column grid, 150px spacing, chain n0 -> n1 -> ... -> n9.
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
        elapsed = elapsed_seconds { algorithm.layout(graph) }

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
        Array.new(3) { elapsed_seconds { described_class.new.layout(build_graph(node_count)) } }.min
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

    context "with two unobstructed nodes at any vertical offset" do
      # Offsets that are not a multiple of the 10-unit step: the goal is
      # never on the grid, so only a search that can finish off-grid passes.
      [0, 3, 7, 13, 29, 41, 57, 83, 100].each do |offset|
        it "routes offset #{offset} with a found, orthogonal path" do
          graph = Elkrb::Graph::Graph.from_hash(
            id: "root",
            children: [{ id: "a", x: 0, y: 0, width: 40, height: 40 },
                       { id: "b", x: 200, y: offset, width: 40, height: 40 }],
            edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
          )

          algorithm.layout(graph)

          expect(algorithm.routing_diagnostics["e"]).to eq(:found)
          expect(diagonal_segments(graph.edges.first.sections.first)).to eq([])
        end
      end
    end

    context "with a node between two others only the default padding apart" do
      # Two padded rectangles (10 each side) already overlap at a gap of 20,
      # so the departure point lies inside the neighbour's padding.
      [20, 22, 24, 30].each do |gap|
        it "routes a to c around b at gap #{gap}" do
          graph = Elkrb::Graph::Graph.from_hash(
            id: "root",
            children: [{ id: "a", x: 0, y: 0, width: 40, height: 40 },
                       { id: "b", x: 40 + gap, y: 0, width: 40, height: 40 },
                       { id: "c", x: 80 + (2 * gap), y: 0, width: 40, height: 40 }],
            edges: [{ id: "e", sources: ["a"], targets: ["c"] }],
          )

          algorithm.layout(graph)

          section = graph.edges.first.sections.first
          expect(algorithm.routing_diagnostics["e"]).to eq(:found)
          expect(route_interior_crossings(section, graph.children[1])).to be_empty
        end
      end
    end

    context "with a neighbour's padding holding only the departure point" do
      # a's departure point (51) lies inside c's padded rectangle (from 50),
      # but b's arrival point (289) lies in no padding at all.
      it "still routes a to b around c" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 40, height: 40 },
                     { id: "c", x: 60, y: 0, width: 40, height: 40 },
                     { id: "b", x: 300, y: 0, width: 40, height: 40 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )

        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        expect(algorithm.routing_diagnostics["e"]).to eq(:found)
        expect(route_interior_crossings(section, graph.children[1])).to be_empty
      end
    end

    context "with a neighbour's padding holding only the arrival point" do
      # b's arrival point (279) lies in c's padded rectangle (219 to 279),
      # while a's departure point (51) lies in no padding at all. Mirror of
      # the departure case above.
      it "still routes a to b around c" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 40, height: 40 },
                     { id: "c", x: 229, y: 0, width: 40, height: 40 },
                     { id: "b", x: 290, y: 0, width: 40, height: 40 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )

        algorithm.layout(graph)

        section = graph.edges.first.sections.first
        expect(algorithm.routing_diagnostics["e"]).to eq(:found)
        expect(route_interior_crossings(section, graph.children[1])).to be_empty
      end
    end

    context "with two level nodes whose clearance points overlap" do
      # Each end's clearance point is 11 units out, so a gap of 20 puts the
      # departure point past the arrival point.
      # Keep: guards Waypoints.simplify dropping a doubled-back point; it is the only check on overlapping clearance points.
      it "draws one straight line instead of overshooting and doubling back" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 40, height: 40 },
                     { id: "b", x: 60, y: 0, width: 40, height: 40 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )

        algorithm.layout(graph)

        expect(graph.edges.first.sections.first.bend_points).to be_empty
      end
    end

    context "with a graph whose children list is nil" do
      it "lays out and records no routing status" do
        graph = Elkrb::Graph::Graph.new(id: "root")
        graph.children = nil

        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics).to eq({})
      end
    end

    context "with only leaf nodes" do
      # Keep: guards the `hierarchical?` skip in recurse_into_hierarchical_children; it is the only check that a leaf costs no child graph.
      it "builds no child graph for any node" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 20, height: 20 },
                     { id: "b", x: 100, y: 0, width: 20, height: 20 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
        allow(algorithm).to receive(:create_child_graph).and_call_original

        algorithm.layout(graph)

        expect(algorithm).not_to have_received(:create_child_graph)
      end
    end

    context "with a third node close to an endpoint's clearance stub" do
      # a spans y 0 to 50 and b spans y 100 to 150, both x 0 to 100. The
      # departure stub runs y 50 to 61 and the arrival stub y 89 to 100, both
      # at x 50; the third node `c` is 5 high and 60 wide across them.
      {
        "through the departure stub" => [53, :no_path],
        "through the arrival stub" => [92, :no_path],
        "only in the padding of the departure stub" => [65, :found],
        "only in the padding of the arrival stub" => [80, :found],
      }.each do |where, (top, status)|
        it "reports #{status} for a node #{where}" do
          graph = Elkrb::Graph::Graph.from_hash(
            id: "root",
            children: [{ id: "a", x: 0, y: 0, width: 100, height: 50 },
                       { id: "c", x: 20, y: top, width: 60, height: 5 },
                       { id: "b", x: 0, y: 100, width: 100, height: 50 }],
            edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
          )

          algorithm.layout(graph)

          expect(algorithm.routing_diagnostics).to eq("e" => status)
        end
      end
    end

    context "when a third node blocks a stub and b sits to the right of a" do
      # The search alone would find an orthogonal route here; the blocked
      # stub makes it fall back to the direct line between the clearance points.
      it "replaces the searched route with the direct line" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 100, height: 50 },
                     { id: "c", x: 70, y: 92, width: 80, height: 5 },
                     { id: "b", x: 60, y: 100, width: 100, height: 50 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )

        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics).to eq("e" => :no_path)
        expect(diagonal_segments(graph.edges.first.sections.first).size).to eq(1)
      end
    end

    context "with two non-overlapping nodes one unit apart" do
      # Each end's stub, running straight out of its own node, crosses the
      # other end's node, so neither direction of the edge has a clean route.
      [%w[a b], %w[b a]].each do |source, target|
        it "reports :no_path for the edge #{source} to #{target}" do
          graph = Elkrb::Graph::Graph.from_hash(
            id: "root",
            children: [{ id: "a", x: 0, y: 0, width: 5, height: 20 },
                       { id: "b", x: 6, y: 0, width: 5, height: 20 }],
            edges: [{ id: "e", sources: [source], targets: [target] }],
          )

          algorithm.layout(graph)

          expect(algorithm.routing_diagnostics).to eq("e" => :no_path)
        end
      end
    end

    describe "#stub_blocked?" do
      # a spans x 0 to 20 and b spans x 100 to 120, both y 0 to 20. The points
      # are `[start, departure, arrival, end]`; a stub is the first two or
      # the last two.
      let(:nodes) do
        [Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 20, height: 20),
         Elkrb::Graph::Node.new(id: "b", x: 100, y: 0, width: 20, height: 20)]
      end
      let(:ends) { described_class.const_get(:EdgeEnds).new(source: nodes[0], target: nodes[1]) }
      let(:obstacle_map) { algorithm.send(:build_obstacle_map, nodes) }

      {
        "the source's stub runs through the target's node" => [[20, 10], [130, 10], [130, -50], [130, -40], true],
        "the target's stub runs through the source's node" => [[50, 50], [60, 50], [-10, 10], [30, 10], true],
        "each stub only leaves its own node" => [[10, 10], [30, 10], [90, 10], [110, 10], false],
        "no stub meets a node" => [[50, 50], [60, 50], [60, 60], [70, 60], false],
      }.each do |description, (*points, blocked)|
        it "is #{blocked} when #{description}" do
          corners = points.map { |x, y| Elkrb::Geometry::Point.new(x: x.to_f, y: y.to_f) }

          expect(algorithm.send(:stub_blocked?, ends, corners, obstacle_map)).to be(blocked)
        end
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

    context "when a short edge needs a detour wider than twice its length" do
      # The search box margin has a floor of eight grid steps: with only
      # twice the 40-unit edge length (80) the wall's far end (y=40) would
      # still fit, so the wall is placed to need the floor.
      it "finds the way round inside the floored search box" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 20, height: 20 },
                     { id: "b", x: 60, y: 0, width: 20, height: 20 },
                     { id: "wall", x: 35, y: -20, width: 10, height: 60 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )

        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics).to eq("e" => :found)
      end
    end

    context "when the search reaches grid points it has already closed" do
      # Measured 33 nodes built; 45 once closed points are extended again.
      it "builds no search node for a closed grid point" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 20, height: 20 },
                     { id: "b", x: 60, y: 0, width: 20, height: 20 },
                     { id: "wall", x: 35, y: -20, width: 10, height: 60 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
        built = 0
        node_class = described_class.const_get(:SearchNode)
        allow(node_class).to receive(:new).and_wrap_original do |original, **fields|
          built += 1
          original.call(**fields)
        end

        algorithm.layout(graph)

        expect(built).to be < 40
      end
    end

    context "when the way round needs more than the floored margin on a long edge" do
      # The margin is twice the edge's length (about 500 here), far past the
      # eight-step floor of 80, so the wall's end 160 above the edge is inside.
      it "finds the way round" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 50, height: 50 },
                     { id: "wall", x: 150, y: -150, width: 10, height: 250 },
                     { id: "b", x: 300, y: 0, width: 50, height: 50 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )

        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics).to eq("e" => :found)
      end
    end

    describe "DiagnosticsKey.segment" do
      {
        "a slash" => ["p/e", "p\\/e"],
        "several slashes" => ["a/b/c", "a\\/b\\/c"],
        "a backslash" => ["a\\b", "a\\\\b"],
        "several backslashes" => ["a\\b\\c", "a\\\\b\\\\c"],
        "neither" => ["plain", "plain"],
      }.each do |description, (id, escaped)|
        it "escapes #{description} in an id" do
          expect(described_class.const_get(:DiagnosticsKey).segment(id)).to eq(escaped)
        end
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

      it "wraps the :no_path direct line without duplicating an endpoint" do
        # No ports here, so `departure`/`arrival` (the search endpoints) equal
        # `start_point`/`end_point` exactly -- the shape that turns an
        # unconditional [start] + path + [end] wrap into
        # [start, start, end, end] for the :no_path direct-line fallback.
        expect { algorithm.layout(graph) }.to output(/no_path/).to_stderr

        section = graph.edges.first.sections.first
        points = path_points(section)

        expect(points.each_cons(2).none? { |from, to| from.x == to.x && from.y == to.y }).to be(true)
      end
    end

    context "with an edge that ends on a port" do
      # The port sits on the WEST side, facing AWAY from "b" -- the side
      # facing the target would land on the same point NodeBox#border_toward
      # picks for a plain node-to-node edge, so a fixture routed only
      # through that side cannot tell the port fix from the plain fallback.
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50,
              ports: [{ id: "a_p1", x: 0, y: 25, width: 1, height: 1, side: "WEST" }] },
            { id: "b", x: 200, y: 0, width: 50, height: 50 },
          ],
          edges: [{ id: "e", sources: ["a_p1"], targets: ["b"] }],
        )
      end

      # Keep: guards endpoint_point using a port's own position; it is the only check that a ported edge starts at its port.
      it "starts at the port position, not the node border facing the target" do
        algorithm.layout(graph)

        node = graph.children.first
        port = node.ports.first
        start = graph.edges.first.sections.first.start_point
        expect([start.x, start.y]).to eq([node.x + port.x, node.y + port.y])
      end
    end

    context "with an edge that ends on a port and an obstacle in the way" do
      # Same WEST-side reasoning as above: a port facing the target would
      # route identically whether or not the fix resolves its position.
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [
            { id: "a", x: 0, y: 0, width: 50, height: 50,
              ports: [{ id: "a_p1", x: 0, y: 25, width: 1, height: 1, side: "WEST" }] },
            { id: "wall", x: 100, y: -20, width: 50, height: 90 },
            { id: "b", x: 200, y: 0, width: 50, height: 50 },
          ],
          edges: [{ id: "e", sources: ["a_p1"], targets: ["b"] }],
        )
      end

      it "starts at the port and routes around the obstacle" do
        algorithm.layout(graph)

        node = graph.children.first
        port = node.ports.first
        wall = padded_rect(graph.children.find { |n| n.id == "wall" }, 0)
        # Shrunk 0.5 units in from the node's own bare body on every side.
        # The port sits exactly ON that body's boundary, so the route's
        # very first point always touches the un-shrunk rect -- that is the
        # legitimate case (the route starts there and immediately moves
        # away). Shrinking excludes that boundary touch while still
        # catching any segment that actually travels INTO the body, however
        # far in the path it occurs.
        own_body = padded_rect(node, 0)
        own_interior = {
          x: own_body[:x] + 0.5,
          y: own_body[:y] + 0.5,
          width: own_body[:width] - 1.0,
          height: own_body[:height] - 1.0,
        }
        section = graph.edges.first.sections.first
        points = path_points(section)

        expect(algorithm.routing_diagnostics).to eq("e" => :found)
        expect([section.start_point.x, section.start_point.y]).to eq([node.x + port.x, node.y + port.y])
        expect(points.each_cons(2).select { |from, to| segment_intersects_rect?(from, to, wall) }).to be_empty
        # No leg of the route -- not even the stub leaving the port -- may
        # cross back INTO the port's own owning node, or the route runs
        # straight through the node it started from instead of around the
        # obstacle.
        expect(points.each_cons(2).select { |from, to| segment_intersects_rect?(from, to, own_interior) }).to be_empty
      end
    end

    context "with a grid step below one hundredth of a unit" do
      let(:algorithm) do
        described_class.new("libavoid.stepSize" => 0.001, "libavoid.routingPadding" => 0,
                            "libavoid.maxExpansions" => 100_000)
      end
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0.0, y: 0.0, width: 0.01, height: 0.01 },
                     { id: "wall", x: 0.02, y: -0.01, width: 0.01, height: 0.03 },
                     { id: "b", x: 0.04, y: 0.0, width: 0.01, height: 0.01 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      it "keeps neighbouring grid points apart and finds the detour" do
        algorithm.layout(graph)

        expect(algorithm.routing_diagnostics).to eq("e" => :found)
      end
    end

    context "with a grid step of zero" do
      let(:algorithm) { described_class.new("libavoid.stepSize" => 0) }
      # `wall` blocks the straight route, so only the (empty) grid could go round.
      let(:graph) do
        Elkrb::Graph::Graph.from_hash(
          id: "root",
          children: [{ id: "a", x: 0, y: 0, width: 20, height: 20 },
                     { id: "wall", x: 30, y: -100, width: 10, height: 200 },
                     { id: "b", x: 60, y: 0, width: 20, height: 20 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )
      end

      it "reports :no_path instead of raising" do
        expect { algorithm.layout(graph) }.to output(/no_path/).to_stderr
        expect(algorithm.routing_diagnostics).to eq("e" => :no_path)
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
        # `c` forces a detour. Its row is a grid row, so it lies a whole
        # number of steps from the row the search started on; a 10-unit grid
        # puts it at 6 steps (60 units), which is 1.6 steps of 37.5.
        detour_y = section.bend_points.map(&:y).max
        steps = (detour_y - section.start_point.y) / 37.5

        expect(steps).to be > 0
        expect(steps).to be_within(0.001).of(steps.round)
      end
    end

    describe "reading the numeric options" do
      # Every numeric option goes through one reader: a value the resolver
      # rejects (non-finite, non-numeric) raises ValidationError, anything
      # else is held between zero and 1e9.
      {
        "libavoid.stepSize" => [:step_size,
                                [[-100, 0.0], [-1, 0.0], [1e308, 1e9], ["25", 25.0]]],
        "libavoid.routingPadding" => [:routing_padding,
                                      [[-5, 0.0], [1e308, 1e9], ["25", 25.0]]],
        "libavoid.maxExpansions" => [:max_expansions,
                                     [[-5, 0], [0, 0], [1e308, 1_000_000_000]]],
        "libavoid.segmentPenalty" => [:segment_penalty,
                                      [[-1000, 0.0], [1e308, 1e9], ["25", 25.0]]],
        "libavoid.bendPenalty" => [:bend_penalty,
                                   [[-1000, 0.0], [1e308, 1e9], ["25", 25.0]]],
      }.each do |key, (reader, rows)|
        rows.each do |value, expected|
          it "reads #{key} #{value.inspect} as #{expected}" do
            expect(described_class.new(key => value).send(reader)).to eq(expected)
          end
        end

        [Float::NAN, Float::INFINITY, -Float::INFINITY, "abc"].each do |value|
          it "raises ValidationError for #{key} #{value.inspect}" do
            expect { described_class.new(key => value).send(reader) }
              .to raise_error(Elkrb::ValidationError, /#{Regexp.escape(key)}/)
          end
        end
      end
    end

    context "with a negative libavoid.stepSize" do
      # A source node at x 12 to 62: a negative step would put the clearance
      # point inside it and send the route back through it. The legs may
      # touch a node's border but never enter its interior.
      [-1, -100].each do |step|
        it "reports :no_path like a zero step and leaves both nodes alone for #{step}" do
          graph = Elkrb::Graph::Graph.from_hash(
            id: "root",
            children: [{ id: "a", x: 12, y: 0, width: 50, height: 50 },
                       { id: "wall", x: 100, y: -100, width: 10, height: 250 },
                       { id: "b", x: 200, y: 0, width: 50, height: 50 }],
            edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
          )
          algorithm = described_class.new("libavoid.stepSize" => step)

          expect { algorithm.layout(graph) }.to output(/no_path/).to_stderr

          legs = path_points(graph.edges.first.sections.first).each_cons(2)
          inside = graph.children.values_at(0, 2).flat_map do |node|
            legs.select { |from, to| segment_intersects_rect?(from, to, padded_rect(node, -0.001)) }
          end
          expect(algorithm.routing_diagnostics).to eq("e" => :no_path)
          expect(inside).to be_empty
        end
      end
    end

    context "with a negative routingPadding" do
      [-5, -20].each do |padding|
        it "treats #{padding} as 0 and still avoids the obstacle" do
          graph = Elkrb::Graph::Graph.from_hash(
            id: "root",
            children: [{ id: "a", x: 0, y: 0, width: 50, height: 50 },
                       { id: "c", x: 100, y: -20, width: 50, height: 90 },
                       { id: "b", x: 200, y: 0, width: 50, height: 50 }],
            edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
          )

          described_class.new("libavoid.routingPadding" => padding).layout(graph)

          rect = padded_rect(graph.children[1], 0.0)
          legs = path_points(graph.edges.first.sections.first).each_cons(2)
          expect(legs.select { |from, to| segment_intersects_rect?(from, to, rect) }).to be_empty
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

RSpec.describe "Libavoid edge section integration" do
  let(:algorithm) { Elkrb::Layout::Algorithms::Libavoid.new }

  it "replaces stale non-loop sections with normalized endpoint metadata" do
    stale_sections = [
      Elkrb::Graph::EdgeSection.new(id: "stale_1"),
      Elkrb::Graph::EdgeSection.new(id: "stale_2"),
    ]
    edge = Elkrb::Graph::Edge.new(
      id: "e", sources: ["a"], targets: ["b"],
      sections: stale_sections
    )
    graph = Elkrb::Graph::Graph.new(
      id: "root",
      children: [
        Elkrb::Graph::Node.new(id: "a", x: 0, y: 0,
                               width: 30, height: 30),
        Elkrb::Graph::Node.new(id: "b", x: 120, y: 0,
                               width: 30, height: 30),
      ],
      edges: [edge],
    )

    algorithm.layout(graph)

    expect(edge.sections.length).to eq(1)
    expect(edge.sections.first).to have_attributes(
      id: "e_s0", incoming_shape: "a", outgoing_shape: "b",
    )
    expect(edge.container).to eq("root")
  end

  [
    { edge: "SPLINES", graph: "POLYLINE", bends: 2 },
    { edge: "POLYLINE", graph: "SPLINES", bends: 4 },
  ].each do |row|
    it "lets self-loop #{row[:edge]} override graph #{row[:graph]}" do
      edge = Elkrb::Graph::Edge.new(
        id: "loop", sources: ["a"], targets: ["a"],
        layout_options: { "elk.edgeRouting" => row[:edge] }
      )
      graph = Elkrb::Graph::Graph.new(
        id: "root",
        layout_options: { "elk.edgeRouting" => row[:graph] },
        children: [
          Elkrb::Graph::Node.new(id: "a", x: 0, y: 0,
                                 width: 50, height: 50),
        ],
        edges: [edge],
      )

      algorithm.layout(graph)

      expect(edge.sections.first.bend_points.length).to eq(row[:bends])
    end
  end

  it "includes an unresolved edge in fallback style resolution" do
    edge = Elkrb::Graph::Edge.new(
      id: "e", sources: ["a"], targets: ["ghost"],
      layout_options: { "elk.edgeRouting" => "POLYLINE" }
    )
    graph = Elkrb::Graph::Graph.new(
      id: "root",
      children: [
        Elkrb::Graph::Node.new(id: "a", x: 0, y: 0,
                               width: 50, height: 50),
      ],
      edges: [edge],
    )

    expect(algorithm).to receive(:get_edge_routing_style)
      .with(graph, edge).and_call_original

    algorithm.layout(graph)
  end
end
