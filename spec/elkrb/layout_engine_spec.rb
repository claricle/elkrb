# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::LayoutEngine do
  let(:simple_graph_json) do
    JSON.parse(File.read("spec/fixtures/simple_graph.json"))
  end

  describe "#layout" do
    context "with box algorithm" do
      it "positions nodes in a grid pattern" do
        result = described_class.layout(simple_graph_json, algorithm: "box")

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children.length).to eq(3)

        # Check that nodes have positions
        result.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # Check graph has dimensions
        expect(result.width).to be > 0
        expect(result.height).to be > 0
      end
    end

    context "with random algorithm" do
      it "positions nodes at random locations" do
        result = described_class.layout(simple_graph_json, algorithm: "random")

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children.length).to eq(3)

        # Check that nodes have positions
        result.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # Check graph has dimensions
        expect(result.width).to be > 0
        expect(result.height).to be > 0
      end
    end

    context "with fixed algorithm" do
      it "keeps nodes at their current positions" do
        graph_with_positions = simple_graph_json.dup
        graph_with_positions["children"] = [
          { "id" => "n1", "x" => 10, "y" => 20, "width" => 30, "height" => 30 },
          { "id" => "n2", "x" => 50, "y" => 60, "width" => 30, "height" => 30 },
          { "id" => "n3", "x" => 90, "y" => 100, "width" => 30,
            "height" => 30 },
        ]

        result = described_class.layout(
          graph_with_positions,
          algorithm: "fixed",
        )

        expect(result).to be_a(Elkrb::Graph::Graph)

        # Nodes should be shifted by padding but relative positions maintained
        n1 = result.find_node("n1")
        n2 = result.find_node("n2")
        n3 = result.find_node("n3")

        # Check that relative positions are maintained (n2.x - n1.x should equal 40)
        expect(n2.x - n1.x).to eq(40)
        expect(n3.x - n2.x).to eq(40)
      end
    end

    context "with layout options" do
      it "applies spacing options" do
        result = described_class.layout(
          simple_graph_json,
          algorithm: "box",
          spacing_node_node: 50,
        )

        expect(result).to be_a(Elkrb::Graph::Graph)

        # With larger spacing, graph should be larger
        n1 = result.children[0]
        n2 = result.children[1]

        # Nodes should be spaced at least 50 units apart
        distance = n2.x - n1.x
        expect(distance).to be >= 50
      end

      it "applies padding options" do
        result = described_class.layout(
          simple_graph_json,
          algorithm: "box",
          padding: { top: 20, bottom: 20, left: 20, right: 20 },
        )

        expect(result).to be_a(Elkrb::Graph::Graph)

        # First node should be at least at padding position
        n1 = result.children[0]
        expect(n1.x).to be >= 20
        expect(n1.y).to be >= 20
      end
    end

    context "with hash input" do
      it "converts hash to Graph model" do
        result = described_class.layout(simple_graph_json, algorithm: "box")

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.id).to eq("root")
      end
    end

    context "with Graph model input" do
      it "accepts Graph model directly" do
        graph = Elkrb::Graph::Graph.from_hash(simple_graph_json)
        result = described_class.layout(graph, algorithm: "box")

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.id).to eq("root")
      end
    end

    context "with invalid algorithm" do
      it "raises an error" do
        expect do
          described_class.layout(simple_graph_json, algorithm: "nonexistent")
        end.to raise_error(Elkrb::Error, /Unknown layout algorithm/)
      end
    end
  end
end
