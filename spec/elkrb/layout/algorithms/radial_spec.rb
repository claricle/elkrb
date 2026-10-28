# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Radial do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with a simple graph" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "radial" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 40, height: 30),
          Elkrb::Graph::Node.new(id: "node2", width: 40, height: 30),
          Elkrb::Graph::Node.new(id: "node3", width: 40, height: 30),
          Elkrb::Graph::Node.new(id: "node4", width: 40, height: 30),
        ]
        graph.edges = (2..4).map do |index|
          Elkrb::Graph::Edge.new(
            id: "e#{index}",
            sources: ["node1"],
            targets: ["node#{index}"],
          )
        end
      end

      it "arranges nodes in a circular pattern" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
        end

        # Calculate distances from center
        root = graph.children.first
        center_x = root.x + (root.width / 2.0)
        center_y = root.y + (root.height / 2.0)

        distances = graph.children.drop(1).map do |node|
          node_center_x = node.x + (node.width / 2.0)
          node_center_y = node.y + (node.height / 2.0)
          Math.sqrt(
            ((node_center_x - center_x)**2) +
            ((node_center_y - center_y)**2),
          )
        end

        # All nodes should be roughly the same distance from center
        avg_distance = distances.sum / distances.size
        distances.each do |distance|
          expect((distance - avg_distance).abs).to be < 10.0
        end
      end

      it "evenly distributes nodes around the circle" do
        algorithm.layout(graph)

        root = graph.children.first
        center_x = root.x + (root.width / 2.0)
        center_y = root.y + (root.height / 2.0)

        # Calculate angles for each node
        angles = graph.children.drop(1).map do |node|
          node_center_x = node.x + (node.width / 2.0)
          node_center_y = node.y + (node.height / 2.0)
          Math.atan2(node_center_y - center_y, node_center_x - center_x)
        end

        # Sort angles
        sorted_angles = angles.sort

        # Calculate angular spacing
        expected_spacing = (2 * Math::PI) / angles.size

        # Check that nodes are evenly spaced
        (0...(sorted_angles.size - 1)).each do |i|
          spacing = sorted_angles[i + 1] - sorted_angles[i]
          expect((spacing - expected_spacing).abs).to be < 0.2
        end
      end

      it "sets graph dimensions" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0
      end
    end

    context "with a single node" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "radial" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 40, height: 30),
        ]
      end

      it "centers the single node" do
        algorithm.layout(graph)

        node = graph.children.first
        expect(node.x).to be_a(Numeric)
        expect(node.y).to be_a(Numeric)
      end
    end

    context "with many nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "radial" },
        )
      end

      before do
        graph.children = (1..12).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 30,
            height: 20,
          )
        end
      end

      it "arranges all nodes in a circle" do
        algorithm.layout(graph)

        # All nodes should be positioned
        expect(graph.children.all? { |n| n.x.is_a?(Numeric) }).to be true
        expect(graph.children.all? { |n| n.y.is_a?(Numeric) }).to be true

        # Graph should be large enough
        expect(graph.width).to be > 100
        expect(graph.height).to be > 100
      end
    end

    context "with no nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "radial" },
        )
      end

      before do
        graph.children = []
      end

      it "handles empty graph gracefully" do
        algorithm.layout(graph)

        expect(graph.width).to eq(0)
        expect(graph.height).to eq(0)
      end
    end
  end
end

RSpec.describe "Radial edge section integration" do
  it "replaces stale sections with normalized endpoint metadata" do
    graph = {
      "id" => "root",
      "children" => [
        { "id" => "a", "width" => 30, "height" => 30 },
        { "id" => "b", "width" => 30, "height" => 30 },
      ],
      "edges" => [{
        "id" => "e", "sources" => ["a"], "targets" => ["b"],
        "sections" => [
          { "id" => "stale_1" },
          { "id" => "stale_2" },
        ]
      }],
    }

    edge = Elkrb.layout(graph, algorithm: "radial").edges.first

    expect(edge.sections.length).to eq(1)
    expect(edge.sections.first).to have_attributes(
      id: "e_s0", incoming_shape: "a", outgoing_shape: "b",
    )
    expect(edge.container).to eq("root")
  end

  it "keeps a named source port at its origin and the target on its border" do
    input = lambda do |source|
      {
        "id" => "root",
        "children" => [
          {
            "id" => "a", "width" => 30, "height" => 30,
            "ports" => [{ "id" => "a_out", "side" => "NORTH" }]
          },
          { "id" => "b", "width" => 30, "height" => 30 },
          { "id" => "c", "width" => 30, "height" => 30 },
        ],
        "edges" => [{ "id" => "e", "sources" => [source], "targets" => ["b"] }],
      }
    end

    node_edge = Elkrb.layout(input.call("a"), algorithm: "radial").edges.first
    ported = Elkrb.layout(input.call("a_out"), algorithm: "radial")
    port_edge = ported.edges.first
    source = ported.children.find { |node| node.id == "a" }
    port = source.ports.first

    expect([port_edge.sections.first.start_point.x,
            port_edge.sections.first.start_point.y])
      .to eq([source.x + port.x, source.y + port.y])
    expect(port_edge.sections.first.end_point)
      .to eq(node_edge.sections.first.end_point)
    expect(port_edge.sections.first.bend_points).to eq([])
  end
end

RSpec.describe "Radial tree geometry" do
  def star_graph(count, width: 30, height: 30)
    children = (0...count).map do |index|
      { "id" => "n#{index}", "width" => width, "height" => height }
    end
    edges = (1...count).map do |index|
      { "id" => "e#{index}", "sources" => ["n0"],
        "targets" => ["n#{index}"] }
    end
    { "id" => "root", "children" => children, "edges" => edges }
  end

  it "centres the edge-derived root inside a ring" do
    graph = Elkrb.layout(star_graph(5), algorithm: "radial")
    root = graph.children.first

    expect(root.x + (root.width / 2.0)).to be_within(1e-9).of(graph.width / 2.0)
    expect(root.y + (root.height / 2.0))
      .to be_within(1e-9).of(graph.height / 2.0)
  end

  it "grows the ring until eight large nodes do not overlap" do
    graph = Elkrb.layout(star_graph(8, width: 100, height: 50),
                         algorithm: "radial")
    overlaps = graph.children.combination(2).count do |left, right|
      left.x < right.x + right.width && right.x < left.x + left.width &&
        left.y < right.y + right.height && right.y < left.y + left.height
    end

    expect(overlaps).to be_zero
  end

  it "marks centerOnRoot as honoured" do
    expect(Elkrb::Options::Registry.status("elk.radial.centerOnRoot"))
      .to eq(:honoured)
  end
end
