# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::CycleBreaker do
  describe "#break_cycles" do
    context "with two structurally identical back edges" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: [
            Elkrb::Graph::Node.new(id: "a", width: 10, height: 10),
            Elkrb::Graph::Node.new(id: "b", width: 10, height: 10),
          ],
          edges: [
            Elkrb::Graph::Edge.new(id: "e1", sources: ["a"], targets: ["b"]),
            Elkrb::Graph::Edge.new(id: "back", sources: ["b"], targets: ["a"]),
            Elkrb::Graph::Edge.new(id: "back", sources: ["b"], targets: ["a"]),
          ],
        )
      end

      # Edge carries value equality, so deduping the reversal list with
      # include? collapsed these two into one and left the second cycle live.
      it "reverses both of them" do
        described_class.new(graph, Elkrb::Layout::NodeIndex.build(graph)).break_cycles

        back_edges = graph.edges.select { |edge| edge.id == "back" }

        expect(back_edges.map(&:sources)).to all(eq(["a"]))
        expect(back_edges.map(&:targets)).to all(eq(["b"]))
      end

      it "leaves no cycle for the layer assigner to recurse on" do
        expect { Elkrb.layout(graph, algorithm: "layered") }.not_to raise_error
      end
    end

    context "with one edge closing a cycle through two targets at once" do
      # a -> b -> c -> x, and x -> [b, c]. Both b and c are still on the DFS
      # stack when x is reached, so the back edge gets flagged twice. Reversing
      # it twice swaps it straight back and leaves the cycle in place.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: %w[a b c x].map do |id|
            Elkrb::Graph::Node.new(id: id, width: 10, height: 10)
          end,
          edges: [
            Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
            Elkrb::Graph::Edge.new(id: "bc", sources: ["b"], targets: ["c"]),
            Elkrb::Graph::Edge.new(id: "cx", sources: ["c"], targets: ["x"]),
            Elkrb::Graph::Edge.new(
              id: "back", sources: ["x"], targets: %w[b c],
            ),
          ],
        )
      end

      it "reverses it once, not once per cyclic target" do
        reversed = described_class.new(graph, Elkrb::Layout::NodeIndex.build(graph)).break_cycles
        back = graph.edges.find { |edge| edge.id == "back" }

        expect(reversed.size).to eq(1)
        expect(back.sources).to eq(%w[b c])
        expect(back.targets).to eq(["x"])
      end
    end

    context "with a self-loop" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: [
            Elkrb::Graph::Node.new(id: "a", width: 10, height: 10),
          ],
          edges: [
            Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["a"]),
          ],
        )
      end

      it "leaves it alone" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed).to be_empty
        expect(graph.edges.first.targets).to eq(["a"])
      end
    end
  end
end
