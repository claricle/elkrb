# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::EdgeRouter do
  let(:router_class) do
    Class.new do
      include Elkrb::Layout::EdgeRouter
    end
  end
  let(:router) { router_class.new }

  describe "#route_edges" do
    it "routes all edges in a graph" do
      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [
          Elkrb::Graph::Node.new(
            id: "n1",
            x: 0.0,
            y: 0.0,
            width: 50.0,
            height: 50.0,
          ),
          Elkrb::Graph::Node.new(
            id: "n2",
            x: 100.0,
            y: 0.0,
            width: 50.0,
            height: 50.0,
          ),
        ],
        edges: [
          Elkrb::Graph::Edge.new(
            id: "e1",
            sources: ["n1"],
            targets: ["n2"],
          ),
        ],
      )

      router.route_edges(graph)

      edge = graph.edges.first
      expect(edge.sections).not_to be_empty
      expect(edge.sections.first.start_point).to be_a(
        Elkrb::Geometry::Point,
      )
      expect(edge.sections.first.end_point).to be_a(Elkrb::Geometry::Point)
    end

    it "handles graphs without edges" do
      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [
          Elkrb::Graph::Node.new(id: "n1", x: 0.0, y: 0.0),
        ],
      )

      expect { router.route_edges(graph) }.not_to raise_error
    end
  end

  describe "#route_edge" do
    let(:node1) do
      Elkrb::Graph::Node.new(
        id: "n1",
        x: 0.0,
        y: 0.0,
        width: 50.0,
        height: 50.0,
      )
    end
    let(:node2) do
      Elkrb::Graph::Node.new(
        id: "n2",
        x: 100.0,
        y: 0.0,
        width: 50.0,
        height: 50.0,
      )
    end
    let(:edge) do
      Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n2"],
      )
    end
    let(:node_map) { { "n1" => node1, "n2" => node2 } }
    let(:graph) { Elkrb::Graph::Graph.new(id: "g1") }

    it "creates edge section for node-to-node routing" do
      router.route_edge(edge, node_map, graph)

      expect(edge.sections).not_to be_empty
      section = edge.sections.first
      expect(section.id).to eq("e1_section_0")
      expect(section.start_point.x).to eq(25.0) # Center of n1
      expect(section.start_point.y).to eq(25.0)
      expect(section.end_point.x).to eq(125.0) # Center of n2
      expect(section.end_point.y).to eq(25.0)
    end

    it "routes with ports when available" do
      node1.ports = [
        Elkrb::Graph::Port.new(id: "p1", x: 50.0, y: 25.0),
      ]
      node2.ports = [
        Elkrb::Graph::Port.new(id: "p2", x: 0.0, y: 25.0),
      ]
      edge.sources = ["p1"]
      edge.targets = ["p2"]

      router.route_edge(edge, node_map, graph)

      section = edge.sections.first
      # Port positions are relative to node positions
      expect(section.start_point.x).to eq(50.0) # node1.x + port.x
      expect(section.start_point.y).to eq(25.0) # node1.y + port.y
      expect(section.end_point.x).to eq(100.0) # node2.x + port.x
      expect(section.end_point.y).to eq(25.0) # node2.y + port.y
    end

    it "handles missing nodes gracefully" do
      empty_map = {}
      expect { router.route_edge(edge, empty_map, graph) }.not_to raise_error
      expect(edge.sections).to be_nil
    end

    it "adds orthogonal bend points when configured" do
      edge.layout_options = Elkrb::Graph::LayoutOptions.new
      edge.layout_options["edge.routing"] = "orthogonal"

      router.route_edge(edge, node_map, graph)

      section = edge.sections.first
      expect(section.bend_points.length).to eq(2)
      # Mid-point x coordinate
      mid_x = (25.0 + 125.0) / 2.0
      expect(section.bend_points[0].x).to eq(mid_x)
      expect(section.bend_points[0].y).to eq(25.0)
      expect(section.bend_points[1].x).to eq(mid_x)
      expect(section.bend_points[1].y).to eq(25.0)
    end
  end

  describe "EdgeSection" do
    let(:section) do
      Elkrb::Graph::EdgeSection.new(
        id: "s1",
        start_point: Elkrb::Geometry::Point.new(x: 0.0, y: 0.0),
        end_point: Elkrb::Geometry::Point.new(x: 100.0, y: 0.0),
      )
    end

    describe "#add_bend_point" do
      it "adds a bend point" do
        section.add_bend_point(50.0, 25.0)

        expect(section.bend_points.length).to eq(1)
        expect(section.bend_points.first.x).to eq(50.0)
        expect(section.bend_points.first.y).to eq(25.0)
      end

      it "adds multiple bend points" do
        section.add_bend_point(25.0, 10.0)
        section.add_bend_point(75.0, 10.0)

        expect(section.bend_points.length).to eq(2)
      end
    end

    describe "#length" do
      it "calculates straight line length" do
        expect(section.length).to eq(100.0)
      end

      it "calculates length with bend points" do
        section.add_bend_point(50.0, 50.0)

        # Length: (0,0) -> (50,50) -> (100,0)
        # sqrt(50^2 + 50^2) + sqrt(50^2 + 50^2)
        expected = Math.sqrt(5000) * 2
        expect(section.length).to be_within(0.01).of(expected)
      end

      it "handles missing points" do
        empty_section = Elkrb::Graph::EdgeSection.new(id: "s2")
        expect(empty_section.length).to eq(0.0)
      end

      it "calculates complex path length" do
        section.add_bend_point(30.0, 20.0)
        section.add_bend_point(70.0, 20.0)

        # (0,0) -> (30,20) -> (70,20) -> (100,0)
        len1 = Math.sqrt((30 * 30) + (20 * 20))
        len2 = 40.0 # Horizontal
        len3 = Math.sqrt((30 * 30) + (20 * 20))
        expected = len1 + len2 + len3

        expect(section.length).to be_within(0.01).of(expected)
      end
    end
  end

  describe "integration with algorithms" do
    it "allows algorithms to use edge routing" do
      algorithm = Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
        def layout(graph)
          # Position nodes
          graph.children&.each_with_index do |node, i|
            node.x = i * 100.0
            node.y = 0.0
            node.width = 50.0
            node.height = 50.0
          end

          # Route edges using inherited method
          route_edges(graph)

          graph
        end
      end.new

      graph = Elkrb::Graph::Graph.new(
        id: "g1",
        children: [
          Elkrb::Graph::Node.new(id: "n1"),
          Elkrb::Graph::Node.new(id: "n2"),
        ],
        edges: [
          Elkrb::Graph::Edge.new(
            id: "e1",
            sources: ["n1"],
            targets: ["n2"],
          ),
        ],
      )

      result = algorithm.layout(graph)

      expect(result.edges.first.sections).not_to be_empty
      section = result.edges.first.sections.first
      expect(section.start_point).to be_a(Elkrb::Geometry::Point)
      expect(section.end_point).to be_a(Elkrb::Geometry::Point)
    end
  end

  describe "spline routing" do
    let(:node1) do
      Elkrb::Graph::Node.new(
        id: "n1",
        x: 0.0,
        y: 50.0,
        width: 50.0,
        height: 50.0,
      )
    end
    let(:node2) do
      Elkrb::Graph::Node.new(
        id: "n2",
        x: 200.0,
        y: 50.0,
        width: 50.0,
        height: 50.0,
      )
    end
    let(:edge) do
      Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n2"],
      )
    end
    let(:node_map) { { "n1" => node1, "n2" => node2 } }

    describe "#route_spline_edge" do
      let(:graph) { Elkrb::Graph::Graph.new(id: "g1") }

      it "creates edge section with control points" do
        router.send(:route_spline_edge, edge, node_map, graph)

        expect(edge.sections).not_to be_empty
        section = edge.sections.first
        expect(section.start_point).to be_a(Elkrb::Geometry::Point)
        expect(section.end_point).to be_a(Elkrb::Geometry::Point)
        expect(section.bend_points).not_to be_empty
        expect(section.bend_points.length).to eq(2)
      end

      it "uses node centers for routing" do
        router.send(:route_spline_edge, edge, node_map, graph)

        section = edge.sections.first
        expect(section.start_point.x).to eq(25.0) # Center of n1
        expect(section.start_point.y).to eq(75.0)
        expect(section.end_point.x).to eq(225.0) # Center of n2
        expect(section.end_point.y).to eq(75.0)
      end

      it "creates Bezier control points" do
        router.send(:route_spline_edge, edge, node_map, graph)

        section = edge.sections.first
        control1 = section.bend_points[0]
        control2 = section.bend_points[1]

        expect(control1).to be_a(Elkrb::Geometry::Point)
        expect(control2).to be_a(Elkrb::Geometry::Point)
      end

      it "routes with ports when available" do
        node1.ports = [
          Elkrb::Graph::Port.new(id: "p1", x: 50.0, y: 25.0),
        ]
        node2.ports = [
          Elkrb::Graph::Port.new(id: "p2", x: 0.0, y: 25.0),
        ]
        edge.sources = ["p1"]
        edge.targets = ["p2"]

        router.send(:route_spline_edge, edge, node_map, graph)

        section = edge.sections.first
        expect(section.start_point.x).to eq(50.0)
        expect(section.start_point.y).to eq(75.0)
        expect(section.end_point.x).to eq(200.0)
        expect(section.end_point.y).to eq(75.0)
        expect(section.bend_points.length).to eq(2)
      end

      it "respects curvature setting" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.spline.curvature"] = 0.8

        router.send(:route_spline_edge, edge, node_map, graph)

        section = edge.sections.first
        expect(section.bend_points.length).to eq(2)
      end
    end

    describe "#route_edges with routing styles" do
      it "uses spline routing when configured" do
        graph = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node1, node2],
          edges: [edge],
          layout_options: Elkrb::Graph::LayoutOptions.new(
            edge_routing: "SPLINES",
          ),
        )

        router.route_edges(graph, nil, "SPLINES")

        section = edge.sections.first
        expect(section.bend_points).not_to be_empty
        expect(section.bend_points.length).to eq(2)
      end

      it "uses orthogonal routing by default" do
        graph = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node1, node2],
          edges: [edge],
        )
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["edge.routing"] = "orthogonal"

        router.route_edges(graph)

        section = edge.sections.first
        # Orthogonal routing creates 2 bend points
        expect(section.bend_points.length).to eq(2)
      end

      it "uses polyline routing when configured" do
        graph = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node1, node2],
          edges: [edge],
        )

        router.route_edges(graph, nil, "POLYLINE")

        section = edge.sections.first
        expect(section.start_point).to be_a(Elkrb::Geometry::Point)
        expect(section.end_point).to be_a(Elkrb::Geometry::Point)
      end
    end

    describe "#get_routing_style" do
      it "returns ORTHOGONAL as default" do
        graph = Elkrb::Graph::Graph.new(id: "g1")
        style = router.send(:get_routing_style, graph)
        expect(style).to eq("ORTHOGONAL")
      end

      it "reads from elk.edgeRouting option" do
        graph = Elkrb::Graph::Graph.new(
          id: "g1",
          layout_options: Elkrb::Graph::LayoutOptions.new,
        )
        graph.layout_options["elk.edgeRouting"] = "SPLINES"

        style = router.send(:get_routing_style, graph)
        expect(style).to eq("SPLINES")
      end

      it "reads from edgeRouting option" do
        graph = Elkrb::Graph::Graph.new(
          id: "g1",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            edge_routing: "POLYLINE",
          ),
        )

        style = router.send(:get_routing_style, graph)
        expect(style).to eq("POLYLINE")
      end

      it "converts to uppercase" do
        graph = Elkrb::Graph::Graph.new(
          id: "g1",
          layout_options: Elkrb::Graph::LayoutOptions.new,
        )
        graph.layout_options["elk.edgeRouting"] = "splines"

        style = router.send(:get_routing_style, graph)
        expect(style).to eq("SPLINES")
      end
    end

    describe "#calculate_spline_controls" do
      let(:start_point) { Elkrb::Geometry::Point.new(x: 0.0, y: 0.0) }
      let(:end_point) { Elkrb::Geometry::Point.new(x: 100.0, y: 0.0) }

      it "calculates horizontal control points by default" do
        controls = router.send(
          :calculate_spline_controls,
          start_point,
          end_point,
          0.5,
          edge,
        )

        expect(controls.length).to eq(2)
        expect(controls[0]).to be_a(Elkrb::Geometry::Point)
        expect(controls[1]).to be_a(Elkrb::Geometry::Point)
      end

      it "uses direction from edge options" do
        edge.layout_options = Elkrb::Graph::LayoutOptions.new
        edge.layout_options["elk.direction"] = "VERTICAL"

        controls = router.send(
          :calculate_spline_controls,
          start_point,
          end_point,
          0.5,
          edge,
        )

        expect(controls.length).to eq(2)
      end
    end
  end

  describe "self-loop handling" do
    let(:node) do
      Elkrb::Graph::Node.new(
        id: "n1",
        x: 50.0,
        y: 50.0,
        width: 100.0,
        height: 80.0,
      )
    end
    let(:self_loop_edge) do
      Elkrb::Graph::Edge.new(
        id: "e_self",
        sources: ["n1"],
        targets: ["n1"],
      )
    end
    let(:graph) do
      Elkrb::Graph::Graph.new(
        id: "g1",
        children: [node],
        edges: [self_loop_edge],
      )
    end

    describe "#self_loop?" do
      it "identifies self-loop edges" do
        expect(router.send(:self_loop?, self_loop_edge)).to be true
      end

      it "identifies non-self-loop edges" do
        normal_edge = Elkrb::Graph::Edge.new(
          id: "e1",
          sources: ["n1"],
          targets: ["n2"],
        )
        expect(router.send(:self_loop?, normal_edge)).to be false
      end

      it "handles nil sources/targets" do
        edge = Elkrb::Graph::Edge.new(id: "e1")
        expect(router.send(:self_loop?, edge)).to be false
      end

      it "handles port IDs as self-loop" do
        edge = Elkrb::Graph::Edge.new(
          id: "e1",
          sources: ["p1"],
          targets: ["p1"],
        )
        expect(router.send(:self_loop?, edge)).to be true
      end
    end

    describe "self-loop routing" do
      it "routes self-loop with orthogonal style" do
        router.route_edges(graph, nil, "ORTHOGONAL")

        expect(self_loop_edge.sections).not_to be_empty
        section = self_loop_edge.sections.first
        expect(section.bend_points.length).to be > 0
      end

      it "routes self-loop with splines style" do
        router.route_edges(graph, nil, "SPLINES")

        expect(self_loop_edge.sections).not_to be_empty
        section = self_loop_edge.sections.first
        expect(section.bend_points.length).to eq(2)
      end

      it "creates proper start and end points" do
        router.route_edges(graph, nil, "ORTHOGONAL")

        section = self_loop_edge.sections.first
        expect(section.start_point).to be_a(Elkrb::Geometry::Point)
        expect(section.end_point).to be_a(Elkrb::Geometry::Point)
        # End point should be slightly offset from start
        expect(section.end_point.y).not_to eq(section.start_point.y)
      end

      it "handles missing node gracefully" do
        edge = Elkrb::Graph::Edge.new(
          id: "e1",
          sources: ["missing"],
          targets: ["missing"],
        )
        graph_with_missing = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node],
          edges: [edge],
        )

        expect { router.route_edges(graph_with_missing) }.not_to raise_error
      end
    end

    describe "mixed edges" do
      let(:node2) do
        Elkrb::Graph::Node.new(
          id: "n2",
          x: 200.0,
          y: 50.0,
          width: 100.0,
          height: 80.0,
        )
      end
      let(:normal_edge) do
        Elkrb::Graph::Edge.new(
          id: "e_normal",
          sources: ["n1"],
          targets: ["n2"],
        )
      end

      it "routes both self-loops and normal edges" do
        mixed_graph = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node, node2],
          edges: [self_loop_edge, normal_edge],
        )

        router.route_edges(mixed_graph)

        expect(self_loop_edge.sections).not_to be_empty
        expect(normal_edge.sections).not_to be_empty
      end

      it "distinguishes self-loop routing from normal routing" do
        mixed_graph = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node, node2],
          edges: [self_loop_edge, normal_edge],
        )

        router.route_edges(mixed_graph, nil, "ORTHOGONAL")

        # Self-loop should have 4 bend points (rectangular)
        expect(self_loop_edge.sections.first.bend_points.length).to eq(4)

        # Normal edge should have 2 bend points (orthogonal)
        normal_edge.layout_options = Elkrb::Graph::LayoutOptions.new
        normal_edge.layout_options["edge.routing"] = "orthogonal"
        router.route_edge(normal_edge, { "n1" => node, "n2" => node2 },
                          mixed_graph)
        expect(normal_edge.sections.first.bend_points.length).to eq(2)
      end

      it "routes multiple self-loops separately from normal edges" do
        self_loop_2 = Elkrb::Graph::Edge.new(
          id: "e_self2",
          sources: ["n1"],
          targets: ["n1"],
        )

        mixed_graph = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node, node2],
          edges: [self_loop_edge, self_loop_2, normal_edge],
        )

        router.route_edges(mixed_graph, nil, "SPLINES")

        expect(self_loop_edge.sections.first.bend_points).not_to be_empty
        expect(self_loop_2.sections.first.bend_points).not_to be_empty
        expect(normal_edge.sections.first.bend_points).not_to be_empty

        # Self-loops should have different control points
        control1 = self_loop_edge.sections.first.bend_points[0]
        control2 = self_loop_2.sections.first.bend_points[0]
        expect(control1.x).not_to eq(control2.x)
      end

      it "preserves normal edge routing behavior" do
        mixed_graph = Elkrb::Graph::Graph.new(
          id: "g1",
          children: [node, node2],
          edges: [self_loop_edge, normal_edge],
        )

        router.route_edges(mixed_graph)

        # Normal edge should connect centers
        normal_section = normal_edge.sections.first
        expect(normal_section.start_point.x).to eq(100.0) # node1 center x
        expect(normal_section.end_point.x).to eq(250.0) # node2 center x
      end
    end
  end
end
