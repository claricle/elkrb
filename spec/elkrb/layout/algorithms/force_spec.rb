# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Force do
  describe "Fruchterman-Reingold layout" do
    let(:chain_json) do
      {
        id: "r",
        children: Array.new(30) do |i|
          { id: "n#{i}", width: 30, height: 30 }
        end,
        edges: Array.new(29) do |i|
          { id: "e#{i}", sources: ["n#{i}"], targets: ["n#{i + 1}"] }
        end,
      }.to_json
    end

    let(:five_nodes_json) do
      {
        id: "r",
        children: Array.new(5) do |i|
          { id: "n#{i}", width: 30, height: 30 }
        end,
        edges: [],
      }.to_json
    end

    it "separates a 30-node chain while keeping adjacent nodes close" do
      result = Elkrb.layout(JSON.parse(chain_json), algorithm: "force")
      by_id = result.children.to_h { |node| [node.id, node] }
      adjacent_distances = Array.new(29) do |i|
        left = by_id.fetch("n#{i}")
        right = by_id.fetch("n#{i + 1}")
        Math.hypot(left.x - right.x, left.y - right.y)
      end

      expect(result).to have_no_overlapping_siblings
      expect(adjacent_distances).to all(be_between(40.0, 200.0))
      expect(result.children.map(&:x).min).to eq(50.0)
      expect(result.children.map(&:y).min).to eq(50.0)
    end

    it "separates nodes that start at the same position" do
      graph = JSON.parse(five_nodes_json)
      graph["children"].each { |node| node.merge!("x" => 0, "y" => 0) }
      result = Elkrb.layout(graph, algorithm: "force")

      pairwise_distances = result.children.combination(2).map do |left, right|
        Math.hypot(left.x - right.x, left.y - right.y)
      end

      expect(pairwise_distances).to all(be > 10.0)
    end

    it "is deterministic" do
      expect do
        Elkrb.layout(JSON.parse(chain_json), algorithm: "force")
      end.to be_deterministic
    end

    it "returns only the seeded scatter when iterations are zero" do
      first = JSON.parse(five_nodes_json)
      first["layoutOptions"] = {
        "elk.force.iterations" => 0,
        "elk.force.repulsion" => 0,
        "elk.force.temperature" => 0,
      }
      second = JSON.parse(five_nodes_json)
      second["layoutOptions"] = {
        "elk.force.iterations" => 0,
        "elk.force.repulsion" => 1000,
        "elk.force.temperature" => 1000,
      }

      first_result = Elkrb.layout(first, algorithm: "force")
      second_result = Elkrb.layout(second, algorithm: "force")
      positions = first_result.children.map { |node| [node.x, node.y] }
      second_positions = second_result.children.map { |node| [node.x, node.y] }

      expect(positions).to eq(second_positions)
      expect(positions.uniq.length).to eq(5)
    end

    it "keeps zero-spacing sizeless graphs finite" do
      graph = {
        id: "r",
        layoutOptions: { "elk.spacing.nodeNode" => 0 },
        children: [{ id: "a" }, { id: "b" }],
        edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
      }

      result = Elkrb.layout(graph, algorithm: "force")

      coordinates = result.children.flat_map { |node| [node.x, node.y] }
      expect(coordinates).to all(be_finite)
    end
  end

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
        "iterations" => 1, "repulsion" => 0.0, "temperature" => 1000.0,
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
        ports: [Elkrb::Graph::Port.new(id: "a_out")]
      )
      node_b = Elkrb::Graph::Node.new(
        id: "b", x: 100.0, y: 0.0, width: 10, height: 10,
        ports: [Elkrb::Graph::Port.new(id: "b_in")]
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
