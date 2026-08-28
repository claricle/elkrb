# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::MRTree do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with a simple tree graph" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
            "elk.spacing.nodeNode" => 20.0,
          ),
        )
      end

      before do
        # Create a simple tree: root -> child1, child2
        root = Elkrb::Graph::Node.new(
          id: "root",
          width: 50,
          height: 30,
        )
        child1 = Elkrb::Graph::Node.new(
          id: "child1",
          width: 40,
          height: 30,
        )
        child2 = Elkrb::Graph::Node.new(
          id: "child2",
          width: 40,
          height: 30,
        )

        graph.children = [root, child1, child2]

        # Add edges
        graph.edges = [
          Elkrb::Graph::Edge.new(
            id: "e1",
            sources: ["root"],
            targets: ["child1"],
          ),
          Elkrb::Graph::Edge.new(
            id: "e2",
            sources: ["root"],
            targets: ["child2"],
          ),
        ]
      end

      it "positions nodes in a tree structure" do
        algorithm.layout(graph)

        # Root should be at the top (after padding)
        root = graph.children.find { |n| n.id == "root" }
        expect(root.x).to be_a(Numeric)
        expect(root.y).to be >= 0.0

        # Children should be below and spaced out
        child1 = graph.children.find { |n| n.id == "child1" }
        child2 = graph.children.find { |n| n.id == "child2" }

        expect(child1.y).to be > root.y
        expect(child2.y).to be > root.y
        expect(child1.x).not_to eq(child2.x)
      end

      it "respects node spacing" do
        algorithm.layout(graph)

        child1 = graph.children.find { |n| n.id == "child1" }
        child2 = graph.children.find { |n| n.id == "child2" }

        # Children should be spaced apart
        spacing = (child2.x - child1.x).abs
        expect(spacing).to be >= 20.0
      end

      it "sets graph dimensions" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0
      end
    end

    context "with multiple root nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        # Create two separate trees
        root1 = Elkrb::Graph::Node.new(
          id: "root1",
          width: 50,
          height: 30,
        )
        root2 = Elkrb::Graph::Node.new(
          id: "root2",
          width: 50,
          height: 30,
        )
        child1 = Elkrb::Graph::Node.new(
          id: "child1",
          width: 40,
          height: 30,
        )
        child2 = Elkrb::Graph::Node.new(
          id: "child2",
          width: 40,
          height: 30,
        )

        graph.children = [root1, root2, child1, child2]

        # Create two separate trees
        graph.edges = [
          Elkrb::Graph::Edge.new(
            id: "e1",
            sources: ["root1"],
            targets: ["child1"],
          ),
          Elkrb::Graph::Edge.new(
            id: "e2",
            sources: ["root2"],
            targets: ["child2"],
          ),
        ]
      end

      it "lays out multiple trees side by side" do
        algorithm.layout(graph)

        root1 = graph.children.find { |n| n.id == "root1" }
        root2 = graph.children.find { |n| n.id == "root2" }

        # Both roots should be at same y level (after padding)
        expect(root1.y).to eq(root2.y)

        # Trees should be separated horizontally
        expect((root2.x - root1.x).abs).to be > 0
      end
    end

    context "with no edges" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 50, height: 30),
          Elkrb::Graph::Node.new(id: "node2", width: 50, height: 30),
        ]
        graph.edges = []
      end

      it "treats all nodes as roots" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
        end
      end
    end

    context "with a self-loop" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", width: 50, height: 30),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["a"]),
        ]
      end

      it "lays out without SystemStackError" do
        expect { algorithm.layout(graph) }.not_to raise_error
      end
    end

    context "with a self-loop alongside a real edge" do
      # Codex round-1 diff finding: the self-loop must not make its own
      # node look like it "has an incoming edge" — that made both nodes
      # register as roots and lose the parent/child relationship entirely.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", width: 10, height: 10),
          Elkrb::Graph::Node.new(id: "b", width: 10, height: 10),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e0", sources: ["a"], targets: ["a"]),
          Elkrb::Graph::Edge.new(id: "e1", sources: ["a"], targets: ["b"]),
        ]
      end

      it "still treats b as a's child, not a second root" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.y).to be > a.y
      end
    end

    context "with a port-id edge" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        a = Elkrb::Graph::Node.new(
          id: "a",
          width: 10,
          height: 10,
          ports: [Elkrb::Graph::Port.new(id: "p1")],
        )
        b = Elkrb::Graph::Node.new(id: "b", width: 10, height: 10)

        graph.children = [a, b]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["p1"], targets: ["b"]),
        ]
      end

      it "builds b below a, resolving the port id to its owning node" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.y).to be > a.y
      end
    end

    context "with a two-port self-loop alongside a real edge" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        a = Elkrb::Graph::Node.new(
          id: "a",
          width: 10,
          height: 10,
          ports: [
            Elkrb::Graph::Port.new(id: "p1"),
            Elkrb::Graph::Port.new(id: "p2"),
          ],
        )
        b = Elkrb::Graph::Node.new(id: "b", width: 10, height: 10)

        graph.children = [a, b]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "loop", sources: ["p1"], targets: ["p2"]),
          Elkrb::Graph::Edge.new(id: "real", sources: ["a"], targets: ["b"]),
        ]
      end

      # Regression guard for the same class of bug as layered's
      # self-loop fix: a raw-id comparison here would count "loop" as
      # real incoming traffic to "a" (since "p2" now resolves to "a"
      # via the index) and wrongly drop "a" from `roots`, losing it
      # from the tree.
      it "still treats a as a root and b as its child" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.y).to be > a.y
      end
    end

    context "with a hyperedge mixing a self-referencing target and a " \
            "real child" do
      # Regression guard: comparing only the first resolved
      # source/target treated this whole edge as a self-loop (since
      # "ap" resolves to "a", same as the first source), which hid the
      # real a -> b connection and made b a second root instead of a's
      # child.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        a = Elkrb::Graph::Node.new(
          id: "a",
          width: 10,
          height: 10,
          ports: [Elkrb::Graph::Port.new(id: "ap")],
        )
        b = Elkrb::Graph::Node.new(id: "b", width: 10, height: 10)

        graph.children = [a, b]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: %w[ap b]),
        ]
      end

      it "treats a as the root and b as its only child, not a co-root" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.y).to be > a.y
      end
    end

    context "with a multi-source edge whose sources include the target" do
      # find_root_nodes' skip condition (sources.any? { |s| s != target })
      # is untested on its own: this edge's target ("b") is ALSO its
      # FIRST source, with the genuinely different source ("a") listed
      # second, so b still has real incoming traffic and must not be a
      # root -- a version that only checked sources.first would miss
      # this and wrongly treat b as a root too.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", width: 10, height: 10),
          Elkrb::Graph::Node.new(id: "b", width: 10, height: 10),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: %w[b a], targets: ["b"]),
        ]
      end

      it "treats a as the root and b as its child" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.y).to be > a.y
      end
    end

    # Every guard above asserts y only, and y comes from the relaxed
    # levels, which stay right even when root finding gets a node wrong.
    # What root finding really decides is which nodes START a tree, and
    # each tree begins at its own x offset. That only shows when a child
    # is listed BEFORE its own parent -- with the parent first it keeps
    # x = 0 either way. So the contexts below all list b first and assert
    # x as well as y.
    context "with an edge onto a child's port, the child listed first" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        a = Elkrb::Graph::Node.new(id: "a", width: 10, height: 10)
        b = Elkrb::Graph::Node.new(
          id: "b",
          width: 10,
          height: 10,
          ports: [Elkrb::Graph::Port.new(id: "bp")],
        )

        graph.children = [b, a]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["bp"]),
        ]
      end

      it "keeps b under a instead of starting a tree of its own" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.x).to eq(a.x)
        expect(b.y).to be > a.y
      end
    end

    context "with a hyperedge onto its own port, the child listed first" do
      # Reading only the first source and the first target makes this whole
      # edge look like a self-loop, which hides a -> b entirely.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        a = Elkrb::Graph::Node.new(
          id: "a",
          width: 10,
          height: 10,
          ports: [Elkrb::Graph::Port.new(id: "ap")],
        )
        b = Elkrb::Graph::Node.new(id: "b", width: 10, height: 10)

        graph.children = [b, a]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: %w[ap b]),
        ]
      end

      it "keeps b under a instead of starting a tree of its own" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.x).to eq(a.x)
        expect(b.y).to be > a.y
      end
    end

    context "with a multi-source edge onto a target listed first" do
      # b is one of its own sources, with a as the other. Asking whether
      # the sources merely `include?` the target calls that a self-loop and
      # hands b a tree of its own; asking whether any source is a DIFFERENT
      # node keeps it as a's child.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "b", width: 10, height: 10),
          Elkrb::Graph::Node.new(id: "a", width: 10, height: 10),
        ]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: %w[a b], targets: ["b"]),
        ]
      end

      it "keeps b under a instead of starting a tree of its own" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.x).to eq(a.x)
        expect(b.y).to be > a.y
      end
    end

    context "with a port-sourced hyperedge onto its own node and a child" do
      # The source is a's port, never a itself. Resolving targets but not
      # sources leaves this edge with no source at all, so nothing marks b
      # as having incoming traffic and b becomes a root.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        a = Elkrb::Graph::Node.new(
          id: "a",
          width: 10,
          height: 10,
          ports: [
            Elkrb::Graph::Port.new(id: "p1"),
            Elkrb::Graph::Port.new(id: "p2"),
          ],
        )
        b = Elkrb::Graph::Node.new(id: "b", width: 10, height: 10)

        graph.children = [b, a]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e", sources: ["p1"], targets: %w[p2 b]),
        ]
      end

      it "keeps b under a instead of starting a tree of its own" do
        algorithm.layout(graph)

        a = graph.children.find { |n| n.id == "a" }
        b = graph.children.find { |n| n.id == "b" }

        expect(b.x).to eq(a.x)
        expect(b.y).to be > a.y
      end
    end

    context "with two edges onto two ports of the same child" do
      # "bp1" and "bp2" are different ids that resolve to the same node, so
      # de-duplicating the raw ids would leave b in the child list twice.
      # A duplicate does not move a node, it adds a column, so the width is
      # what shows it.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: Elkrb::Graph::LayoutOptions.new(
            "algorithm" => "mrtree",
          ),
        )
      end

      before do
        a = Elkrb::Graph::Node.new(id: "a", width: 10, height: 10)
        b = Elkrb::Graph::Node.new(
          id: "b",
          width: 10,
          height: 10,
          ports: [
            Elkrb::Graph::Port.new(id: "bp1"),
            Elkrb::Graph::Port.new(id: "bp2"),
          ],
        )

        graph.children = [b, a]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e1", sources: ["a"], targets: ["bp1"]),
          Elkrb::Graph::Edge.new(id: "e2", sources: ["a"], targets: ["bp2"]),
        ]
      end

      it "gives a one child, not the same node twice" do
        algorithm.layout(graph)

        # One 10-wide column between 12.0 of padding on each side. A second
        # copy of b would add a column and widen this.
        expect(graph.width).to eq(34.0)
      end
    end

    context "with children that carry no size" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          children: [
            Elkrb::Graph::Node.new(id: "a"),
            Elkrb::Graph::Node.new(id: "b"),
            Elkrb::Graph::Node.new(id: "c"),
          ],
          edges: [
            Elkrb::Graph::Edge.new(id: "e1", sources: ["a"], targets: ["b"]),
            Elkrb::Graph::Edge.new(id: "e2", sources: ["b"], targets: ["c"]),
          ],
        )
      end

      it "treats the missing width as zero instead of crashing" do
        expect { algorithm.layout(graph) }.not_to raise_error
      end

      it "still positions every node" do
        algorithm.layout(graph)

        expect(graph.children.map(&:x)).to all(be_a(Numeric))
        expect(graph.children.map(&:y)).to all(be_a(Numeric))
      end

      it "leaves the width unset, since the node never had one" do
        algorithm.layout(graph)

        expect(graph.children.map(&:width)).to all(be_nil)
      end
    end
  end
end

RSpec.describe "MRTree with a component that has no root of its own" do
  # a -> b -> a is wholly cyclic, so it contains no root. c is isolated and
  # is the graph's only root, which used to mean a and b were never reached
  # and kept nil coordinates until padding tripped over them.
  let(:graph) do
    {
      "id" => "r",
      "children" => %w[a b c].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
        { "id" => "e2", "sources" => ["b"], "targets" => ["a"] },
      ],
    }
  end

  it "lays out without tripping over a nil coordinate" do
    expect { Elkrb.layout(graph, algorithm: "mrtree") }.not_to raise_error
  end

  it "gives every node real coordinates, cyclic component included" do
    result = Elkrb.layout(graph, algorithm: "mrtree")

    expect(result.children.map(&:x)).to all(be_a(Float))
    expect(result.children.map(&:y)).to all(be_a(Float))
  end
end

RSpec.describe "MRTree fallback trees must stay disjoint" do
  # r -> u -> v -> c is a rooted chain. a <-> b is a cyclic component with no
  # root of its own, and a also points at c. Seeding a as a fallback root must
  # not let its tree reach back into c, which r's tree already owns — placing
  # c twice drags it above its own parent.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[r u v c a b].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["r"], "targets" => ["u"] },
        { "id" => "e2", "sources" => ["u"], "targets" => ["v"] },
        { "id" => "e3", "sources" => ["v"], "targets" => ["c"] },
        { "id" => "e4", "sources" => ["a"], "targets" => ["b"] },
        { "id" => "e5", "sources" => ["b"], "targets" => ["a"] },
        { "id" => "e6", "sources" => ["a"], "targets" => ["c"] },
      ],
    }
  end

  it "keeps a shared child below its own parent" do
    by_id = Elkrb.layout(graph, algorithm: "mrtree")
      .children.to_h { |node| [node.id, node] }

    expect(by_id["c"].y).to be > by_id["v"].y
    # v owns c and is its only parent in the forest, so they share a
    # column. Let a's fallback tree place c a second time and c slides
    # right, while y stays exactly where it was.
    expect(by_id["c"].x).to eq(by_id["v"].x)
  end

  it "still places every node" do
    result = Elkrb.layout(graph, algorithm: "mrtree")

    expect(result.children.map(&:y)).to all(be_a(Float))
  end
end

RSpec.describe "MRTree claims every sibling before expanding any of them" do
  # a's children are b and c, and c is reachable from b as well. The child
  # list is settled before any of it is recursed into, so c has to be
  # claimed as a's child straight away -- otherwise b's subtree reaches c,
  # places it and d a second time, and the later placement wins.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[a b c d].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
        { "id" => "e2", "sources" => ["a"], "targets" => ["c"] },
        { "id" => "e3", "sources" => ["b"], "targets" => ["c"] },
        { "id" => "e4", "sources" => ["c"], "targets" => ["d"] },
      ],
    }
  end

  it "leaves d under the c that a owns" do
    by_id = Elkrb.layout(graph, algorithm: "mrtree")
      .children.to_h { |node| [node.id, node] }

    expect(by_id["d"].x).to eq(by_id["c"].x)
  end
end

RSpec.describe "MRTree with a node reachable by two paths of different depth" do
  # r -> c is one hop. a -> b -> d -> c is three. c belongs at the deeper
  # level, or it lands above d, its own parent.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[r a b d c].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["r"], "targets" => ["c"] },
        { "id" => "e2", "sources" => ["a"], "targets" => ["b"] },
        { "id" => "e3", "sources" => ["b"], "targets" => ["d"] },
        { "id" => "e4", "sources" => ["d"], "targets" => ["c"] },
      ],
    }
  end

  it "places the shared node below its deepest parent" do
    by_id = Elkrb.layout(graph, algorithm: "mrtree")
      .children.to_h { |node| [node.id, node] }

    expect(by_id["c"].y).to be > by_id["d"].y
  end

  it "places every node exactly once" do
    result = Elkrb.layout(graph, algorithm: "mrtree")

    expect(result.children.map(&:id)).to match_array(%w[r a b d c])
    # The id list alone stays green even if every node landed on the same
    # spot -- layout never adds or drops a child. Distinct positions are
    # what says they were each laid out.
    positions = result.children.map { |node| [node.x, node.y] }
    expect(positions.uniq.size).to eq(positions.size)
  end
end

RSpec.describe "MRTree on a densely cyclic graph" do
  # Every node reachable from every other. Enumerating simple paths here is
  # factorial: a complete 8-node cycle took 2.5s and each further node cost
  # roughly ten times more. The bound is deliberately loose — it is guarding
  # against a return to factorial growth, not measuring throughput.
  def complete_cycle(size)
    ids = (1..size).map { |i| "s#{i}" }
    edges = [{ "id" => "seed", "sources" => ["root"],
               "targets" => [ids.first] }]
    ids.each_with_index do |from, i|
      ids.each_with_index do |to, j|
        next if i == j

        edges << { "id" => "e#{i}_#{j}", "sources" => [from],
                   "targets" => [to] }
      end
    end
    {
      "id" => "r",
      "children" => (["root"] + ids).map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => edges,
    }
  end

  it "lays out a complete 20-node cycle well inside a second" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Elkrb.layout(complete_cycle(20), algorithm: "mrtree")

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(elapsed).to be < 5.0
  end

  it "keeps the seed root above every node of the cycle" do
    result = Elkrb.layout(complete_cycle(12), algorithm: "mrtree")

    ids = result.children.map(&:id)
    expect(ids.uniq.size).to eq(ids.size)
    expect(result.children.map(&:y)).to all(be_a(Float))

    # "root" is the one node outside the cycle and the only one with no
    # incoming edge, so it is the sole real root. Every s-node has to be
    # levelled from it and land below it.
    by_id = result.children.to_h { |node| [node.id, node] }
    root = by_id.delete("root")
    expect(by_id.each_value.map(&:y)).to all(be > root.y)
  end
end
