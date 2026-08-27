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

    it "does not stack-overflow on a hyperedge mixing a self-referencing " \
       "target and a real child" do
      # Regression guard: CycleBreaker's dfs used `edge.targets.first`
      # unconditionally; for this edge the first target ("ap") resolves
      # back to the source node "a" itself, so dfs treated a's own
      # in-progress DFS frame as a cycle and reversed the edge,
      # corrupting it before LayerAssigner ever saw it ->
      # SystemStackError there. Confirmed against that version, and
      # confirmed this exact graph does NOT raise on origin/v2
      # (port-id blindness there means the edge is invisible to
      # cycle-breaking entirely, so no crash) -- a genuine regression
      # this diff must not ship.
      graph = {
        id: "r",
        children: [
          {
            id: "a", width: 10, height: 10,
            ports: [{ id: "ap" }]
          },
          { id: "b", width: 10, height: 10 },
        ],
        edges: [
          { id: "e", sources: ["a"], targets: %w[ap b] },
        ],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .not_to raise_error
    end

    it "does not stack-overflow on a hyperedge whose first source is " \
       "the target itself" do
      # Regression guard: [a, b] -> a is genuine incoming traffic to
      # "a" from "b" (incoming_to? correctly counts it), but
      # calculate_layer picked edge.sources.first unconditionally --
      # for this edge that is "a" itself, so it recursed on "a" again
      # before memoizing it. first_other_source below picks the other
      # one instead.
      graph = {
        id: "r",
        children: [
          { id: "a", width: 10, height: 10 },
          { id: "b", width: 10, height: 10 },
        ],
        edges: [
          { id: "e", sources: %w[a b], targets: ["a"] },
        ],
      }

      result = Elkrb.layout(graph, algorithm: "layered")

      a = result.children.find { |n| n.id == "a" }
      b = result.children.find { |n| n.id == "b" }

      # Pins S7's interim behaviour; S8 replaces with hyperedge raise.
      expect(a.y).to be > b.y
    end

    it "does not stack-overflow on a cycle closing through a hyperedge's " \
       "later target" do
      # Regression guard: a's hyperedge fans out to three ports, and
      # the real a -> c -> a cycle closes through the LAST of them (c's
      # edge back to a's port). A dfs that stopped at the first
      # non-self target never visited c during cycle-breaking, left the
      # cycle unbroken, and calculate_layer then recursed between a and
      # c forever. Confirmed against that version, and confirmed this
      # exact graph does NOT raise on origin/v2 (port ids are invisible
      # there, so the cycle is invisible too -- a genuine regression
      # this diff must not ship). dfs now walks every resolved target,
      # so CycleBreaker reverses the closing edge itself.
      graph = {
        id: "r",
        children: [
          {
            id: "a", width: 10, height: 10,
            ports: [{ id: "ap" }]
          },
          {
            id: "b", width: 10, height: 10,
            ports: [{ id: "bp" }]
          },
          {
            id: "c", width: 10, height: 10,
            ports: [{ id: "cp" }]
          },
        ],
        edges: [
          { id: "e1", sources: ["a"], targets: %w[ap bp cp] },
          { id: "e2", sources: ["cp"], targets: ["ap"] },
        ],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .not_to raise_error
    end

    it "breaks a cycle that closes through a hyperedge's later target" do
      # Following only the first non-self target left this cycle for
      # LayerAssigner's re-entrancy guard to absorb, which warns on
      # stderr. Walking every target breaks it in phase 1 instead.
      graph = {
        id: "r",
        children: %w[a b c].map { |i| { id: i, width: 10, height: 10 } },
        edges: [
          { id: "e1", sources: ["a"], targets: %w[b c] },
          { id: "e2", sources: ["c"], targets: ["a"] },
        ],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .not_to output.to_stderr
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
