# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::LayeredAlgorithm do
  describe "#layout" do
    it "lays out edges that reference port ids into separate layers" do
      graph = JSON.parse(File.read("spec/fixtures/elkjs_bug7_complex.json"))

      result = Elkrb.layout(graph, algorithm: "layered")

      expect(result.children.map(&:y).uniq.size).to be > 1
    end

    it "raises Elkrb::ValidationError for a duplicate node id" do
      graph = {
        id: "r",
        children: [
          { id: "a", width: 10, height: 10 },
          { id: "a", width: 10, height: 10 },
        ],
        edges: [],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::ValidationError, /duplicate id: a/)
    end

    it "does not stack-overflow on a two-port self-loop beside a real edge" do
      # Regression guard: resolving get_incoming_edges' target check
      # through the index while leaving self_loop_edge? comparing RAW
      # ids (sources.first == targets.first, "p1" != "p2") makes this
      # edge look like an incoming edge from node "a" to itself, and
      # calculate_layer recurses on "a" again before it is memoized ->
      # SystemStackError. Confirmed by reproducing that version;
      # incoming_to? below compares resolved owners instead, so this
      # example is green.
      graph = {
        id: "r",
        children: [
          {
            id: "a", width: 10, height: 10,
            ports: [{ id: "p1" }, { id: "p2" }]
          },
          { id: "b", width: 10, height: 10 },
        ],
        edges: [
          { id: "loop", sources: ["p1"], targets: ["p2"] },
          { id: "real", sources: ["a"], targets: ["b"] },
        ],
      }

      result = Elkrb.layout(graph, algorithm: "layered")
      a = result.children.find { |n| n.id == "a" }
      b = result.children.find { |n| n.id == "b" }

      # Pins S7's interim behaviour; S8 replaces with hyperedge raise.
      expect(b.y).to be > a.y
    end

    it "preserves cyclic edge directions and assigns three layers" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [
          { id: "ab", sources: ["a"], targets: ["b"] },
          { id: "bc", sources: ["b"], targets: ["c"] },
          { id: "ca", sources: ["c"], targets: ["a"] },
        ],
      }

      result = Elkrb.layout(graph, algorithm: "layered")

      expect(result.edges.map { |edge| [edge.sources, edge.targets] }).to eq(
        [
          [["a"], ["b"]],
          [["b"], ["c"]],
          [["c"], ["a"]],
        ],
      )
      expect(result.edges).to all(
        satisfy { |edge| !edge.properties&.key?("reversed") },
      )
      expect(result.children.map(&:y).uniq.size).to eq(3)
    end

    it "raises for a hyperedge with multiple sources" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [{ id: "e", sources: %w[a b], targets: ["c"] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(
          Elkrb::UnsupportedConfigurationException,
          "layered does not support hyperedges (edge e)",
        )
    end

    it "raises for a hyperedge with multiple targets" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [{ id: "e", sources: ["a"], targets: %w[b c] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::UnsupportedConfigurationException)
    end

    it "raises for a duplicate edge id" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [
          { id: "e", sources: ["a"], targets: ["b"] },
          { id: "e", sources: ["b"], targets: ["c"] },
        ],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::ValidationError, /duplicate edge id: e/)
    end

    it "raises for missing or empty endpoints before the empty fast path" do
      graph = {
        id: "r",
        children: [],
        edges: [{ id: "missing", sources: [], targets: ["a"] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::UnsupportedConfigurationException)
    end

    it "validates edges when children are omitted" do
      graph = {
        id: "r",
        edges: [{ id: "e", sources: ["a"], targets: ["b", "c"] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::UnsupportedConfigurationException)
    end

    it "validates a leaf child's edges in the parent index" do
      graph = {
        id: "r",
        children: [
          {
            id: "leaf", width: 10, height: 10,
            edges: [{ id: "nested", sources: ["a"], targets: ["b", "c"] }]
          },
        ],
        edges: [],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::UnsupportedConfigurationException)
    end

    it "lays out a 5000-node chain without overflowing the stack" do
      count = 5000
      graph = {
        id: "r",
        children: (0...count).map do |i|
          { id: "n#{i}", width: 1, height: 1 }
        end,
        edges: (0...(count - 1)).map do |i|
          { id: "e#{i}", sources: ["n#{i}"], targets: ["n#{i + 1}"] }
        end,
      }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Elkrb.layout(graph, algorithm: "layered")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(result.children.size).to eq(count)
      expect(result.children.map(&:y).uniq.size).to eq(count)
      expect(elapsed).to be < 5
    end

    it "leaves a nested edge whose ids alias this level's ports alone" do
      # "x" and "y" name c's children AND a's and b's ports. Resolving
      # c's own edge through the parent index aliased it onto a and b,
      # so walking b -> c reached c with b still on the dfs stack and
      # reversed an acyclic nested edge into y -> x.
      graph = cross_level_graph(
        edges: [{ id: "bc", sources: ["b"], targets: ["c"] }],
      )

      result = Elkrb.layout(graph, algorithm: "layered")
      inner = result.children.find { |n| n.id == "c" }.edges.first

      expect(inner.sources).to eq(["x"])
      expect(inner.targets).to eq(["y"])
    end

    it "does not layer this level by a nested edge's aliased ids" do
      # Nothing connects a, b and c at the top level, so all three are
      # roots. The aliased nested edge made b a layer of its own.
      result = Elkrb.layout(cross_level_graph, algorithm: "layered")

      expect(result.children.map(&:y).uniq.size).to eq(1)
    end
  end

  def cross_level_graph(edges: [])
    {
      id: "r",
      children: [
        { id: "a", width: 10, height: 10, ports: [{ id: "x" }] },
        { id: "b", width: 10, height: 10, ports: [{ id: "y" }] },
        {
          id: "c", width: 10, height: 10,
          children: [
            { id: "x", width: 5, height: 5 },
            { id: "y", width: 5, height: 5 },
          ],
          edges: [{ id: "inner", sources: ["x"], targets: ["y"] }]
        },
      ],
      edges: edges,
    }
  end
end
