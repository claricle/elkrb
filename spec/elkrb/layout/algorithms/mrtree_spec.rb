# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::MRTree do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with a simple tree graph" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
            "elk.spacing.nodeNode" => 20.0,
          ),
        )
      end

      before do
        # Create a simple tree: root -> child1, child2
        root = Elkrb::Graph::Node.new(
          id: "root",
          width: 50,
          height: 30,
        )
        child1 = Elkrb::Graph::Node.new(
          id: "child1",
          width: 40,
          height: 30,
        )
        child2 = Elkrb::Graph::Node.new(
          id: "child2",
          width: 40,
          height: 30,
        )

        graph.children = [root, child1, child2]

        # Add edges
        graph.edges = [
          Elkrb::Graph::Edge.new(
            id: "e1",
            sources: ["root"],
            targets: ["child1"],
          ),
          Elkrb::Graph::Edge.new(
            id: "e2",
            sources: ["root"],
            targets: ["child2"],
          ),
        ]
      end

      it "positions nodes in a tree structure" do
        algorithm.layout(graph)

        # Root should be at the top (after padding)
        root = graph.children.find { |n| n.id == "root" }
        expect(root.x).to be_a(Numeric)
        expect(root.y).to be >= 0.0

        # Children should be below and spaced out
        child1 = graph.children.find { |n| n.id == "child1" }
        child2 = graph.children.find { |n| n.id == "child2" }

        expect(child1.y).to be > root.y
        expect(child2.y).to be > root.y
        expect(child1.x).not_to eq(child2.x)
      end

      it "respects node spacing" do
        algorithm.layout(graph)

        child1 = graph.children.find { |n| n.id == "child1" }
        child2 = graph.children.find { |n| n.id == "child2" }

        # Children should be spaced apart
        spacing = (child2.x - child1.x).abs
        expect(spacing).to be >= 20.0
      end

      it "sets graph dimensions" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0
      end
    end

    context "with multiple root nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        # Create two separate trees
        root1 = Elkrb::Graph::Node.new(
          id: "root1",
          width: 50,
          height: 30,
        )
        root2 = Elkrb::Graph::Node.new(
          id: "root2",
          width: 50,
          height: 30,
        )
        child1 = Elkrb::Graph::Node.new(
          id: "child1",
          width: 40,
          height: 30,
        )
        child2 = Elkrb::Graph::Node.new(
          id: "child2",
          width: 40,
          height: 30,
        )

        graph.children = [root1, root2, child1, child2]

        # Create two separate trees
        graph.edges = [
          Elkrb::Graph::Edge.new(
            id: "e1",
            sources: ["root1"],
            targets: ["child1"],
          ),
          Elkrb::Graph::Edge.new(
            id: "e2",
            sources: ["root2"],
            targets: ["child2"],
          ),
        ]
      end

      it "lays out multiple trees side by side" do
        algorithm.layout(graph)

        root1 = graph.children.find { |n| n.id == "root1" }
        root2 = graph.children.find { |n| n.id == "root2" }

        # Both roots should be at same y level (after padding)
        expect(root1.y).to eq(root2.y)

        # Trees should be separated horizontally
        expect((root2.x - root1.x).abs).to be > 0
      end
    end

    context "with no edges" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 50, height: 30),
          Elkrb::Graph::Node.new(id: "node2", width: 50, height: 30),
        ]
        graph.edges = []
      end

      it "treats all nodes as roots" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
        end
      end
    end
  end
end
