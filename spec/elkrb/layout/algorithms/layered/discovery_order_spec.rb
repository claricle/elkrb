# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::DiscoveryOrder do
  def nodes_for(ids)
    ids.to_h { |id| [id, Elkrb::Graph::Node.new(id: id)] }
  end

  def graph_for(nodes, edges)
    Elkrb::Graph::Graph.new(
      id: "root", children: nodes.values,
      edges: edges.map do |source, target|
        Elkrb::Graph::Edge.new(id: "#{source}-#{target}", sources: [source],
                               targets: [target])
      end
    )
  end

  def sorted(ids:, edges:, layers:)
    nodes = nodes_for(ids)
    graph = graph_for(nodes, edges)
    columns = layers.map { |layer| layer.map { |id| nodes.fetch(id) } }
    described_class.new(graph, Elkrb::Layout::NodeIndex.build(graph))
      .sort(columns)
    columns.map { |layer| layer.map(&:id) }
  end

  it "lists nodes depth first along edges in creation order" do
    result = sorted(ids: %w[a b c d e], layers: [%w[b c d e]],
                    edges: [%w[a d], %w[d e], %w[a b]])

    expect(result).to eq([%w[d e b c]])
  end

  it "follows an edge from its target back to its source" do
    result = sorted(ids: %w[a b c], layers: [%w[a b c]],
                    edges: [%w[c b], %w[b a]])

    expect(result).to eq([%w[a b c]])
  end

  it "keeps items it never met at the end, in their current order" do
    stranger = Struct.new(:id).new("dummy")
    nodes = nodes_for(%w[a b])
    graph = Elkrb::Graph::Graph.new(id: "root", children: nodes.values,
                                    edges: [])
    layer = [stranger, nodes.fetch("b"), nodes.fetch("a")]

    described_class.new(graph, nil).sort([layer])

    expect(layer.map(&:id)).to eq(%w[a b dummy])
  end
end
