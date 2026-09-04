# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::LayerAssigner do
  describe "#assign_layers" do
    # Through the real pipeline, CycleBreaker always resolves a cycle before
    # LayerAssigner ever sees it. This class is still directly instantiable
    # with no reversal set, though (default `reversed_edge_ids: Set.new`),
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

      layers = nil
      expect do
        layers = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).assign_layers
      end.to output(/cycle through .* not fully broken/).to_stderr

      expect(layers.flatten.map(&:id)).to contain_exactly("a", "b", "c")
    end
  end
end
