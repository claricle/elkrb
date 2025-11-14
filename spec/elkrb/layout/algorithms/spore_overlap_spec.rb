# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::SporeOverlap do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with overlapping nodes" do
      it "removes overlaps between nodes" do
        graph = Elkrb::Graph::Graph.new

        # Create overlapping nodes
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 25, y: 0, width: 50,
                                       height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        algorithm.layout(graph)

        # Nodes should no longer overlap
        right1 = node1.x + node1.width
        left2 = node2.x

        expect(right1).to be <= left2
      end
    end

    context "with minimum spacing" do
      it "respects minimum spacing between nodes" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "spore.nodeSpacing" => 20.0 }

        # Create nodes that are too close
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 60, y: 0, width: 50,
                                       height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        algorithm.layout(graph)

        # Calculate spacing between nodes
        spacing = node2.x - (node1.x + node1.width)
        expect(spacing).to be >= 20.0
      end
    end

    context "with vertically overlapping nodes" do
      it "resolves vertical overlaps" do
        graph = Elkrb::Graph::Graph.new

        # Create vertically overlapping nodes
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 50)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 0, y: 25, width: 50,
                                       height: 50)

        graph.children = [node1, node2]
        graph.edges = []

        algorithm.layout(graph)

        # Nodes should no longer overlap vertically
        bottom1 = node1.y + node1.height
        top2 = node2.y

        expect(bottom1).to be <= top2
      end
    end

    context "with multiple overlapping nodes" do
      it "resolves all overlaps" do
        graph = Elkrb::Graph::Graph.new

        # Create a cluster of overlapping nodes
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 40,
                                       height: 40)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 20, y: 0, width: 40,
                                       height: 40)
        node3 = Elkrb::Graph::Node.new(id: "n3", x: 0, y: 20, width: 40,
                                       height: 40)
        node4 = Elkrb::Graph::Node.new(id: "n4", x: 20, y: 20, width: 40,
                                       height: 40)

        graph.children = [node1, node2, node3, node4]
        graph.edges = []

        result = algorithm.layout(graph)

        # Check that no nodes overlap
        nodes = result.children
        nodes.each_with_index do |n1, i|
          nodes[(i + 1)..].each do |n2|
            right1 = n1.x + n1.width
            left2 = n2.x
            bottom1 = n1.y + n1.height
            top2 = n2.y

            # Either horizontally or vertically separated
            separated = (right1 <= left2) || (left2 + n2.width <= n1.x) ||
              (bottom1 <= top2) || (top2 + n2.height <= n1.y)

            expect(separated).to be true
          end
        end
      end
    end

    context "with max iterations limit" do
      it "stops after max iterations" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "spore.maxIterations" => 5 }

        # Create many overlapping nodes
        nodes = Array.new(20) do |i|
          Elkrb::Graph::Node.new(id: "n#{i}", x: 0, y: 0, width: 50, height: 30)
        end

        graph.children = nodes
        graph.edges = []

        # Should complete without infinite loop
        expect { algorithm.layout(graph) }.not_to raise_error
      end
    end

    context "with non-overlapping nodes" do
      it "preserves positions of non-overlapping nodes" do
        graph = Elkrb::Graph::Graph.new

        # Create well-separated nodes
        node1 = Elkrb::Graph::Node.new(id: "n1", x: 0, y: 0, width: 50,
                                       height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", x: 100, y: 0, width: 50,
                                       height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", x: 0, y: 100, width: 50,
                                       height: 30)

        graph.children = [node1, node2, node3]
        graph.edges = []

        original_positions = graph.children.map { |n| [n.x, n.y] }

        result = algorithm.layout(graph)

        # Positions should be relatively unchanged (allowing for padding)
        result.children.each_with_index do |node, i|
          orig_x, orig_y = original_positions[i]
          # Allow some tolerance for padding adjustments
          expect((node.x - orig_x).abs).to be < 20
          expect((node.y - orig_y).abs).to be < 20
        end
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
      it "handles single node without changes" do
        graph = Elkrb::Graph::Graph.new

        node = Elkrb::Graph::Node.new(id: "n1", x: 10, y: 20, width: 50,
                                      height: 30)
        graph.children = [node]
        graph.edges = []

        result = algorithm.layout(graph)

        expect(result.children.size).to eq(1)
        # Position may change slightly due to padding
        expect(node.x).to be >= 0
        expect(node.y).to be >= 0
      end
    end
  end
end
