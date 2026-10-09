# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::CrossingMinimizer do
  def graph_with_tied_targets
    # Both edges leave one port: with a port each, their order would decide
    # the targets' order and the barycenters would no longer tie.
    source = Elkrb::Graph::Node.new(
      id: "source", ports: [Elkrb::Graph::Port.new(id: "source_port")],
    )
    b = Elkrb::Graph::Node.new(id: "b")
    a = Elkrb::Graph::Node.new(id: "a")
    graph = Elkrb::Graph::Graph.new(
      id: "root",
      children: [source, b, a],
      edges: [
        Elkrb::Graph::Edge.new(
          id: "sb", sources: ["source_port"], targets: ["b"],
        ),
        Elkrb::Graph::Edge.new(
          id: "sa", sources: ["source_port"], targets: ["a"],
        ),
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

  describe "port order under NODES_AND_EDGES" do
    let(:model_order) do
      { "elk.layered.considerModelOrder.strategy" => "NODES_AND_EDGES" }
    end

    it "orders fan-in WEST ports by the input order of the sources" do
      _layers, order = minimized_ports(
        ids: %w[d b c], edges: [%w[b d], %w[c d]],
        layers: [%w[c b], %w[d]], options: model_order
      )

      expect(port_targets(order, "d", :west)).to eq([%w[b], %w[c]])
    end

    it "puts the last-declared source first without model order" do
      _layers, order = minimized_ports(
        ids: %w[d b c], edges: [%w[b d], %w[c d]], layers: [%w[b c], %w[d]],
      )

      expect(port_targets(order, "d", :west)).to eq([%w[c], %w[b]])
    end

    it "keeps EAST ports in sweep order, not input order" do
      _layers, order = minimized_ports(
        ids: %w[a b c x], edges: [%w[x c], %w[a b], %w[a c]],
        layers: [%w[x a], %w[c b]], options: model_order
      )

      expect(port_targets(order, "a", :east)).to eq([%w[b], %w[c]])
    end
  end
end
