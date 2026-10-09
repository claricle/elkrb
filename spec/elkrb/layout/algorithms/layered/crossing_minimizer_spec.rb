# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::CrossingMinimizer do
  def graph_with_tied_targets
    source = Elkrb::Graph::Node.new(id: "source")
    b = Elkrb::Graph::Node.new(id: "b")
    a = Elkrb::Graph::Node.new(id: "a")
    graph = Elkrb::Graph::Graph.new(
      id: "root",
      children: [source, b, a],
      edges: [
        Elkrb::Graph::Edge.new(id: "sb", sources: ["source"], targets: ["b"]),
        Elkrb::Graph::Edge.new(id: "sa", sources: ["source"], targets: ["a"]),
      ],
    )
    [graph, [[source], [b, a]]]
  end

  def minimize(graph, layers, options = {})
    described_class.new(
      graph,
      layers,
      Elkrb::Layout::NodeIndex.build(graph),
      Elkrb::Options::Resolver.new(options),
    ).minimize
  end

  it "breaks barycenter ties by node id by default" do
    graph, layers = graph_with_tied_targets

    expect(minimize(graph, layers).last.map(&:id)).to eq(%w[a b])
  end

  it "breaks barycenter ties by input order for NODES_AND_EDGES" do
    graph, layers = graph_with_tied_targets

    result = minimize(
      graph,
      layers,
      "elk.layered.considerModelOrder.strategy" => "NODES_AND_EDGES",
    )

    expect(result.last.map(&:id)).to eq(%w[b a])
  end

  it "uses a port endpoint as its owning node's neighbour" do
    source = Elkrb::Graph::Node.new(
      id: "source", ports: [Elkrb::Graph::Port.new(id: "source_port")],
    )
    other = Elkrb::Graph::Node.new(id: "other")
    b = Elkrb::Graph::Node.new(id: "b")
    a = Elkrb::Graph::Node.new(id: "a")
    graph = Elkrb::Graph::Graph.new(
      id: "root", children: [source, other, b, a],
      edges: [
        Elkrb::Graph::Edge.new(
          id: "port_a", sources: ["source_port"], targets: ["a"],
        ),
        Elkrb::Graph::Edge.new(
          id: "other_b", sources: ["other"], targets: ["b"],
        ),
      ]
    )

    result = minimize(graph, [[source, other], [b, a]])

    expect(result.last.map(&:id)).to eq(%w[a b])
  end
end
