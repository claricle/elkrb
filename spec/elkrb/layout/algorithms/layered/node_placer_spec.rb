# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::NodePlacer do
  describe "directional placement" do
    let(:layers) do
      [
        [Elkrb::Graph::Node.new(id: "a", width: 30.0, height: 20.0)],
        [
          Elkrb::Graph::Node.new(id: "b", width: 10.0, height: 10.0),
          Elkrb::Graph::Node.new(id: "c", width: 20.0, height: 20.0),
        ],
      ]
    end

    # Nodes without edges are separate blocks; Brandes-Koepf compaction puts a
    # block at the smallest cross coordinate its layer neighbour allows, so the
    # first node of each layer sits at the start of the cross axis. A node
    # without edges is centred across its layer, so the 10px node sits 5px in.
    it "starts RIGHT layers at the cross-axis origin" do
      described_class.new(
        Elkrb::Graph::Graph.new(id: "r"), layers,
        direction: "RIGHT", layer_spacing: 7.0, node_spacing: 5.0
      ).place_nodes

      expect(layers.flatten.map { |node| [node.x, node.y] })
        .to eq([[0.0, 0.0], [42.0, 0.0], [37.0, 15.0]])
    end

    it "maps DOWN onto y and stacks nodes along x" do
      described_class.new(
        Elkrb::Graph::Graph.new(id: "r"), layers,
        direction: "DOWN", layer_spacing: 7.0, node_spacing: 5.0
      ).place_nodes

      expect(layers.flatten.map { |node| [node.x, node.y] })
        .to eq([[0.0, 0.0], [0.0, 32.0], [15.0, 27.0]])
    end

    it "mirrors LEFT within the placed bounding box" do
      described_class.new(
        Elkrb::Graph::Graph.new(id: "r"), layers,
        direction: "LEFT", layer_spacing: 7.0, node_spacing: 5.0
      ).place_nodes

      expect(layers.flatten.map { |node| [node.x, node.y] })
        .to eq([[27.0, 0.0], [5.0, 0.0], [0.0, 15.0]])
    end

    it "mirrors UP within the placed bounding box" do
      described_class.new(
        Elkrb::Graph::Graph.new(id: "r"), layers,
        direction: "UP", layer_spacing: 7.0, node_spacing: 5.0
      ).place_nodes

      expect(layers.flatten.map { |node| [node.x, node.y] })
        .to eq([[0.0, 27.0], [0.0, 5.0], [15.0, 0.0]])
    end
  end

  describe "fan-out alignment" do
    # Two EAST ports on a 10px parent are spread evenly (10 / 3 apart), and the
    # target's single WEST port is centred (5). Brandes-Koepf aligns the
    # parent's first port with child v: 20 + 5 - 10 / 3 = 21.67.
    it "aligns a parent's first edge port with its target's port" do
      parent = Elkrb::Graph::Node.new(id: "parent", width: 10, height: 10)
      children = %w[u v w].map do |id|
        Elkrb::Graph::Node.new(id: id, width: 10, height: 10)
      end
      graph = Elkrb::Graph::Graph.new(
        id: "root",
        children: [parent, *children],
        edges: %w[v w].map do |target|
          Elkrb::Graph::Edge.new(
            id: "parent_#{target}", sources: ["parent"], targets: [target],
          )
        end,
      )
      placer = described_class.new(
        graph, [[parent], children], node_spacing: 10
      )
      placer.index = Elkrb::Layout::NodeIndex.build(graph)

      placer.place_nodes

      expect(parent.y).to be_within(1e-9).of(21.0 + (2.0 / 3))
    end
  end
end
