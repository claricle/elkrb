# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::LayerAssigner do
  describe "#assign_layers" do
    # Through the real pipeline, CycleBreaker always resolves a cycle before
    # LayerAssigner ever sees it. This class is still directly instantiable
    # with no reversal set, though (its default is an empty
    # `Set.new.compare_by_identity`),
    # which is exactly the "incomplete reversal set" the class's own comment
    # names -- previously warned about, now checked here directly since
    # nothing else in the suite ever constructs this class by itself.
    it "warns and treats the cycle-closing edge as a root, rather than " \
       "looping forever" do
      graph = Elkrb::Graph::Graph.new(
        id: "r",
        children: %w[a b c].map { |id| Elkrb::Graph::Node.new(id: id) },
        edges: [
          Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
          Elkrb::Graph::Edge.new(id: "bc", sources: ["b"], targets: ["c"]),
          Elkrb::Graph::Edge.new(id: "ca", sources: ["c"], targets: ["a"]),
        ],
      )

      # Anchored on "LayerAssigner:", not just "cycle through". The message
      # this replaced was "Layered: cycle through ... not fully broken
      # (hyperedge)", which a looser pattern also matches -- so the example
      # stayed green against the pre-change code and pinned nothing.
      layers = nil
      expect do
        layers = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).assign_layers
      end.to output(
        /LayerAssigner: cycle through \w+ not fully broken/,
      ).to_stderr

      expect(layers.flatten.map(&:id)).to contain_exactly("a", "b", "c")
    end

    # Every other example in this file declares `children` in an order that
    # already matches the DFS topology, so a predecessor is always resolved
    # (@node_layers.key?) before anything checks whether it's :active --
    # the false branch of predecessor_assigned? (not yet visited by an
    # earlier root) is exercised only by accident of declaration order,
    # never pinned. Declaring the chain in reverse forces that branch: `d`
    # walks into `c`, `b`, `a` -- none of which any earlier root has
    # resolved yet -- before any of them is :active.
    it "assigns an acyclic chain's layers correctly even when children are " \
       "declared in reverse topological order" do
      graph = Elkrb::Graph::Graph.new(
        id: "r",
        children: %w[d c b a].map { |id| Elkrb::Graph::Node.new(id: id) },
        edges: [
          Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
          Elkrb::Graph::Edge.new(id: "bc", sources: ["b"], targets: ["c"]),
          Elkrb::Graph::Edge.new(id: "cd", sources: ["c"], targets: ["d"]),
        ],
      )

      layers = described_class.new(
        graph, Elkrb::Layout::NodeIndex.build(graph)
      ).assign_layers

      expect(layers.map { |layer| layer.map(&:id) }).to eq(
        [["a"], ["b"], ["c"], ["d"]],
      )
    end
  end
end
