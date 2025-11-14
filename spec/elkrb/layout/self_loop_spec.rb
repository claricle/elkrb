# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Self-loop Support" do
  let(:router_class) do
    Class.new do
      include Elkrb::Layout::EdgeRouter
    end
  end
  let(:router) { router_class.new }

  describe "self-loop detection" do
    it "detects self-loop when source equals target" do
      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n1"],
      )

      expect(router.send(:self_loop?, edge)).to be true
    end

    it "returns false for normal edge" do
      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n2"],
      )

      expect(router.send(:self_loop?, edge)).to be false
    end

    it "handles empty sources" do
      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: [],
        targets: ["n1"],
      )

      expect(router.send(:self_loop?, edge)).to be false
    end

    it "handles empty targets" do
      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: [],
      )

      expect(router.send(:self_loop?, edge)).to be false
    end
  end

  describe "single self-loop routing" do
    let(:node) do
      Elkrb::Graph::Node.new(
        id: "n1",
        x: 100.0,
        y: 100.0,
        width: 80.0,
        height: 60.0,
      )
    end
    let(:edge) do
      Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n1"],
      )
    end
    let(:graph) do
      Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge],
      )
    end

    describe "orthogonal routing" do
      it "creates rectangular self-loop on EAST side" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.selfLoopSide"] = "EAST"

        router.route_edges(graph, nil, "ORTHOGONAL")

        section = edge.sections.first
        expect(section.start_point).to be_a(Elkrb::Geometry::Point)
        expect(section.end_point).to be_a(Elkrb::Geometry::Point)
        expect(section.bend_points.length).to eq(4)

        # Start should be on right side of node
        expect(section.start_point.x).to eq(180.0)
        expect(section.start_point.y).to eq(130.0)
      end

      it "creates rectangular self-loop on WEST side" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.selfLoopSide"] = "WEST"

        router.route_edges(graph, nil, "ORTHOGONAL")

        section = edge.sections.first
        expect(section.bend_points.length).to eq(4)

        # Start should be on left side of node
        expect(section.start_point.x).to eq(100.0)
      end

      it "creates rectangular self-loop on NORTH side" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.selfLoopSide"] = "NORTH"

        router.route_edges(graph, nil, "ORTHOGONAL")

        section = edge.sections.first
        expect(section.bend_points.length).to eq(4)

        # Start should be on top of node
        expect(section.start_point.y).to eq(100.0)
      end

      it "creates rectangular self-loop on SOUTH side" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.selfLoopSide"] = "SOUTH"

        router.route_edges(graph, nil, "ORTHOGONAL")

        section = edge.sections.first
        expect(section.bend_points.length).to eq(4)

        # Start should be on bottom of node
        expect(section.start_point.y).to eq(160.0)
      end

      it "defaults to EAST side when not specified" do
        router.route_edges(graph, nil, "ORTHOGONAL")

        section = edge.sections.first
        expect(section.start_point.x).to eq(180.0)
      end

      it "creates edge section with proper structure" do
        router.route_edges(graph, nil, "ORTHOGONAL")

        expect(edge.sections).not_to be_empty
        section = edge.sections.first
        expect(section.id).to eq("e1_section_0")
        expect(section.start_point).to be_a(Elkrb::Geometry::Point)
        expect(section.end_point).to be_a(Elkrb::Geometry::Point)
        expect(section.bend_points).to be_an(Array)
      end
    end

    describe "spline routing" do
      it "creates curved self-loop with control points" do
        router.route_edges(graph, nil, "SPLINES")

        section = edge.sections.first
        expect(section.bend_points.length).to eq(2)
        expect(section.bend_points[0]).to be_a(Elkrb::Geometry::Point)
        expect(section.bend_points[1]).to be_a(Elkrb::Geometry::Point)
      end

      it "creates spline on EAST side" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.selfLoopSide"] = "EAST"

        router.route_edges(graph, nil, "SPLINES")

        section = edge.sections.first
        control1 = section.bend_points[0]

        # Control point should extend to the right
        expect(control1.x).to be > section.start_point.x
      end

      it "creates spline on WEST side" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.selfLoopSide"] = "WEST"

        router.route_edges(graph, nil, "SPLINES")

        section = edge.sections.first
        control1 = section.bend_points[0]

        # Control point should extend to the left
        expect(control1.x).to be < section.start_point.x
      end

      it "creates spline on NORTH side" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.selfLoopSide"] = "NORTH"

        router.route_edges(graph, nil, "SPLINES")

        section = edge.sections.first
        control1 = section.bend_points[0]

        # Control point should extend upward
        expect(control1.y).to be < section.start_point.y
      end

      it "creates spline on SOUTH side" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.selfLoopSide"] = "SOUTH"

        router.route_edges(graph, nil, "SPLINES")

        section = edge.sections.first
        control1 = section.bend_points[0]

        # Control point should extend downward
        expect(control1.y).to be > section.start_point.y
      end
    end

    describe "polyline routing" do
      it "uses orthogonal routing for polyline" do
        router.route_edges(graph, nil, "POLYLINE")

        section = edge.sections.first
        # Polyline delegates to orthogonal
        expect(section.bend_points.length).to eq(4)
      end
    end
  end

  describe "multiple self-loops on same node" do
    let(:node) do
      Elkrb::Graph::Node.new(
        id: "n1",
        x: 100.0,
        y: 100.0,
        width: 80.0,
        height: 60.0,
      )
    end
    let(:edge1) do
      Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n1"],
      )
    end
    let(:edge2) do
      Elkrb::Graph::Edge.new(
        id: "e2",
        sources: ["n1"],
        targets: ["n1"],
      )
    end
    let(:edge3) do
      Elkrb::Graph::Edge.new(
        id: "e3",
        sources: ["n1"],
        targets: ["n1"],
      )
    end

    it "calculates different loop indices" do
      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge1, edge2, edge3],
      )

      index1 = router.send(:get_self_loop_index, edge1, node, graph)
      index2 = router.send(:get_self_loop_index, edge2, node, graph)
      index3 = router.send(:get_self_loop_index, edge3, node, graph)

      expect(index1).to eq(0)
      expect(index2).to eq(1)
      expect(index3).to eq(2)
    end

    it "applies increasing offsets to multiple loops" do
      offset0 = router.send(:calculate_loop_offset, 0)
      offset1 = router.send(:calculate_loop_offset, 1)
      offset2 = router.send(:calculate_loop_offset, 2)

      expect(offset0).to eq(20.0)
      expect(offset1).to eq(40.0)
      expect(offset2).to eq(60.0)
    end

    it "routes all self-loops with different offsets" do
      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge1, edge2],
      )

      router.route_edges(graph, nil, "SPLINES")

      section1 = edge1.sections.first
      section2 = edge2.sections.first

      # Control points should be at different positions
      control1_x = section1.bend_points[0].x
      control2_x = section2.bend_points[0].x

      expect(control1_x).not_to eq(control2_x)
    end

    it "supports up to 5 self-loops on same node" do
      edges = (1..5).map do |i|
        Elkrb::Graph::Edge.new(
          id: "e#{i}",
          sources: ["n1"],
          targets: ["n1"],
        )
      end

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: edges,
      )

      router.route_edges(graph, nil, "ORTHOGONAL")

      edges.each do |edge|
        expect(edge.sections).not_to be_empty
        expect(edge.sections.first.bend_points).not_to be_empty
      end
    end

    it "maintains consistent loop index order" do
      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge1, edge2, edge3],
      )

      # Get indices multiple times
      index1a = router.send(:get_self_loop_index, edge1, node, graph)
      index2a = router.send(:get_self_loop_index, edge2, node, graph)
      index1b = router.send(:get_self_loop_index, edge1, node, graph)

      expect(index1a).to eq(index1b)
      expect(index1a).to be < index2a
    end

    it "handles mixed self-loops and normal edges" do
      node2 = Elkrb::Graph::Node.new(
        id: "n2",
        x: 200.0,
        y: 100.0,
        width: 80.0,
        height: 60.0,
      )
      normal_edge = Elkrb::Graph::Edge.new(
        id: "e_normal",
        sources: ["n1"],
        targets: ["n2"],
      )

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node, node2],
        edges: [edge1, normal_edge, edge2],
      )

      router.route_edges(graph, nil, "ORTHOGONAL")

      # Self-loops should be routed
      expect(edge1.sections).not_to be_empty
      expect(edge2.sections).not_to be_empty

      # Normal edge should also be routed
      expect(normal_edge.sections).not_to be_empty

      # Self-loops should have bend points
      expect(edge1.sections.first.bend_points.length).to be > 0
      # Normal edge might not have bend points
    end
  end

  describe "self-loop with ports" do
    let(:node) do
      Elkrb::Graph::Node.new(
        id: "n1",
        x: 100.0,
        y: 100.0,
        width: 80.0,
        height: 60.0,
      )
    end

    it "detects port usage in self-loop" do
      port1 = Elkrb::Graph::Port.new(id: "p1", x: 80.0, y: 20.0, side: "EAST")
      port2 = Elkrb::Graph::Port.new(id: "p2", x: 80.0, y: 40.0, side: "EAST")
      node.ports = [port1, port2]

      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["p1"],
        targets: ["p2"],
      )

      result = router.send(:edge_uses_ports_for_self_loop?, edge, node)
      expect(result).to be true
    end

    it "routes self-loop between two ports" do
      port1 = Elkrb::Graph::Port.new(id: "p1", x: 80.0, y: 20.0, side: "EAST")
      port2 = Elkrb::Graph::Port.new(id: "p2", x: 80.0, y: 40.0, side: "EAST")
      node.ports = [port1, port2]

      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["p1"],
        targets: ["p2"],
      )

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge],
      )

      router.route_edges(graph, nil, "ORTHOGONAL")

      section = edge.sections.first
      expect(section.start_point.x).to eq(180.0) # node.x + port.x
      expect(section.start_point.y).to eq(120.0) # node.y + port.y
      expect(section.end_point.x).to eq(180.0)
      expect(section.end_point.y).to eq(140.0)
    end

    it "routes spline self-loop between ports on same side" do
      port1 = Elkrb::Graph::Port.new(id: "p1", x: 80.0, y: 20.0, side: "EAST")
      port2 = Elkrb::Graph::Port.new(id: "p2", x: 80.0, y: 40.0, side: "EAST")
      node.ports = [port1, port2]

      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["p1"],
        targets: ["p2"],
      )

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge],
      )

      router.route_edges(graph, nil, "SPLINES")

      section = edge.sections.first
      expect(section.bend_points.length).to eq(2)
      # Verify proper spline control points exist
      expect(section.bend_points[0]).to be_a(Elkrb::Geometry::Point)
      expect(section.bend_points[1]).to be_a(Elkrb::Geometry::Point)
    end

    it "handles ports on different sides" do
      port1 = Elkrb::Graph::Port.new(id: "p1", x: 80.0, y: 30.0, side: "EAST")
      port2 = Elkrb::Graph::Port.new(id: "p2", x: 0.0, y: 30.0, side: "WEST")
      node.ports = [port1, port2]

      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["p1"],
        targets: ["p2"],
      )

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge],
      )

      router.route_edges(graph, nil, "ORTHOGONAL")

      section = edge.sections.first
      expect(section.bend_points).not_to be_empty
    end
  end

  describe "self-loop side selection" do
    let(:node) do
      Elkrb::Graph::Node.new(
        id: "n1",
        x: 100.0,
        y: 100.0,
        width: 80.0,
        height: 60.0,
      )
    end
    let(:edge) { Elkrb::Graph::Edge.new(id: "e1") }

    it "uses edge layout option for side" do
      edge.layout_options = Elkrb::Graph::LayoutOptions.new
      edge.layout_options["elk.selfLoopSide"] = "WEST"

      side = router.send(:get_self_loop_side, edge, node)
      expect(side).to eq("WEST")
    end

    it "uses shorthand option for side" do
      edge.layout_options = Elkrb::Graph::LayoutOptions.new
      edge.layout_options["selfLoopSide"] = "NORTH"

      side = router.send(:get_self_loop_side, edge, node)
      expect(side).to eq("NORTH")
    end

    it "uses node layout option when edge option not set" do
      node.layout_options = Elkrb::Graph::LayoutOptions.new
      node.layout_options["elk.selfLoopSide"] = "SOUTH"

      side = router.send(:get_self_loop_side, edge, node)
      expect(side).to eq("SOUTH")
    end

    it "defaults to EAST when no options set" do
      side = router.send(:get_self_loop_side, edge, node)
      expect(side).to eq("EAST")
    end
  end

  describe "self-loop offset calculation" do
    it "calculates base offset for first loop" do
      offset = router.send(:calculate_loop_offset, 0)
      expect(offset).to eq(20.0)
    end

    it "calculates increasing offset for subsequent loops" do
      offset1 = router.send(:calculate_loop_offset, 1)
      offset2 = router.send(:calculate_loop_offset, 2)
      offset3 = router.send(:calculate_loop_offset, 3)

      expect(offset1).to eq(40.0)
      expect(offset2).to eq(60.0)
      expect(offset3).to eq(80.0)
    end

    it "uses offset in routing calculations" do
      node = Elkrb::Graph::Node.new(
        id: "n1",
        x: 0.0,
        y: 0.0,
        width: 100.0,
        height: 100.0,
      )
      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n1"],
      )

      section = Elkrb::Graph::EdgeSection.new(id: "s1")

      # Route with different indices
      router.send(:route_orthogonal_self_loop, section, edge, node, 0)
      bend_x_0 = section.bend_points[0].x

      section2 = Elkrb::Graph::EdgeSection.new(id: "s2")
      router.send(:route_orthogonal_self_loop, section2, edge, node, 1)
      bend_x_1 = section2.bend_points[0].x

      # Second loop should extend further
      expect(bend_x_1).to be > bend_x_0
    end
  end

  describe "integration with algorithms" do
    it "works with BaseAlgorithm edge routing" do
      algorithm = Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
        def layout_flat(graph, _options = {})
          # Just position the node
          graph.children.first.x = 0.0
          graph.children.first.y = 0.0
          graph.children.first.width = 100.0
          graph.children.first.height = 100.0
          graph
        end
      end.new

      node = Elkrb::Graph::Node.new(id: "n1")
      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n1"],
      )

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge],
      )

      result = algorithm.layout(graph)

      expect(result.edges.first.sections).not_to be_empty
      expect(result.edges.first.sections.first.bend_points).not_to be_empty
    end

    it "routes self-loops with spline routing option" do
      algorithm = Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
        def layout_flat(graph, _options = {})
          graph.children.first.x = 0.0
          graph.children.first.y = 0.0
          graph.children.first.width = 100.0
          graph.children.first.height = 100.0
          graph
        end
      end.new

      node = Elkrb::Graph::Node.new(id: "n1")
      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n1"],
      )

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [edge],
        layout_options: Elkrb::Graph::LayoutOptions.new(
          edge_routing: "SPLINES",
        ),
      )

      result = algorithm.layout(graph)

      section = result.edges.first.sections.first
      expect(section.bend_points.length).to eq(2)
    end

    it "handles hierarchical graphs with self-loops" do
      algorithm = Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
        def layout_flat(graph, _options = {})
          graph.children&.each do |node|
            node.x = 0.0
            node.y = 0.0
            node.width = 100.0
            node.height = 100.0
          end
          graph
        end
      end.new

      child_node = Elkrb::Graph::Node.new(
        id: "n1",
        x: 0.0,
        y: 0.0,
        width: 80.0,
        height: 60.0,
      )
      child_edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n1"],
      )

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [child_node],
        edges: [child_edge],
      )

      result = algorithm.layout(graph)

      # Self-loop should be routed
      expect(result.edges.first.sections).not_to be_empty
      expect(result.edges.first.sections.first.bend_points).not_to be_empty
    end

    it "supports all routing styles for self-loops" do
      node = Elkrb::Graph::Node.new(
        id: "n1",
        x: 0.0,
        y: 0.0,
        width: 100.0,
        height: 100.0,
      )
      edge = Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n1"],
      )

      %w[ORTHOGONAL SPLINES POLYLINE].each do |style|
        graph = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node],
          edges: [edge.dup],
        )

        router.route_edges(graph, nil, style)

        expect(graph.edges.first.sections).not_to be_empty
        expect(graph.edges.first.sections.first.start_point).to be_a(
          Elkrb::Geometry::Point,
        )
      end
    end
  end
end
