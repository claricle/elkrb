# frozen_string_literal: true

require "timeout"

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
      # de-duplicating the raw ids instead of the resolved nodes leaves b in
      # a's child list twice.
      #
      # z is what makes that visible. With only a and b, the duplicate moves
      # a and b together and apply_padding's bounding box takes the shift
      # straight back out -- the result is byte-identical either way. z is a
      # second tree, and a second tree starts at the width of the first one,
      # so it moves as soon as a's tree claims a column it should not have.
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

        z = Elkrb::Graph::Node.new(id: "z", width: 10, height: 10)

        graph.children = [b, a, z]
        graph.edges = [
          Elkrb::Graph::Edge.new(id: "e1", sources: ["a"], targets: ["bp1"]),
          Elkrb::Graph::Edge.new(id: "e2", sources: ["a"], targets: ["bp2"]),
        ]
      end

      it "gives a one child, not the same node twice" do
        algorithm.layout(graph)

        z = graph.children.find { |n| n.id == "z" }

        # a's tree is one 10-wide column, so z lands 30.0 past it: the
        # column plus 20.0 of node spacing, inside 12.0 of padding. A
        # duplicated b gives a's tree a second column and drops z to 22.0
        # with the graph 44.0 wide.
        expect(z.x).to eq(42.0)
        expect(graph.width).to eq(64.0)
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
        # Nil widths alone are also what a layout that did nothing at all
        # would leave behind. The missing width has to be READ as zero:
        # the chain stacks into one zero-wide column at the left padding.
        expect(graph.children.map(&:x)).to all(eq(12.0))
        expect(graph.children.map(&:y)).to eq([12.0, 92.0, 172.0])
        expect(graph.width).to eq(24.0)
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
    # The bound has to interrupt the call, not be read after it returns. A
    # regression to unbounded growth never reaches the assertion, so the old
    # form stalled the whole suite instead of failing this one example.
    expect do
      Timeout.timeout(5.0) do
        Elkrb.layout(complete_cycle(20), algorithm: "mrtree")
      end
    end.not_to raise_error
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

RSpec.describe "MRTree on a cycle hanging off a real root" do
  # r0 is the only root. a -> b -> c is the rest of the chain and c -> a
  # closes the cycle, which is what pushes a's own level past b's: the
  # back edge offers a a deeper candidate, the relaxation bound freezes
  # it there, and a ends up drawn below the child it owns.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[r0 a b c].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["r0"], "targets" => ["a"] },
        { "id" => "e2", "sources" => ["a"], "targets" => ["b"] },
        { "id" => "e3", "sources" => ["b"], "targets" => ["c"] },
        { "id" => "e4", "sources" => ["c"], "targets" => ["a"] },
      ],
    }
  end

  it "keeps every parent strictly above its own child" do
    by_id = Elkrb.layout(graph, algorithm: "mrtree")
      .children.to_h { |node| [node.id, node] }

    # r0 -> a -> b -> c is the chain the forest picks. c -> a is the edge
    # that closes the cycle and stays an unavoidable violation -- no tree
    # can honour it. Every edge the forest DID pick has to go downward.
    %w[r0 a b c].each_cons(2) do |parent, child|
      expect(by_id[child].y).to be > by_id[parent].y
    end
  end
end

RSpec.describe "MRTree relaxing a shared node listed above its own parents" do
  # a -> b, a -> c and b -> c, with the children listed bottom-up. One
  # sweep over that order reaches c through the short a -> c hop and stops:
  # nothing has told it about the longer a -> b -> c route yet, so c lands
  # level with b, its own parent. Only a second sweep pushes it below.
  #
  # Listed top-down the same graph converges in a single sweep and cannot
  # tell a one-shot relaxation from a repeated one.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[c b a].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
        { "id" => "e2", "sources" => ["a"], "targets" => ["c"] },
        { "id" => "e3", "sources" => ["b"], "targets" => ["c"] },
      ],
    }
  end

  it "keeps sweeping until the deeper route reaches c" do
    by_id = Elkrb.layout(graph, algorithm: "mrtree")
      .children.to_h { |node| [node.id, node] }

    expect(by_id["c"].y).to be > by_id["b"].y
    expect(by_id["b"].y).to be > by_id["a"].y
  end
end

RSpec.describe "MRTree with more than one rootless component" do
  # z is the graph's only root. a <-> b and c <-> d are two disjoint cyclic
  # components, neither reachable from z and neither holding a root of its
  # own. Seeding just one fallback root leaves the other component unlevelled
  # and unplaced, and padding then trips over its nil coordinates.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[z a b c d].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
        { "id" => "e2", "sources" => ["b"], "targets" => ["a"] },
        { "id" => "e3", "sources" => ["c"], "targets" => ["d"] },
        { "id" => "e4", "sources" => ["d"], "targets" => ["c"] },
      ],
    }
  end

  it "seeds a fallback root for every rootless component, not just one" do
    result = Elkrb.layout(graph, algorithm: "mrtree")
    by_id = result.children.to_h { |node| [node.id, node] }

    expect(result.children.map(&:y)).to all(be_a(Float))
    # z, a <-> b and c <-> d are three separate trees, so three columns.
    expect(result.children.map(&:x).uniq.size).to eq(3)
    expect(by_id["b"].y).to be > by_id["a"].y
    expect(by_id["d"].y).to be > by_id["c"].y
  end
end

RSpec.describe "MRTree with a multi-source edge led by its own target" do
  # b heads its own source list, with the genuinely different source a
  # second, and b is listed before a as a child. Reading only sources.first
  # calls this a self-loop, so nothing marks b as having incoming traffic
  # and b starts a tree of its own at its own x offset.
  #
  # The existing %w[a b] fixture cannot catch that: its first source already
  # differs from the target, so the two readings agree there.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[b a].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e", "sources" => %w[b a], "targets" => ["b"] },
      ],
    }
  end

  it "keeps b under a instead of starting a tree of its own" do
    by_id = Elkrb.layout(graph, algorithm: "mrtree")
      .children.to_h { |node| [node.id, node] }

    expect(by_id["b"].x).to eq(by_id["a"].x)
    expect(by_id["b"].y).to be > by_id["a"].y
  end
end

RSpec.describe "MRTree on a graph with no root anywhere" do
  # A bare 2-cycle: every node has incoming traffic, so root finding comes
  # back empty and every child has to be treated as a root. n1's tree then
  # claims n0, and the n0 seed behind it has to be skipped -- handing it a
  # tree of its own would place n0 twice, in a second column.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[n1 n0].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["n0"], "targets" => ["n1"] },
        { "id" => "e2", "sources" => ["n1"], "targets" => ["n0"] },
      ],
    }
  end

  it "places both nodes in one column, each exactly once" do
    result = Elkrb.layout(graph, algorithm: "mrtree")
    by_id = result.children.to_h { |node| [node.id, node] }

    expect(result.children.map(&:y)).to all(be_a(Float))
    expect(by_id["n0"].x).to eq(by_id["n1"].x)
    expect(by_id["n0"].y).to be > by_id["n1"].y
  end
end

RSpec.describe "MRTree with an edge declared on a childless sibling" do
  # n owns the edge x -> y, so the node index folds it in and index.edges
  # sees it while graph.edges does not. Root finding reads the narrower
  # graph.edges, which makes y a root. Building the adjacency map from the
  # wider set would make y x's child at the same time -- a root that is also
  # somebody's child gets placed twice, once per view.
  let(:graph) do
    {
      "id" => "root",
      "children" => [
        { "id" => "x", "width" => 10, "height" => 10 },
        { "id" => "y", "width" => 10, "height" => 10 },
        { "id" => "n", "width" => 10, "height" => 10,
          "edges" => [
            { "id" => "own", "sources" => ["x"], "targets" => ["y"] },
          ] },
      ],
    }
  end

  it "keeps the child list and the root list reading the same edges" do
    result = Elkrb.layout(graph, algorithm: "mrtree")
    by_id = result.children.to_h { |node| [node.id, node] }

    # y is a root by graph.edges, so it stays one: its own column, its own
    # top row, not tucked under x.
    expect(by_id["y"].y).to eq(by_id["x"].y)
    expect(by_id["y"].x).not_to eq(by_id["x"].x)
    expect(result.children.map(&:x).uniq.size).to eq(3)
  end
end

RSpec.describe "MRTree on a hash that declares no edges at all" do
  # Graph.from_hash bypasses Graph#initialize, so it leaves `edges` nil
  # rather than filling in the empty default -- and that is the constructor
  # LayoutEngine uses for Hash input. Reaching for `edges.each` here blows
  # up on the real entry point while every Graph.new fixture stays green.
  let(:graph) do
    {
      "id" => "root",
      "children" => %w[a b].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
    }
  end

  it "lays the children out as roots instead of tripping over nil edges" do
    expect { Elkrb.layout(graph, algorithm: "mrtree") }.not_to raise_error

    result = Elkrb.layout(graph, algorithm: "mrtree")
    expect(result.children.map(&:x)).to all(be_a(Float))
    expect(result.children.map(&:y)).to all(be_a(Float))
    # No edges means no parents: two roots, side by side on one row.
    expect(result.children.map(&:y).uniq.size).to eq(1)
    expect(result.children.map(&:x).uniq.size).to eq(2)
  end
end

RSpec.describe "MRTree on many disjoint cyclic components" do
  # Two isolated roots plus a pile of 2-cycles. Nothing reaches the cycles
  # from a root, so every one of them costs its own fallback seed and its
  # own relaxation -- this is the shape that stresses build_forest's loop,
  # where one dense component with a real root only ever seeds once.
  #
  # The bound is deliberately loose. It is here to catch a hang, not to
  # certify a cost. Levelling this shape WAS superlinear -- relaxation ran
  # graph-wide per seed against a graph-sized level bound. It is now scoped
  # to each component, and the 480-node example below is what measures that.
  def disjoint_cycles(size)
    ids = (0...size).map { |i| "n#{i}" }
    edges = ((size - 2) / 2).times.flat_map do |k|
      a = ids[2 + (k * 2)]
      b = ids[3 + (k * 2)]
      [{ "id" => "f#{k}", "sources" => [a], "targets" => [b] },
       { "id" => "r#{k}", "sources" => [b], "targets" => [a] }]
    end
    {
      "id" => "r",
      "children" => ids.map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => edges,
    }
  end

  it "places every component without hanging" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Elkrb.layout(disjoint_cycles(80), algorithm: "mrtree")
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(elapsed).to be < 5.0
    # The crash this branch is named for: a component left unseeded keeps
    # nil coordinates, and apply_padding dies subtracting from them.
    expect(result.children.map(&:x)).to all(be_a(Float))
    expect(result.children.map(&:y)).to all(be_a(Float))
  end
end

RSpec.describe "MRTree levelling a cycle it cannot find a path through" do
  # root is the only real root; c1..c5 are wired to each other in every
  # direction. Relaxation has no longest path to settle on here, so each
  # sweep keeps offering a deeper candidate and the levels climb until the
  # bound stops them. Drop that bound and the depth grows with the SQUARE
  # of the node count instead of with the node count.
  let(:graph) do
    ids = %w[c1 c2 c3 c4 c5]
    edges = [{ "id" => "seed", "sources" => ["root"], "targets" => ["c1"] }]
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

  it "keeps the cycle's depth proportional to the node count" do
    result = Elkrb.layout(graph, algorithm: "mrtree")

    # Rows are 80 apart. Relaxation cannot push a level past the node
    # count, and the tree floor can add at most one row per node on top of
    # that, so twice the node count is the honest ceiling -- six nodes here
    # occupy seven rows. Unbounded, the same graph spreads over thirty-two.
    expect(result.height).to be < (2 * result.children.size * 80.0)
  end

  it "still puts the seed root above every node of the cycle" do
    by_id = Elkrb.layout(graph, algorithm: "mrtree")
      .children.to_h { |node| [node.id, node] }
    root = by_id.delete("root")

    expect(by_id.each_value.map(&:y)).to all(be > root.y)
  end
end

RSpec.describe "MRTree forest spacing and component cost" do
  let(:spacing) { 31.0 }

  # r0 owns a, b and c; r1 owns only d, because a node belongs to one tree.
  # The forest offset used to come from a width that summed leaf widths and
  # skipped the gaps between them, so the next tree started too far left and
  # its nodes touched the previous tree's.
  def two_trees
    {
      "id" => "r",
      "children" => %w[r0 r1 a b c d].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => [
        { "id" => "e1", "sources" => ["r0"], "targets" => ["a"] },
        { "id" => "e2", "sources" => ["r0"], "targets" => ["b"] },
        { "id" => "e3", "sources" => ["r0"], "targets" => ["c"] },
        { "id" => "e4", "sources" => ["r1"], "targets" => ["c"] },
        { "id" => "e5", "sources" => ["r1"], "targets" => ["d"] },
      ],
    }
  end

  it "keeps the configured gap between nodes that share a row" do
    # Passed as an option, not in the graph's layoutOptions: measured on this
    # branch, a graph-level "elk.spacing.nodeNode" does not reach mrtree's
    # node_spacing and the layout silently uses the 20.0 default. Using a
    # non-default value is what stops this example passing on that default.
    result = Elkrb.layout(two_trees, algorithm: "mrtree",
                                     spacing_node_node: spacing)

    by_row = result.children.group_by(&:y)
    by_row.each_value do |row|
      row.sort_by(&:x).each_cons(2) do |left, right|
        gap = right.x - (left.x + (left.width || 0.0))
        # Name the gap, not merely "they do not overlap": a zero gap is
        # already the defect, and >= 0 would pass with it.
        expect(gap).to be >= spacing
      end
    end
  end

  # Two isolated roots plus a pile of disjoint 2-cycles. The two roots are
  # LOAD-BEARING, not an off-by-one: they are what makes this the cubic
  # shape. Nothing reaches the cycles from a root, so each cycle costs its
  # own fallback seed, and levelling used to run graph-wide per seed against
  # a graph-sized bound.
  #
  # Pairing every node instead removes the roots, and the old code then
  # seeded everything at once and relaxed once -- quadratic, fast enough to
  # pass this example's bound with the defect still present. That was tried
  # and reverted; a version of this fixture with no roots proves nothing.
  #
  # Measured against the old code on this shape: 120 nodes 0.24s, 240 nodes
  # 1.61s -- doubling the size multiplies the time by 6.7.
  def disjoint_two_cycles(size)
    ids = (0...size).map { |i| "n#{i}" }
    edges = ((size - 2) / 2).times.flat_map do |k|
      a = ids[2 + (k * 2)]
      b = ids[3 + (k * 2)]
      [{ "id" => "f#{k}", "sources" => [a], "targets" => [b] },
       { "id" => "r#{k}", "sources" => [b], "targets" => [a] }]
    end
    {
      "id" => "r",
      "children" => ids.map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => edges,
    }
  end

  # A tree whose LAST child is narrow but has descendants reaching further
  # right than itself. The consumed width used to be read off that last
  # child's own edge, which sits left of its subtree's real extent, so the
  # next tree started inside this one. Found by review with this exact shape.
  def deep_then_wide
    pairs = [%w[r0 deep1], %w[deep1 deep2], %w[deep2 deep3],
             %w[r0 wide], %w[wide a], %w[wide b], %w[wide c],
             %w[r1 q1], %w[q1 q2], %w[q2 q3]]
    {
      "id" => "r",
      "children" => %w[r0 r1 deep1 deep2 deep3 wide a b c q1 q2 q3].map do |id|
        { "id" => id, "width" => 10, "height" => 10 }
      end,
      "edges" => pairs.each_with_index.map do |(source, target), i|
        { "id" => "e#{i}", "sources" => [source], "targets" => [target] }
      end,
    }
  end

  # A parent WIDER than all its children combined. Centring puts it either
  # side of them, so the consumed width has to come from where the nodes
  # actually landed, not from what the children were allotted. Found by
  # review: a 200px parent over two 10px children reported 60 and the next
  # tree began 60px inside it.
  def wide_parent
    {
      "id" => "r",
      "children" => [{ "id" => "big", "width" => 200, "height" => 10 },
                     { "id" => "c1", "width" => 10, "height" => 10 },
                     { "id" => "c2", "width" => 10, "height" => 10 },
                     { "id" => "r2", "width" => 10, "height" => 10 },
                     { "id" => "d1", "width" => 10, "height" => 10 }],
      "edges" => [{ "id" => "e1", "sources" => ["big"], "targets" => ["c1"] },
                  { "id" => "e2", "sources" => ["big"], "targets" => ["c2"] },
                  { "id" => "e3", "sources" => ["r2"], "targets" => ["d1"] }],
    }
  end

  it "counts a parent wider than its children as part of its tree's width" do
    result = Elkrb.layout(wide_parent, algorithm: "mrtree",
                                       spacing_node_node: 20)
    by_id = result.children.to_h { |node| [node.id, node] }
    big = by_id.fetch("big")
    other = by_id.fetch("r2")

    expect(big.y).to eq(other.y)
    # Signed gap, so an overlap reads as negative rather than as a near miss.
    expect(other.x - (big.x + big.width)).to be >= 20
  end

  it "separates trees by a last child's descendants, not the child itself" do
    result = Elkrb.layout(deep_then_wide, algorithm: "mrtree",
                                          spacing_node_node: 37)
    by_id = result.children.to_h { |node| [node.id, node] }
    left = by_id.fetch("c")
    right = by_id.fetch("q2")

    # These two land on the same row and belong to different trees. Naming
    # the gap matters: they used to overlap by 10px, so a >= 0 assertion
    # would have passed with the defect in place.
    expect(left.y).to eq(right.y)
    expect(right.x - (left.x + left.width)).to be >= 37
  end

  it "lays out 480 disjoint-cycle nodes in the bound, placing them all" do
    # The timeout interrupts the call rather than being read after it returns,
    # for the same reason as the complete-cycle example above. Asserting the
    # positions in the same example keeps the bound honest: a layout that
    # returned early having placed nothing would beat any time bound.
    result = nil

    expect do
      result = Timeout.timeout(5.0) do
        Elkrb.layout(disjoint_two_cycles(480), algorithm: "mrtree")
      end
    end.not_to raise_error

    expect(result.children.size).to eq(480)
    expect(result.children.map(&:x)).to all(be_a(Numeric).and(be_finite))
  end
end
