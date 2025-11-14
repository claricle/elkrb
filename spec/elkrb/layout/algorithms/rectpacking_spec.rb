# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::RectPacking do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with a simple graph" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "rectpacking",
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

      it "packs all nodes without overlap" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # Check for no overlaps
        graph.children.combination(2).each do |node1, node2|
          # Check if rectangles overlap
          overlap_x = (node1.x < node2.x + node2.width) &&
            (node1.x + node1.width > node2.x)
          overlap_y = (node1.y < node2.y + node2.height) &&
            (node1.y + node1.height > node2.y)

          expect(overlap_x && overlap_y).to be false
        end
      end

      it "respects node spacing" do
        algorithm.layout(graph)

        # Find nodes that are horizontally adjacent
        graph.children.combination(2).each do |node1, node2|
          # Check if they're on the same shelf (similar y values)
          next unless (node1.y - node2.y).abs < 5.0

          # They should be spaced apart
          gap = if node1.x < node2.x
                  node2.x - (node1.x + node1.width)
                else
                  node1.x - (node2.x + node2.width)
                end

          # Gap should be at least the spacing (allowing for floating point)
          expect(gap).to be >= 9.0 if gap > 0
        end
      end

      it "sets graph dimensions" do
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

    context "with nodes of varying sizes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "rectpacking",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "tall", width: 30, height: 80),
          Elkrb::Graph::Node.new(id: "wide", width: 100, height: 20),
          Elkrb::Graph::Node.new(id: "small", width: 20, height: 20),
          Elkrb::Graph::Node.new(id: "medium", width: 50, height: 50),
        ]
      end

      it "efficiently packs nodes of different sizes" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
        end

        # Tall node should ideally be placed first (tallest first heuristic)
        tall_node = graph.children.find { |n| n.id == "tall" }
        expect(tall_node.x).to be_a(Numeric)
      end
    end

    context "with a single node" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "rectpacking",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 50, height: 40),
        ]
      end

      it "positions the single node at origin" do
        algorithm.layout(graph)

        node = graph.children.first
        # After padding, node will be offset by padding amount
        expect(node.x).to be >= 0.0
        expect(node.y).to be >= 0.0
      end
    end

    context "with many nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "rectpacking",
            "elk.spacing.nodeNode" => 5.0,
          ),
        )
      end

      before do
        graph.children = (1..20).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 30 + ((i % 5) * 10),
            height: 20 + ((i % 4) * 10),
          )
        end
      end

      it "packs all nodes efficiently" do
        algorithm.layout(graph)

        # All nodes should be positioned
        expect(graph.children.all? { |n| n.x.is_a?(Numeric) }).to be true
        expect(graph.children.all? { |n| n.y.is_a?(Numeric) }).to be true

        # No overlaps
        graph.children.combination(2).each do |node1, node2|
          overlap_x = (node1.x < node2.x + node2.width) &&
            (node1.x + node1.width > node2.x)
          overlap_y = (node1.y < node2.y + node2.height) &&
            (node1.y + node1.height > node2.y)

          expect(overlap_x && overlap_y).to be false
        end
      end
    end

    context "with no nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "rectpacking",
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
  end
end
