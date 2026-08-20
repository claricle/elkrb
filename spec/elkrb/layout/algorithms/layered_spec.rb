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
        .to raise_error(Elkrb::ValidationError, /a/)
    end

    it "does not stack-overflow on a two-port self-loop beside a real edge" do
      # Regression guard, not a red/green case on its own: a naive
      # version of Step 4 that resolves get_incoming_edges' target check
      # through the index but leaves self_loop_edge? comparing RAW ids
      # (sources.first == targets.first, "p1" != "p2") makes this edge
      # look like an incoming edge from node "a" to itself, and
      # calculate_layer recurses on "a" again before it is memoized ->
      # SystemStackError. Confirmed by reproducing that naive version.
      # Step 4 below fixes self_loop_edge? to compare resolved owners,
      # so this example is green from the first run of Step 6.
      graph = {
        id: "r",
        children: [
          {
            id: "a", width: 10, height: 10,
            ports: [{ id: "p1" }, { id: "p2" }],
          },
          { id: "b", width: 10, height: 10 },
        ],
        edges: [
          { id: "loop", sources: ["p1"], targets: ["p2"] },
          { id: "real", sources: ["a"], targets: ["b"] },
        ],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .not_to raise_error
    end

    it "does not stack-overflow on a hyperedge mixing a self-referencing " \
       "target and a real child" do
      # Codex diff-review finding (round 2): CycleBreaker's dfs used
      # `edge.targets.first` unconditionally; for this edge the first
      # target ("ap") resolves back to the source node "a" itself, so
      # dfs treated a's own in-progress DFS frame as a cycle and
      # reversed the edge, corrupting it before LayerAssigner ever saw
      # it -> SystemStackError there. Confirmed against the pre-fix
      # code, and confirmed this exact graph does NOT raise on
      # origin/v2 (port-id blindness there means the edge is invisible
      # to cycle-breaking entirely, so no crash) -- a genuine
      # regression this diff must not ship.
      graph = {
        id: "r",
        children: [
          {
            id: "a", width: 10, height: 10,
            ports: [{ id: "ap" }],
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
      # Codex diff-review finding (round 3): [a, b] -> a is genuine
      # incoming traffic to "a" from "b" (incoming_to? correctly counts
      # it), but calculate_layer picked edge.sources.first unconditionally
      # -- for this edge that is "a" itself, so it recursed on "a" again
      # before memoizing it. Confirmed against the pre-fix code.
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

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .not_to raise_error
    end
  end
end
