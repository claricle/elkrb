# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Stress do
  describe "#calculate_distances (private)" do
    it "resolves port-id edge endpoints to their owning node's row/column" do
      node_a = Elkrb::Graph::Node.new(
        id: "a", width: 10, height: 10,
        ports: [Elkrb::Graph::Port.new(id: "a_out")],
      )
      node_b = Elkrb::Graph::Node.new(
        id: "b", width: 10, height: 10,
        ports: [Elkrb::Graph::Port.new(id: "b_in")],
      )
      node_c = Elkrb::Graph::Node.new(id: "c", width: 10, height: 10)
      graph = Elkrb::Graph::Graph.new(children: [node_a, node_b, node_c])
      graph.edges = [
        Elkrb::Graph::Edge.new(id: "e", sources: ["a_out"], targets: ["b_in"]),
      ]

      distances = described_class.new.send(:calculate_distances, graph)

      expect(distances[0][1]).to eq(1.0)
      expect(distances[1][0]).to eq(1.0)
      expect(distances[0][2]).to eq(Float::INFINITY)
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

      distances = described_class.new.send(:calculate_distances, graph)

      expect(distances[0][1]).to eq(Float::INFINITY)
    end
  end
end
