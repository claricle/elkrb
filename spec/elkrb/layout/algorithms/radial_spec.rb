# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Radial do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with a simple graph" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "radial",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 40, height: 30),
          Elkrb::Graph::Node.new(id: "node2", width: 40, height: 30),
          Elkrb::Graph::Node.new(id: "node3", width: 40, height: 30),
          Elkrb::Graph::Node.new(id: "node4", width: 40, height: 30),
        ]
      end

      it "arranges nodes in a circular pattern" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
        end

        # Calculate distances from center
        center_x = graph.width / 2.0
        center_y = graph.height / 2.0

        distances = graph.children.map do |node|
          node_center_x = node.x + (node.width / 2.0)
          node_center_y = node.y + (node.height / 2.0)
          Math.sqrt(
            ((node_center_x - center_x)**2) +
            ((node_center_y - center_y)**2),
          )
        end

        # All nodes should be roughly the same distance from center
        avg_distance = distances.sum / distances.size
        distances.each do |distance|
          expect((distance - avg_distance).abs).to be < 10.0
        end
      end

      it "evenly distributes nodes around the circle" do
        algorithm.layout(graph)

        center_x = graph.width / 2.0
        center_y = graph.height / 2.0

        # Calculate angles for each node
        angles = graph.children.map do |node|
          node_center_x = node.x + (node.width / 2.0)
          node_center_y = node.y + (node.height / 2.0)
          Math.atan2(node_center_y - center_y, node_center_x - center_x)
        end

        # Sort angles
        sorted_angles = angles.sort

        # Calculate angular spacing
        expected_spacing = (2 * Math::PI) / graph.children.size

        # Check that nodes are evenly spaced
        (0...(sorted_angles.size - 1)).each do |i|
          spacing = sorted_angles[i + 1] - sorted_angles[i]
          expect((spacing - expected_spacing).abs).to be < 0.2
        end
      end

      it "sets graph dimensions" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0
      end
    end

    context "with a single node" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "radial",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 40, height: 30),
        ]
      end

      it "centers the single node" do
        algorithm.layout(graph)

        node = graph.children.first
        expect(node.x).to be_a(Numeric)
        expect(node.y).to be_a(Numeric)
      end
    end

    context "with many nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "radial",
          ),
        )
      end

      before do
        graph.children = (1..12).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 30,
            height: 20,
          )
        end
      end

      it "arranges all nodes in a circle" do
        algorithm.layout(graph)

        # All nodes should be positioned
        expect(graph.children.all? { |n| n.x.is_a?(Numeric) }).to be true
        expect(graph.children.all? { |n| n.y.is_a?(Numeric) }).to be true

        # Graph should be large enough
        expect(graph.width).to be > 100
        expect(graph.height).to be > 100
      end
    end

    context "with no nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "radial",
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
