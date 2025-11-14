# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "elkjs Compatibility" do
  describe "Basic layered graph" do
    let(:graph_data) do
      JSON.parse(File.read("spec/fixtures/elkjs_basic.json"))
    end

    it "successfully lays out the basic graph with layered algorithm" do
      result = Elkrb::Layout::LayoutEngine.layout(graph_data, {})

      expect(result).to be_a(Elkrb::Graph::Graph)
      expect(result.id).to eq("root")
      expect(result.children.size).to eq(3)

      # Verify all nodes have been positioned
      result.children.each do |node|
        expect(node.x).to be_a(Numeric)
        expect(node.y).to be_a(Numeric)
        expect(node.x).to be >= 0
        expect(node.y).to be >= 0
      end

      # Verify graph dimensions are set
      expect(result.width).to be_a(Numeric)
      expect(result.height).to be_a(Numeric)
      expect(result.width).to be > 0
      expect(result.height).to be > 0
    end

    it "maintains node dimensions" do
      result = Elkrb::Layout::LayoutEngine.layout(graph_data, {})

      result.children.each do |node|
        expect(node.width).to eq(30.0)
        expect(node.height).to eq(30.0)
      end
    end

    it "maintains edge connectivity" do
      result = Elkrb::Layout::LayoutEngine.layout(graph_data, {})

      expect(result.edges.size).to eq(2)

      e1 = result.edges.find { |e| e.id == "e1" }
      expect(e1.sources).to eq(["n1"])
      expect(e1.targets).to eq(["n2"])

      e2 = result.edges.find { |e| e.id == "e2" }
      expect(e2.sources).to eq(["n1"])
      expect(e2.targets).to eq(["n3"])
    end
  end

  describe "Complex graph (bug-7)" do
    let(:graph_data) do
      JSON.parse(File.read("spec/fixtures/elkjs_bug7_complex.json"))
    end

    it "successfully lays out a complex graph without errors" do
      expect do
        Elkrb::Layout::LayoutEngine.layout(graph_data, {})
      end.not_to raise_error
    end

    it "positions all nodes" do
      result = Elkrb::Layout::LayoutEngine.layout(graph_data, {})

      expect(result).to be_a(Elkrb::Graph::Graph)
      expect(result.children.size).to eq(29)

      # Verify all nodes have valid positions
      result.children.each do |node|
        expect(node.x).to be_a(Numeric)
        expect(node.y).to be_a(Numeric)
        expect(node.x).to be >= 0
        expect(node.y).to be >= 0
      end
    end

    it "preserves all edges" do
      result = Elkrb::Layout::LayoutEngine.layout(graph_data, {})

      expect(result.edges.size).to eq(33)

      # Verify edges maintain their source/target relationships
      result.edges.each do |edge|
        expect(edge.sources).not_to be_empty
        expect(edge.targets).not_to be_empty
      end
    end

    it "handles nodes with ports" do
      result = Elkrb::Layout::LayoutEngine.layout(graph_data, {})

      nodes_with_ports = result.children.select do |n|
        n.ports && !n.ports.empty?
      end
      expect(nodes_with_ports.size).to be > 0

      # Verify port structure is preserved
      nodes_with_ports.each do |node|
        node.ports.each do |port|
          expect(port.id).not_to be_nil
          expect(port.width).to be_a(Numeric)
          expect(port.height).to be_a(Numeric)
        end
      end
    end

    it "respects layout properties" do
      result = Elkrb::Layout::LayoutEngine.layout(graph_data, {})

      # The graph should have been laid out successfully
      # Graph dimensions should be calculated
      expect(result.width).to be > 0
      expect(result.height).to be > 0
    end
  end

  describe "Multiple algorithm compatibility" do
    let(:simple_graph) do
      {
        "id" => "root",
        "children" => [
          { "id" => "n1", "width" => 30, "height" => 30 },
          { "id" => "n2", "width" => 30, "height" => 30 },
          { "id" => "n3", "width" => 30, "height" => 30 },
        ],
        "edges" => [
          { "id" => "e1", "sources" => ["n1"], "targets" => ["n2"] },
          { "id" => "e2", "sources" => ["n2"], "targets" => ["n3"] },
        ],
      }
    end

    %w[random fixed box layered force stress].each do |algorithm|
      it "successfully lays out with #{algorithm} algorithm" do
        result = Elkrb::Layout::LayoutEngine.layout(
          simple_graph,
          { "algorithm" => algorithm },
        )

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children.size).to eq(3)

        # All algorithms should position nodes
        result.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
        end
      end
    end
  end

  describe "Edge case handling" do
    it "handles empty graph" do
      empty_graph = {
        "id" => "root",
        "children" => [],
        "edges" => [],
      }

      result = Elkrb::Layout::LayoutEngine.layout(empty_graph, {})
      expect(result).to be_a(Elkrb::Graph::Graph)
      expect(result.children).to be_empty
      expect(result.edges).to be_empty
    end

    it "handles single node graph" do
      single_node = {
        "id" => "root",
        "children" => [
          { "id" => "n1", "width" => 30, "height" => 30 },
        ],
        "edges" => [],
      }

      result = Elkrb::Layout::LayoutEngine.layout(single_node, {})
      expect(result).to be_a(Elkrb::Graph::Graph)
      expect(result.children.size).to eq(1)
      expect(result.children.first.x).to be >= 0
      expect(result.children.first.y).to be >= 0
    end

    it "handles disconnected nodes" do
      disconnected = {
        "id" => "root",
        "children" => [
          { "id" => "n1", "width" => 30, "height" => 30 },
          { "id" => "n2", "width" => 30, "height" => 30 },
          { "id" => "n3", "width" => 30, "height" => 30 },
        ],
        "edges" => [],
      }

      result = Elkrb::Layout::LayoutEngine.layout(disconnected, {})
      expect(result).to be_a(Elkrb::Graph::Graph)
      expect(result.children.size).to eq(3)

      # All nodes should still be positioned
      result.children.each do |node|
        expect(node.x).to be_a(Numeric)
        expect(node.y).to be_a(Numeric)
      end
    end
  end
end
