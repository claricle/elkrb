# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Graph::Graph do
  describe "#initialize" do
    it "creates a graph with default values" do
      graph = described_class.new

      expect(graph.id).to eq("root")
      expect(graph.x).to eq(0.0)
      expect(graph.y).to eq(0.0)
      expect(graph.width).to eq(0.0)
      expect(graph.height).to eq(0.0)
      expect(graph.children).to eq([])
      expect(graph.edges).to eq([])
    end

    it "creates a graph with custom attributes" do
      graph = described_class.new(
        id: "custom",
        x: 10.0,
        y: 20.0,
        width: 100.0,
        height: 200.0,
      )

      expect(graph.id).to eq("custom")
      expect(graph.x).to eq(10.0)
      expect(graph.y).to eq(20.0)
      expect(graph.width).to eq(100.0)
      expect(graph.height).to eq(200.0)
    end
  end

  describe "#from_hash" do
    it "creates a graph from a hash" do
      hash = {
        "id" => "test",
        "children" => [
          { "id" => "n1", "width" => 100, "height" => 60 },
          { "id" => "n2", "width" => 100, "height" => 60 },
        ],
        "edges" => [
          { "id" => "e1", "sources" => ["n1"], "targets" => ["n2"] },
        ],
      }

      graph = described_class.from_hash(hash)

      expect(graph.id).to eq("test")
      expect(graph.children.size).to eq(2)
      expect(graph.children[0].id).to eq("n1")
      expect(graph.edges.size).to eq(1)
      expect(graph.edges[0].id).to eq("e1")
    end
  end

  describe "#to_json" do
    it "serializes to JSON" do
      graph = described_class.new(id: "test")
      json = graph.to_json

      expect(json).to include('"id":"test"')
    end
  end

  describe "#to_yaml" do
    it "serializes to YAML" do
      graph = described_class.new(id: "test")
      yaml = graph.to_yaml

      expect(yaml).to include("id: test")
    end
  end

  describe "#find_node" do
    it "finds a node by id" do
      graph = described_class.new(
        children: [
          Elkrb::Graph::Node.new(id: "n1"),
          Elkrb::Graph::Node.new(id: "n2"),
        ],
      )

      node = graph.find_node("n2")
      expect(node.id).to eq("n2")
    end

    it "returns nil for non-existent node" do
      graph = described_class.new

      node = graph.find_node("nonexistent")
      expect(node).to be_nil
    end
  end
end
