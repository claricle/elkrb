# frozen_string_literal: true

require "spec_helper"

RSpec.describe "have_edges_on_node_borders" do
  def graph_with_section(start_point:, end_point:, ports: [])
    source = Elkrb::Graph::Node.new(
      id: "source", x: 10, y: 20, width: 40, height: 30,
      ports: ports
    )
    target = Elkrb::Graph::Node.new(
      id: "target", x: 100, y: 20, width: 40, height: 30,
    )
    edge = Elkrb::Graph::Edge.new(
      id: "edge",
      sources: [ports.empty? ? "source" : ports.first.id],
      targets: ["target"],
      sections: [
        Elkrb::Graph::EdgeSection.new(
          id: "edge_s0",
          start_point: start_point,
          end_point: end_point,
        ),
      ],
    )
    Elkrb::Graph::Graph.new(
      id: "root", children: [source, target], edges: [edge],
    )
  end

  def point(x_coordinate, y_coordinate)
    Elkrb::Geometry::Point.new(x: x_coordinate, y: y_coordinate)
  end

  it "accepts section endpoints on their node borders" do
    graph = graph_with_section(
      start_point: point(50, 35), end_point: point(100, 35),
    )

    expect(graph).to have_edges_on_node_borders
  end

  it "rejects a section endpoint inside its node" do
    graph = graph_with_section(
      start_point: point(30, 35), end_point: point(100, 35),
    )

    expect(graph).not_to have_edges_on_node_borders
  end

  it "excludes port-carrying edges until port placement lands" do
    port = Elkrb::Graph::Port.new(id: "source_port", x: 20, y: 15)
    graph = graph_with_section(
      start_point: point(30, 35), end_point: point(100, 35), ports: [port],
    )

    expect(graph).to have_edges_on_node_borders
  end

  it "does not let a nested port shadow a node endpoint at this level" do
    graph = graph_with_section(
      start_point: point(30, 35), end_point: point(100, 35),
    )
    nested_port = Elkrb::Graph::Port.new(id: "source")
    nested_node = Elkrb::Graph::Node.new(id: "nested", ports: [nested_port])
    compound = Elkrb::Graph::Node.new(id: "compound", children: [nested_node])
    graph.children << compound

    expect(graph).not_to have_edges_on_node_borders
  end

  it "checks nested endpoints in their owner's coordinate frame" do
    graph = graph_with_section(
      start_point: point(30, 35), end_point: point(100, 35),
    )
    source = graph.children.shift
    source.x = 10
    source.y = 5
    compound = Elkrb::Graph::Node.new(
      id: "compound", x: 20, y: 15, children: [source],
    )
    graph.children.unshift(compound)
    graph.edges.first.sections.first.start_point = point(70, 35)

    expect(graph).to have_edges_on_node_borders
  end
end
