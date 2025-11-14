# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::TopdownPacking do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with a basic graph (3-5 nodes)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "topdownpacking",
            "elk.spacing.nodeNode" => 10.0,
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 50, height: 40),
          Elkrb::Graph::Node.new(id: "node2", width: 40, height: 30),
          Elkrb::Graph::Node.new(id: "node3", width: 60, height: 35),
          Elkrb::Graph::Node.new(id: "node4", width: 30, height: 25),
        ]
      end

      it "arranges nodes in a grid pattern" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # For 4 nodes, should create a 2x2 grid
        # Verify grid structure (nodes should align in rows/columns)
        nodes = graph.children.sort_by { |n| [n.y, n.x] }

        # Top row nodes should have similar y values
        expect((nodes[0].y - nodes[1].y).abs).to be < 1.0
        # Bottom row nodes should have similar y values
        expect((nodes[2].y - nodes[3].y).abs).to be < 1.0
      end

      it "creates nodes with uniform dimensions" do
        algorithm.layout(graph)

        # All nodes should have the same width and height in grid layout
        widths = graph.children.map(&:width).uniq
        heights = graph.children.map(&:height).uniq

        expect(widths.size).to eq(1)
        expect(heights.size).to eq(1)
      end

      it "verifies no overlaps between nodes" do
        algorithm.layout(graph)

        # Check for no overlaps
        graph.children.combination(2).each do |node1, node2|
          overlap_x = (node1.x < node2.x + node2.width) &&
            (node1.x + node1.width > node2.x)
          overlap_y = (node1.y < node2.y + node2.height) &&
            (node1.y + node1.height > node2.y)

          expect(overlap_x && overlap_y).to be false
        end
      end

      it "sets graph dimensions correctly" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0

        # Graph should be large enough to contain all nodes
        graph.children.each do |node|
          expect(node.x + node.width).to be <= graph.width
          expect(node.y + node.height).to be <= graph.height
        end
      end
    end

    context "with many nodes (20+ nodes)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "topdownpacking",
            "elk.spacing.nodeNode" => 5.0,
          ),
        )
      end

      before do
        graph.children = (1..25).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 30 + ((i % 5) * 10),
            height: 20 + ((i % 4) * 10),
          )
        end
      end

      it "arranges all nodes in a grid" do
        algorithm.layout(graph)

        # All nodes should be positioned
        expect(graph.children.all? { |n| n.x.is_a?(Numeric) }).to be true
        expect(graph.children.all? { |n| n.y.is_a?(Numeric) }).to be true

        # For 25 nodes, should create a 5x5 grid
        # Verify that nodes are arranged in rows
        nodes_by_row = graph.children.group_by { |n| n.y.round }
        expect(nodes_by_row.size).to be <= 5
      end

      it "maintains proper spacing between nodes" do
        algorithm.layout(graph)

        # Check spacing between adjacent nodes
        sorted_nodes = graph.children.sort_by { |n| [n.y, n.x] }

        # Check horizontal spacing on first row
        row_nodes = sorted_nodes.select do |n|
          (n.y - sorted_nodes.first.y).abs < 1.0
        end
        if row_nodes.size > 1
          spacing = row_nodes[1].x - (row_nodes[0].x + row_nodes[0].width)
          expect(spacing).to be >= 4.0 # Allow small floating point variance
        end
      end

      it "verifies no overlaps with many nodes" do
        algorithm.layout(graph)

        # Check for no overlaps
        graph.children.combination(2).each do |node1, node2|
          overlap_x = (node1.x < node2.x + node2.width) &&
            (node1.x + node1.width > node2.x)
          overlap_y = (node1.y < node2.y + node2.height) &&
            (node1.y + node1.height > node2.y)

          expect(overlap_x && overlap_y).to be false
        end
      end
    end

    context "with different aspect ratios" do
      let(:aspect_ratio) { 2.0 }

      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "topdownpacking"
        opts["topdownpacking.aspectRatio"] = aspect_ratio

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..9).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 50,
            height: 50,
          )
        end
      end

      it "respects aspect ratio option" do
        algorithm.layout(graph)

        # All nodes should have dimensions respecting the aspect ratio
        graph.children.each do |node|
          ratio = node.width / node.height
          expect(ratio).to be_within(0.1).of(aspect_ratio)
        end
      end

      it "creates a proper grid with aspect ratio 2.0" do
        algorithm.layout(graph)

        # For 9 nodes, should create a 3x3 grid
        nodes_by_y = graph.children.group_by { |n| n.y.round }
        expect(nodes_by_y.size).to eq(3)
      end
    end

    context "with various node sizes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "topdownpacking",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "tiny", width: 10, height: 10),
          Elkrb::Graph::Node.new(id: "small", width: 30, height: 20),
          Elkrb::Graph::Node.new(id: "medium", width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "large", width: 80, height: 60),
          Elkrb::Graph::Node.new(id: "huge", width: 120, height: 100),
        ]
      end

      it "normalizes node sizes in grid layout" do
        algorithm.layout(graph)

        # All nodes should be resized to uniform dimensions
        widths = graph.children.map(&:width).uniq
        heights = graph.children.map(&:height).uniq

        expect(widths.size).to eq(1)
        expect(heights.size).to eq(1)
      end

      it "positions all nodes correctly" do
        algorithm.layout(graph)

        graph.children.each do |node|
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end
      end
    end

    context "with a single node" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "topdownpacking",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 50, height: 40),
        ]
      end

      it "positions the single node correctly" do
        algorithm.layout(graph)

        node = graph.children.first
        # After padding, node will be offset by padding amount
        expect(node.x).to be >= 0.0
        expect(node.y).to be >= 0.0
      end

      it "sets appropriate graph dimensions" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0
      end
    end

    context "with no nodes (empty graph)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "topdownpacking",
          ),
        )
      end

      before do
        graph.children = []
      end

      it "handles empty graph gracefully" do
        algorithm.layout(graph)

        expect(graph.width).to eq(0)
        expect(graph.height).to eq(0)
      end
    end

    context "with custom node width option" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "topdownpacking"
        opts["topdownpacking.nodeWidth"] = 100.0
        opts["topdownpacking.aspectRatio"] = 1.5

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..6).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 50,
            height: 50,
          )
        end
      end

      it "respects custom node width" do
        algorithm.layout(graph)

        graph.children.each do |node|
          expect(node.width).to eq(100.0)
        end
      end

      it "calculates height from width and aspect ratio" do
        algorithm.layout(graph)

        graph.children.each do |node|
          expected_height = 100.0 / 1.5
          expect(node.height).to be_within(0.1).of(expected_height)
        end
      end
    end

    context "grid dimension calculations" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "topdownpacking",
          ),
        )
      end

      it "creates 3x3 grid for 9 nodes" do
        graph.children = (1..9).map { |i| Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 50) }
        algorithm.layout(graph)

        # Should create 3x3 grid
        unique_y = graph.children.map { |n| n.y.round }.uniq.sort
        unique_x = graph.children.map { |n| n.x.round }.uniq.sort

        expect(unique_y.size).to eq(3)
        expect(unique_x.size).to eq(3)
      end

      it "creates 4x3 grid for 10 nodes" do
        graph.children = (1..10).map { |i| Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 50) }
        algorithm.layout(graph)

        # Should create 4x3 grid (4 columns, 3 rows since sqrt(10) ≈ 3.16 -> 4 cols)
        unique_y = graph.children.map { |n| n.y.round }.uniq.sort
        unique_x = graph.children.map { |n| n.x.round }.uniq.sort

        expect(unique_x.size).to eq(4)
        expect(unique_y.size).to eq(3)
      end

      it "creates 5x5 grid for 25 nodes" do
        graph.children = (1..25).map { |i| Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 50) }
        algorithm.layout(graph)

        # Should create 5x5 grid
        unique_y = graph.children.map { |n| n.y.round }.uniq.sort
        unique_x = graph.children.map { |n| n.x.round }.uniq.sort

        expect(unique_y.size).to eq(5)
        expect(unique_x.size).to eq(5)
      end
    end
  end
end
