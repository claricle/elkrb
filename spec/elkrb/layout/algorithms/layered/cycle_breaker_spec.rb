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

      it "flags both identical back edges without mutating either" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        back_edges = graph.edges.select { |edge| edge.id == "back" }

        # These two are `==` to each other: lutaml-model gives the graph
        # classes VALUE equality, so a plain Set would hold ONE of them and
        # answer `include?` true for any look-alike. The reversal set
        # compares by identity, so it keeps both apart and holds both.
        expect(back_edges.first).to eq(back_edges.last)
        expect(reversed.to_a).to contain_exactly(
          be(back_edges.first), be(back_edges.last)
        )

        expect(back_edges.map(&:sources)).to all(eq(["b"]))
        expect(back_edges.map(&:targets)).to all(eq(["a"]))
      end

      it "does not mutate edge properties while finding reversals" do
        graph.edges.each { |edge| edge.properties = { "keep" => true } }

        described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(graph.edges.map(&:properties)).to all(eq("keep" => true))
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

      it "returns one reversal without changing the hyperedge" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles
        back = graph.edges.find { |edge| edge.id == "back" }

        expect(reversed.to_a).to contain_exactly(be(back))
        expect(back.sources).to eq(["x"])
        expect(back.targets).to eq(%w[b c])
      end
    end

    context "with a cycle closing through a later target" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: %w[a b c d x].map do |id|
            Elkrb::Graph::Node.new(id: id, width: 10, height: 10)
          end,
          edges: [
            Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
            Elkrb::Graph::Edge.new(id: "bc", sources: ["b"], targets: ["c"]),
            Elkrb::Graph::Edge.new(id: "cx", sources: ["c"], targets: ["x"]),
            Elkrb::Graph::Edge.new(
              id: "back", sources: ["x"], targets: %w[d c],
            ),
          ],
        )
      end

      it "returns the reversal for the later target" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed.map(&:id)).to contain_exactly("back")
      end
    end

    context "with a node whose own two forward edges reach either side of " \
            "a 2-cycle" do
      # a's own adjacency is declared [a->b, a->c]. walk_from starts
      # scanning a NODE's adjacency at its first entry -- nothing else in
      # this file has a node with two outgoing edges feeding into the
      # same later cycle, so starting that per-node scan at the wrong
      # offset (found by comparing against a from-scratch reimplementation
      # across 2000 random graphs; this is the smallest mismatching one)
      # still finds *a* back edge, just the wrong one.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: %w[a b c].map do |id|
            Elkrb::Graph::Node.new(id: id, width: 10, height: 10)
          end,
          edges: [
            Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
            Elkrb::Graph::Edge.new(id: "ac", sources: ["a"], targets: ["c"]),
            Elkrb::Graph::Edge.new(id: "bc", sources: ["b"], targets: ["c"]),
            Elkrb::Graph::Edge.new(id: "cb", sources: ["c"], targets: ["b"]),
          ],
        )
      end

      it "reverses cb, not bc" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed.map(&:id)).to contain_exactly("cb")
      end
    end

    context "with a cycle closing through a later source" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: %w[a b c].map do |id|
            Elkrb::Graph::Node.new(id: id, width: 10, height: 10)
          end,
          edges: [
            Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
            Elkrb::Graph::Edge.new(
              id: "back", sources: %w[c b], targets: ["a"],
            ),
          ],
        )
      end

      it "returns the reversal for the later source" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed.map(&:id)).to contain_exactly("back")
      end
    end

    # This context, plus the identical-back-edges case at the top of the
    # file, is what distinguishes "collects every back edge" from
    # "collects only the first" -- nothing else in this file pins that.
    context "with two independent cycles" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: %w[a b c d].map do |id|
            Elkrb::Graph::Node.new(id: id, width: 10, height: 10)
          end,
          edges: [
            Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b"]),
            Elkrb::Graph::Edge.new(id: "ba", sources: ["b"], targets: ["a"]),
            Elkrb::Graph::Edge.new(id: "cd", sources: ["c"], targets: ["d"]),
            Elkrb::Graph::Edge.new(id: "dc", sources: ["d"], targets: ["c"]),
          ],
        )
      end

      it "reverses a back edge from each one, not just the first" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed.map(&:id)).to contain_exactly("ba", "dc")
      end

      # The guard distinguishes "walk each connected component once" from
      # "walk it once per node in it" -- both give the SAME reversed set
      # here, because re-walking an already-:complete node can only ever
      # re-reach other already-:complete nodes (colors is never reset
      # outside walk_from, and every edge target this component can reach
      # was already visited in its first pass), so nothing about the
      # mutations' end result (the reversed edges) can tell the two apart.
      # Only a call count on the private per-root entry point can.
      it "walks each connected component exactly once, not once per node " \
         "in it" do
        breaker = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        )
        allow(breaker).to receive(:walk_from).and_call_original

        breaker.break_cycles

        expect(breaker).to have_received(:walk_from).exactly(2).times
      end

      it "lays both cycles out in edge order without warning" do
        laid_out = nil
        expect do
          laid_out = Elkrb.layout(graph, algorithm: "layered")
        end.not_to output.to_stderr

        x = laid_out.children.to_h { |node| [node.id, node.x] }
        expect(x["a"]).to be < x["b"]
        expect(x["c"]).to be < x["d"]
      end
    end

    context "when constructed directly with a nil children list" do
      # assign_layers goes through Algorithms::Layered#layout_flat first,
      # which already returns early for a nil/empty `children` (layered.rb)
      # -- CycleBreaker is never reached that way in the real pipeline. But
      # nothing stops a direct caller (as every spec in this file already
      # is one) from constructing it with `children` explicitly nil, and
      # the class carries its own guard for exactly that. Without this
      # example nothing ever drove @graph.children to nil, so the guard's
      # branch was never taken either way.
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "r").tap { |g| g.children = nil }
      end

      it "returns no reversals instead of raising" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed).to be_empty
      end
    end

    context "with a cycle whose forward edge leaves through a source port" do
      # The port-routed fixture below this one only resolves a port on the
      # TARGET side. #outgoing_edges resolves sources through the exact
      # same #endpoint_owner_ids call, but nothing else in this file ever
      # gives it a source port to resolve -- skip that resolution and the
      # adjacency entry lands under the port id instead of "a", which
      # walk_from's root ids (plain node ids from @graph.children) can
      # never match, so the cycle silently goes undetected.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: [
            Elkrb::Graph::Node.new(
              id: "a", width: 10, height: 10,
              ports: [Elkrb::Graph::Port.new(id: "a_out")]
            ),
            Elkrb::Graph::Node.new(id: "b", width: 10, height: 10),
          ],
          edges: [
            Elkrb::Graph::Edge.new(id: "ab", sources: ["a_out"],
                                   targets: ["b"]),
            Elkrb::Graph::Edge.new(id: "back", sources: ["b"], targets: ["a"]),
          ],
        )
      end

      it "still finds the back edge by the source's owning node, not by " \
         "the port id" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed.map(&:id)).to contain_exactly("back")
      end
    end

    context "with a hyperedge whose first target is its own source" do
      # #outgoing_edges skips a target that equals the source with `next`,
      # which only drops THAT one target and keeps scanning the rest of
      # `target_ids`. Every other hyperedge fixture in this file (the
      # "closing through two targets at once" context above) has no
      # self-matching target at all, so nothing else here can tell apart
      # "skip just this target" from "stop scanning targets entirely" --
      # the latter (`break` in place of `next`) would silently drop every
      # target declared AFTER the self-match, including the one this
      # cycle needs.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: [
            Elkrb::Graph::Node.new(
              id: "a", width: 10, height: 10,
              ports: [Elkrb::Graph::Port.new(id: "a_self")]
            ),
            Elkrb::Graph::Node.new(id: "b", width: 10, height: 10),
          ],
          edges: [
            Elkrb::Graph::Edge.new(
              id: "ab", sources: ["a"], targets: %w[a_self b],
            ),
            Elkrb::Graph::Edge.new(id: "back", sources: ["b"], targets: ["a"]),
          ],
        )
      end

      it "still reaches the target declared after the self-matching one" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed.map(&:id)).to contain_exactly("back")
      end
    end

    context "with a back edge expressed through ports" do
      # Every other fixture in this file addresses nodes directly. This is
      # the only one routed through a port id, which forces
      # endpoint_owner_ids to resolve the port to its owning node before
      # the adjacency is built -- skip that resolution and the port id
      # never matches any node id walk_from colors, so the cycle goes
      # undetected.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "r",
          children: [
            Elkrb::Graph::Node.new(
              id: "a", width: 10, height: 10,
              ports: [Elkrb::Graph::Port.new(id: "a_in")]
            ),
            Elkrb::Graph::Node.new(
              id: "b", width: 10, height: 10,
              ports: [Elkrb::Graph::Port.new(id: "b_in")]
            ),
          ],
          edges: [
            Elkrb::Graph::Edge.new(id: "ab", sources: ["a"], targets: ["b_in"]),
            Elkrb::Graph::Edge.new(
              id: "back", sources: ["b"], targets: ["a_in"],
            ),
          ],
        )
      end

      it "still finds the back edge by owning node, not by port id" do
        reversed = described_class.new(
          graph, Elkrb::Layout::NodeIndex.build(graph)
        ).break_cycles

        expect(reversed.map(&:id)).to contain_exactly("back")
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

    describe "#endpoint_owner_ids (private contract)" do
      # Every edge fixture elsewhere in this file addresses a node through
      # at most one port, so the cross product in #outgoing_edges never
      # sees the SAME owner twice for one edge side -- nothing else here
      # can tell apart "dedupes owner ids" from "returns one entry per
      # endpoint". Two ports on one node forces that duplication.
      it "dedupes two endpoints that resolve to the same owning node" do
        graph = Elkrb::Graph::Graph.new(
          id: "r",
          children: [
            Elkrb::Graph::Node.new(
              id: "a", width: 10, height: 10,
              ports: [
                Elkrb::Graph::Port.new(id: "a1"),
                Elkrb::Graph::Port.new(id: "a2"),
              ]
            ),
          ],
        )
        breaker = described_class.new(graph, Elkrb::Layout::NodeIndex.build(graph))

        expect(breaker.send(:endpoint_owner_ids, %w[a1 a2])).to eq(["a"])
      end

      # An id with no owner in the index (not one of this level's nodes or
      # ports) resolves to a nil owner. #filter_map drops it; plain #map
      # would keep the nil and hand outgoing_edges a bogus adjacency
      # target. Nothing else in this file passes an unresolvable id.
      it "drops an id that resolves to no owner, instead of keeping a nil" do
        graph = Elkrb::Graph::Graph.new(
          id: "r",
          children: [Elkrb::Graph::Node.new(id: "a", width: 10, height: 10)],
        )
        breaker = described_class.new(graph, Elkrb::Layout::NodeIndex.build(graph))

        expect(breaker.send(:endpoint_owner_ids, ["ghost"])).to eq([])
      end

      it "returns an empty list for a nil endpoints argument, instead of " \
         "raising" do
        graph = Elkrb::Graph::Graph.new(id: "r", children: [])
        breaker = described_class.new(graph, Elkrb::Layout::NodeIndex.build(graph))

        expect(breaker.send(:endpoint_owner_ids, nil)).to eq([])
      end
    end
  end
end
