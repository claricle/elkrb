# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::LayerAssigner do
  def real_layer_ids(layers)
    layers.map do |layer|
      layer.reject { |item| item.respond_to?(:dummy?) }.map(&:id)
    end
  end

  describe "#assign_layers" do
    # Through the real pipeline, CycleBreaker always resolves a cycle before
    # LayerAssigner ever sees it. This class is still directly instantiable
    # with no reversal set, though (its default is an empty
    # `Set.new.compare_by_identity`),
    # which is exactly the "incomplete reversal set" the class's own comment
    # names -- previously warned about, now checked here directly since
    # nothing else in the suite ever constructs this class by itself.
    #
    # Both the warned id and the exact layer values are pinned, not just
    # membership: walk_predecessors marks the ROOT active before it starts
    # walking its own predecessors, which is what makes "a" (not "c") the
    # id the cycle is caught on, and what gives "a" the highest layer.
    # Dropping that marking (confirmed by hand) still warns -- just about
    # "c" instead of "a" -- and shifts every layer by one, which a
    # same-elements-any-order assertion can't tell apart from the
    # original.
    it "warns on the root, not fully broken; treating as a root for this " \
       "branch, and gives it the deepest layer" do
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
      end.to output(
        "LayerAssigner: cycle through a not fully broken; treating as a " \
        "root for this branch\n",
      ).to_stderr

      expect(real_layer_ids(layers)).to eq(
        [["b"], ["c"], ["a"]],
      )
    end

    it "returns an empty layer list for a graph constructed with nil " \
       "children, instead of raising" do
      graph = Elkrb::Graph::Graph.new(id: "r").tap { |g| g.children = nil }

      layers = described_class.new(
        graph, Elkrb::Layout::NodeIndex.build(graph)
      ).assign_layers

      expect(layers).to eq([])
    end

    # Distinct from the nil case above: an empty-but-present `children`
    # takes the OTHER branch (`unless @graph.children` is false, since []
    # is truthy) and falls through to build_layers with no nodes at all,
    # which is the only path that exercises its `|| 0` fallback for a
    # graph with nothing to assign.
    it "returns a single empty layer for a graph with an empty children " \
       "list" do
      graph = Elkrb::Graph::Graph.new(id: "r", children: [])

      layers = described_class.new(
        graph, Elkrb::Layout::NodeIndex.build(graph)
      ).assign_layers

      expect(layers).to eq([[]])
    end

    it "resolves an edge's port endpoint to its owning node before " \
       "building predecessors" do
      # Every other example in this file wires edges directly between
      # node ids. This is the only one that routes through a port, which
      # forces endpoint_owner_id/oriented_endpoints to resolve it via
      # NodeIndex#owner -- skip that and "b_in" never matches the node id
      # "b" that `nodes` is keyed by, so the edge is silently dropped.
      graph = Elkrb::Graph::Graph.new(
        id: "r",
        children: [
          Elkrb::Graph::Node.new(id: "a", width: 10, height: 10),
          Elkrb::Graph::Node.new(
            id: "b", width: 10, height: 10,
            ports: [Elkrb::Graph::Port.new(id: "b_in")]
          ),
        ],
        edges: [
          Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b_in"]),
        ],
      )

      layers = described_class.new(
        graph, Elkrb::Layout::NodeIndex.build(graph)
      ).assign_layers

      expect(real_layer_ids(layers)).to eq([["a"], ["b"]])
    end

    it "assigns a node's layer from the longest predecessor path, not " \
       "simply the first one resolved" do
      # c's predecessors are built as [a, b] (declaration order of the
      # "ac" and "bc" edges). a resolves to layer 0 and b, built from a,
      # resolves to layer 1 -- so c must land one past the LATER of the
      # two (max), not one past whichever happened to finish first.
      graph = Elkrb::Graph::Graph.new(
        id: "r",
        children: %w[a b c].map { |id| Elkrb::Graph::Node.new(id: id) },
        edges: [
          Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
          Elkrb::Graph::Edge.new(id: "ac", sources: ["a"], targets: ["c"]),
          Elkrb::Graph::Edge.new(id: "bc", sources: ["b"], targets: ["c"]),
        ],
      )

      layers = described_class.new(
        graph, Elkrb::Layout::NodeIndex.build(graph)
      ).assign_layers

      expect(real_layer_ids(layers)).to eq(
        [["a"], ["b"], ["c"]],
      )
    end

    it "does not recompute a predecessor already resolved earlier in the " \
       "same walk" do
      # c is the shared predecessor of both a and b, which both feed d.
      # By the time b's branch looks at c, a's branch has already
      # resolved it -- predecessor_assigned?'s @node_layers check is what
      # stops that second branch from re-walking and re-assigning c.
      # Removing it (confirmed by hand) leaves the final layers
      # numerically unchanged -- the recomputation is idempotent -- so
      # only a call count on #assign_layer, not the layer values
      # themselves, can tell the two apart.
      graph = Elkrb::Graph::Graph.new(
        id: "r",
        children: %w[c a b d].map { |id| Elkrb::Graph::Node.new(id: id) },
        edges: [
          Elkrb::Graph::Edge.new(id: "ca", sources: ["c"], targets: ["a"]),
          Elkrb::Graph::Edge.new(id: "cb", sources: ["c"], targets: ["b"]),
          Elkrb::Graph::Edge.new(id: "ad", sources: ["a"], targets: ["d"]),
          Elkrb::Graph::Edge.new(id: "bd", sources: ["b"], targets: ["d"]),
        ],
      )
      assigner = described_class.new(
        graph, Elkrb::Layout::NodeIndex.build(graph)
      )
      allow(assigner).to receive(:assign_layer).and_call_original

      layers = nil
      expect { layers = assigner.assign_layers }.not_to output.to_stderr

      expect(assigner).to have_received(:assign_layer).exactly(4).times
      expect(real_layer_ids(layers)).to eq(
        [["c"], %w[a b], ["d"]],
      )
    end

    describe "#get_layer" do
      it "reads back the layer assigned to a node id, and nil for an " \
         "id that was never assigned" do
        graph = Elkrb::Graph::Graph.new(
          id: "r",
          children: %w[a b].map { |id| Elkrb::Graph::Node.new(id: id) },
          edges: [
            Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
          ],
        )
        assigner = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        )
        assigner.assign_layers

        expect(assigner.get_layer("a")).to eq(0)
        expect(assigner.get_layer("b")).to eq(1)
        expect(assigner.get_layer("ghost")).to be_nil
      end
    end

    describe "#oriented_endpoints (private contract)" do
      # Same shape as the usable_edge? contract test below: reachable only
      # in combination with usable_edge?'s OWN `source_id && target_id`
      # check, which independently excludes a half-resolved edge -- so
      # nothing here can tell apart "returns [nil, nil] for an edge
      # missing a source" from "returns [nil, target_id]" through
      # #assign_layers alone (confirmed by hand). Pinned directly since a
      # future caller of #oriented_endpoints need not re-run that check.
      it "returns [nil, nil] for an edge with no resolvable source" do
        graph = Elkrb::Graph::Graph.new(
          id: "r", children: [Elkrb::Graph::Node.new(id: "b")],
        )
        edge = Elkrb::Graph::Edge.new(
          id: "dangling", sources: [], targets: ["b"],
        )
        assigner = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        )

        expect(assigner.send(:oriented_endpoints, edge)).to eq([nil, nil])
      end
    end

    describe "#usable_edge? (private contract)" do
      # Reachable only in combination with the rest of the pipeline
      # elsewhere in this file, where an edge's target always happens to
      # be one of the current level's own nodes too -- so nothing else
      # here can tell apart "checks both endpoints" from "checks only the
      # source". Confirmed by hand: even a deliberately mismatched
      # graph/index pair (a target resolving outside `nodes`) produces
      # the same #assign_layers output either way, because nothing ever
      # walks into a predecessors entry whose key didn't itself already
      # pass this same check as a SOURCE elsewhere. The predicate's own
      # contract is still worth pinning directly, since a future caller
      # of #usable_edge? is not guaranteed to preserve that coincidence.
      it "rejects an edge whose target is not one of this level's nodes" do
        graph = Elkrb::Graph::Graph.new(
          id: "r", children: [Elkrb::Graph::Node.new(id: "a")],
        )
        assigner = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        )
        nodes = { "a" => graph.children.first }

        expect(
          assigner.send(:usable_edge?, "a", "ghost", nodes),
        ).to be(false)
      end
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

      expect(real_layer_ids(layers)).to eq(
        [["a"], ["b"], ["c"], ["d"]],
      )
    end
  end
end
