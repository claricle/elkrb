# frozen_string_literal: true

require "spec_helper"

RSpec.describe "have_no_edges_through_nodes" do
  def graph_with_route(bend_points, algorithm: nil)
    nodes = %w[source obstacle target].each_with_index.map do |id, index|
      Elkrb::Graph::Node.new(
        id: id, x: index * 100, y: 0, width: 40, height: 40,
      )
    end
    section = Elkrb::Graph::EdgeSection.new(
      id: "edge_s0",
      start_point: Elkrb::Geometry::Point.new(x: 40, y: 20),
      bend_points: bend_points,
      end_point: Elkrb::Geometry::Point.new(x: 200, y: 20),
    )
    edge = Elkrb::Graph::Edge.new(
      id: "edge", sources: ["source"], targets: ["target"],
      sections: [section]
    )
    options = algorithm ? { "elk.algorithm" => algorithm } : nil
    Elkrb::Graph::Graph.new(
      id: "root", children: nodes, edges: [edge], layout_options: options,
    )
  end

  it "rejects a section that enters a non-endpoint node" do
    expect(graph_with_route([])).not_to have_no_edges_through_nodes
  end

  it "accepts a section routed around a non-endpoint node" do
    bends = [
      Elkrb::Geometry::Point.new(x: 80, y: 60),
      Elkrb::Geometry::Point.new(x: 180, y: 60),
    ]

    expect(graph_with_route(bends)).to have_no_edges_through_nodes
  end

  it "leaves non-layered routing to that algorithm's contract" do
    graph = graph_with_route([], algorithm: "radial")

    expect(graph).to have_no_edges_through_nodes
  end
end
