# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::NodeIndex do
  def graph_from(hash)
    Elkrb::Graph::Graph.from_hash(hash)
  end

  describe ".build" do
    it "maps node ids to their node" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          { "id" => "a", "width" => 10, "height" => 10 },
          { "id" => "b", "width" => 10, "height" => 10 },
        ],
      )

      index = described_class.build(graph)

      expect(index.node("a").id).to eq("a")
      expect(index.node("b").id).to eq("b")
    end

    it "maps a port id to its owning node" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "a_p1" }],
          },
        ],
      )

      index = described_class.build(graph)

      expect(index.node("a_p1").id).to eq("a")
    end

    it "returns nil for an id not present at this level" do
      graph = graph_from("id" => "r", "children" => [])

      index = described_class.build(graph)

      expect(index.node("missing")).to be_nil
    end

    it "raises Elkrb::ValidationError on a duplicate node id" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          { "id" => "a", "width" => 10, "height" => 10 },
          { "id" => "a", "width" => 10, "height" => 10 },
        ],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /a/)
    end

    it "raises Elkrb::ValidationError on a duplicate port id" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "p1" }],
          },
          {
            "id" => "b",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "p1" }],
          },
        ],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /p1/)
    end

    it "raises Elkrb::ValidationError when a node id collides with " \
       "another node's port id" do
      # Node and port ids share one namespace at a level (D4) — this
      # proves that holds across kinds, not just node-node/port-port.
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "shared" }],
          },
          { "id" => "shared", "width" => 10, "height" => 10 },
        ],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /shared/)
    end

    it "raises Elkrb::ValidationError for a node without an id" do
      graph = Elkrb::Graph::Graph.new(
        children: [Elkrb::Graph::Node.new(width: 10, height: 10)],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /node without id/)
    end

    it "allows the same id to repeat at a different level" do
      parent = graph_from(
        "id" => "r",
        "children" => [{ "id" => "a", "width" => 10, "height" => 10 }],
      )
      child_graph = Elkrb::Graph::Graph.new(
        children: [Elkrb::Graph::Node.new(id: "a", width: 5, height: 5)],
      )

      expect(described_class.build(parent).node("a").width).to eq(10)
      expect(described_class.build(child_graph).node("a").width).to eq(5)
    end

    it "does not recurse into a node's own nested children" do
      # A version of NodeIndex that (incorrectly) walked node.children
      # would see the id "a" twice within ONE build call here and raise
      # a duplicate-id error; this proves it stays level-scoped.
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "children" => [
              { "id" => "a", "width" => 5, "height" => 5 },
            ],
          },
        ],
      )

      index = described_class.build(graph)

      expect(index.node("a").width).to eq(10)
    end
  end

  describe "#endpoint_nodes" do
    it "resolves a mix of node and port ids, dropping unresolved ones" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "a_p1" }],
          },
          { "id" => "b", "width" => 10, "height" => 10 },
        ],
      )
      index = described_class.build(graph)

      expect(index.endpoint_nodes(%w[a_p1 b missing]).map(&:id))
        .to eq(%w[a b])
    end

    it "returns an empty array for nil" do
      index = described_class.build(graph_from("id" => "r", "children" => []))

      expect(index.endpoint_nodes(nil)).to eq([])
    end
  end
end
