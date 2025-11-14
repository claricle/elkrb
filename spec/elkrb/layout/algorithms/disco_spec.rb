# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Disco do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with disconnected components" do
      it "identifies and lays out separate components" do
        graph = Elkrb::Graph::Graph.new

        # Component 1: Two connected nodes
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)

        # Component 2: Two connected nodes
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)
        node4 = Elkrb::Graph::Node.new(id: "n4", width: 50, height: 30)

        # Component 3: Single isolated node
        node5 = Elkrb::Graph::Node.new(id: "n5", width: 50, height: 30)

        graph.children = [node1, node2, node3, node4, node5]

        # Edges connecting components
        port1 = Elkrb::Graph::Port.new(id: "p1", node: node1)
        port2 = Elkrb::Graph::Port.new(id: "p2", node: node2)
        port3 = Elkrb::Graph::Port.new(id: "p3", node: node3)
        port4 = Elkrb::Graph::Port.new(id: "p4", node: node4)

        edge1 = Elkrb::Graph::Edge.new(
          id: "e1",
          sources: [port1],
          targets: [port2],
        )
        edge2 = Elkrb::Graph::Edge.new(
          id: "e2",
          sources: [port3],
          targets: [port4],
        )

        graph.edges = [edge1, edge2]

        result = algorithm.layout(graph)

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children.size).to eq(5)

        # All nodes should have positions
        result.children.each do |node|
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end
      end
    end

    context "with row arrangement" do
      it "arranges components in a horizontal row" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "disco.componentArrangement" => "row" }

        # Three separate components (single nodes each)
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)

        graph.children = [node1, node2, node3]
        graph.edges = []

        algorithm.layout(graph)

        # Nodes should be arranged horizontally with spacing
        expect(node1.x).to be < node2.x
        expect(node2.x).to be < node3.x
      end
    end

    context "with column arrangement" do
      it "arranges components in a vertical column" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "disco.componentArrangement" => "column" }

        # Three separate components (single nodes each)
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)

        graph.children = [node1, node2, node3]
        graph.edges = []

        algorithm.layout(graph)

        # Nodes should be arranged vertically with spacing
        expect(node1.y).to be < node2.y
        expect(node2.y).to be < node3.y
      end
    end

    context "with grid arrangement" do
      it "arranges components in a grid" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "disco.componentArrangement" => "grid" }

        # Four separate components (single nodes each)
        nodes = Array.new(4) do |i|
          Elkrb::Graph::Node.new(id: "n#{i + 1}", width: 50, height: 30)
        end

        graph.children = nodes
        graph.edges = []

        result = algorithm.layout(graph)

        # With 4 nodes, should form a 2×2 grid
        # Check that we have 2 distinct x positions and 2 distinct y positions
        x_positions = result.children.map(&:x).uniq.sort
        y_positions = result.children.map(&:y).uniq.sort

        expect(x_positions.size).to be >= 2
        expect(y_positions.size).to be >= 2
      end
    end

    context "with component spacing option" do
      it "respects custom component spacing" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = {
          "disco.componentArrangement" => "row",
          "disco.componentSpacing" => 50.0,
        }

        # Two separate components (single nodes each)
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        algorithm.layout(graph)

        # Spacing should be at least 50 pixels
        spacing = node2.x - (node1.x + node1.width)
        expect(spacing).to be >= 50.0
      end
    end

    context "with connected graph" do
      it "treats fully connected graph as single component" do
        graph = Elkrb::Graph::Graph.new

        # All nodes connected
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)

        graph.children = [node1, node2, node3]

        port1 = Elkrb::Graph::Port.new(id: "p1", node: node1)
        port2 = Elkrb::Graph::Port.new(id: "p2", node: node2)
        port3 = Elkrb::Graph::Port.new(id: "p3", node: node3)

        edge1 = Elkrb::Graph::Edge.new(
          id: "e1",
          sources: [port1],
          targets: [port2],
        )
        edge2 = Elkrb::Graph::Edge.new(
          id: "e2",
          sources: [port2],
          targets: [port3],
        )

        graph.edges = [edge1, edge2]

        result = algorithm.layout(graph)

        # All nodes should be positioned (single component)
        expect(result.children.all? { |n| n.x && n.y }).to be true
      end
    end

    context "with empty graph" do
      it "handles empty graph" do
        graph = Elkrb::Graph::Graph.new
        graph.children = []
        graph.edges = []

        result = algorithm.layout(graph)

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children).to be_empty
      end
    end

    context "with custom component algorithm" do
      it "uses specified algorithm for component layout" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "disco.componentAlgorithm" => "box" }

        # Two separate components with multiple nodes each
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        result = algorithm.layout(graph)

        # Should apply box algorithm to each component
        expect(result.children.all? { |n| n.x && n.y }).to be true
      end
    end
  end
end
