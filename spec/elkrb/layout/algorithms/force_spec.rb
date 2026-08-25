# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Force do
  describe "#layout" do
    it "pulls port-id-connected nodes together, not just node-id ones" do
      # Fixed positions plus repulsion: 0.0 isolate the attractive force
      # so a plain distance comparison proves it fired.
      graph = Elkrb::Graph::Graph.from_hash(
        "id" => "r",
        "children" => [
          {
            "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 10, "height" => 10,
            "ports" => [{ "id" => "a_out" }]
          },
          {
            "id" => "b", "x" => 100.0, "y" => 0.0, "width" => 10, "height" => 10,
            "ports" => [{ "id" => "b_in" }]
          },
        ],
        "edges" => [
          { "id" => "e", "sources" => ["a_out"], "targets" => ["b_in"] },
        ],
      )

      described_class.new(
        "iterations" => 1, "repulsion" => 0.0, "temperature" => 1000.0
      ).layout(graph)

      a = graph.children.find { |n| n.id == "a" }
      b = graph.children.find { |n| n.id == "b" }

      expect(b.x - a.x).to be < 100.0
    end
  end

  describe "#resolve_edge_positions (private)" do
    it "resolves port-id edge endpoints to their owning node's force slot" do
      node_a = Elkrb::Graph::Node.new(
        id: "a", x: 0.0, y: 0.0, width: 10, height: 10,
        ports: [Elkrb::Graph::Port.new(id: "a_out")],
      )
      node_b = Elkrb::Graph::Node.new(
        id: "b", x: 100.0, y: 0.0, width: 10, height: 10,
        ports: [Elkrb::Graph::Port.new(id: "b_in")],
      )
      graph = Elkrb::Graph::Graph.new(children: [node_a, node_b])
      graph.edges = [
        Elkrb::Graph::Edge.new(id: "e", sources: ["a_out"], targets: ["b_in"]),
      ]

      algorithm = described_class.new
      resolved = algorithm.send(:resolve_edge_positions, graph)

      expect(resolved).to eq([[0, 1]])
    end

    it "ignores a nested edge whose ids alias this level's ports" do
      # "x" and "y" name c's children AND a's and b's ports. Reading
      # c's own edge through the parent index made a and b look
      # adjacent.
      graph = Elkrb::Graph::Graph.from_hash(
        "id" => "r",
        "children" => [
          {
            "id" => "a", "width" => 10, "height" => 10,
            "ports" => [{ "id" => "x" }]
          },
          {
            "id" => "b", "width" => 10, "height" => 10,
            "ports" => [{ "id" => "y" }]
          },
          {
            "id" => "c", "width" => 10, "height" => 10,
            "children" => [
              { "id" => "x", "width" => 5, "height" => 5 },
              { "id" => "y", "width" => 5, "height" => 5 },
            ],
            "edges" => [
              { "id" => "inner", "sources" => ["x"], "targets" => ["y"] },
            ]
          },
        ],
        "edges" => [],
      )

      resolved = described_class.new.send(:resolve_edge_positions, graph)

      expect(resolved).to eq([])
    end
  end
end
