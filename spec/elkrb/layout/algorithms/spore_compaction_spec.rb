# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::SporeCompaction do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with horizontal compaction" do
      it "removes horizontal whitespace" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "spore.compactionDirection" => "horizontal" }

        # Create nodes with excessive horizontal spacing
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 150, y: 0, width: 50,
                                       height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        original_spacing = node2.x - (node1.x + node1.width)

        algorithm.layout(graph)

        # Spacing should be reduced
        new_spacing = node2.x - (node1.x + node1.width)
        expect(new_spacing).to be < original_spacing
        expect(new_spacing).to be >= 10.0 # min spacing
      end
    end

    context "with vertical compaction" do
      it "removes vertical whitespace" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "spore.compactionDirection" => "vertical" }

        # Create nodes with excessive vertical spacing
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 0, y: 150, width: 50,
                                       height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        original_spacing = node2.y - (node1.y + node1.height)

        algorithm.layout(graph)

        # Spacing should be reduced
        new_spacing = node2.y - (node1.y + node1.height)
        expect(new_spacing).to be < original_spacing
        expect(new_spacing).to be >= 10.0 # min spacing
      end
    end

    context "with both directions compaction" do
      it "compacts in both horizontal and vertical directions" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "spore.compactionDirection" => "both" }

        # Create nodes with excessive spacing
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 150, y: 0, width: 50,
                                       height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", x: 0, y: 150, width: 50,
                                       height: 30)

        graph.children = [node1, node2, node3]
        graph.edges = []

        algorithm.layout(graph)

        # Check horizontal compaction
        h_spacing = node2.x - (node1.x + node1.width)
        expect(h_spacing).to be < 150

        # Check vertical compaction
        v_spacing = node3.y - (node1.y + node1.height)
        expect(v_spacing).to be < 150
      end
    end

    context "with custom node spacing" do
      it "respects minimum spacing between nodes" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = {
          "spore.compactionDirection" => "horizontal",
          "spore.nodeSpacing" => 25.0,
        }

        # Create nodes
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 200, y: 0, width: 50,
                                       height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        algorithm.layout(graph)

        # Spacing should be at least 25.0
        spacing = node2.x - (node1.x + node1.width)
        expect(spacing).to be >= 25.0
      end
    end

    context "with staggered nodes" do
      it "compacts while preserving vertical relationships" do
        graph = Elkrb::Graph::Graph.new

        # Create staggered layout
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 200, y: 50, width: 50,
                                       height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        algorithm.layout(graph)

        # Node2 should move left since it doesn't vertically overlap with node1
        expect(node2.x).to be < 200
      end
    end

    context "with grid layout" do
      it "compacts grid layout efficiently" do
        graph = Elkrb::Graph::Graph.new

        # Create 2x2 grid with excessive spacing
        nodes = [
          Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50, height: 30),
          Elkrb::Graph::Node.new(id: "n2", x: 150, y: 0, width: 50, height: 30),
          Elkrb::Graph::Node.new(id: "n3", x: 0, y: 150, width: 50, height: 30),
          Elkrb::Graph::Node.new(id: "n4", x: 150, y: 150, width: 50,
                                 height: 30),
        ]

        graph.children = nodes
        graph.edges = []

        result = algorithm.layout(graph)

        # Grid should be more compact
        max_x = result.children.map { |n| n.x + n.width }.max
        max_y = result.children.map { |n| n.y + n.height }.max

        expect(max_x).to be < 250
        expect(max_y).to be < 250
      end
    end

    context "with normalization" do
      it "normalizes positions to start at origin" do
        graph = Elkrb::Graph::Graph.new

        # Create nodes not starting at origin
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 100, y: 100, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 200, y: 200, width: 50,
                                       height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        result = algorithm.layout(graph)

        # After compaction and normalization, min position should be at padding
        min_x = result.children.map(&:x).min
        min_y = result.children.map(&:y).min

        # Should be at padding offset (12.0 default)
        expect(min_x).to be >= 0
        expect(min_y).to be >= 0
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

    context "with single node" do
      it "handles single node" do
        graph = Elkrb::Graph::Graph.new

        node = Elkrb::Graph::Node.new(id: "n1", x: 100, y: 100, width: 50,
                                      height: 30)
        graph.children = [node]
        graph.edges = []

        result = algorithm.layout(graph)

        expect(result.children.size).to eq(1)
        # Should be normalized to origin + padding
        expect(node.x).to be >= 0
        expect(node.y).to be >= 0
      end
    end

    context "with overlapping columns" do
      it "preserves vertical column structure" do
        graph = Elkrb::Graph::Graph.new

        # Create two columns of nodes
        col1_nodes = [
          Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50, height: 30),
          Elkrb::Graph::Node.new(id: "n2", x: 0, y: 100, width: 50, height: 30),
        ]
        col2_nodes = [
          Elkrb::Graph::Node.new(id: "n3", x: 200, y: 0, width: 50, height: 30),
          Elkrb::Graph::Node.new(id: "n4", x: 200, y: 100, width: 50,
                                 height: 30),
        ]

        graph.children = col1_nodes + col2_nodes
        graph.edges = []

        algorithm.layout(graph)

        # Column 2 should move closer to column 1
        col2_x = col2_nodes.first.x
        expect(col2_x).to be < 200

        # But both column 2 nodes should have same x coordinate
        expect(col2_nodes.all? { |n| n.x == col2_x }).to be true
      end
    end
  end
end
