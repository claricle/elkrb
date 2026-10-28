# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Disco do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with disconnected components" do
      it "identifies and lays out separate components" do
        graph = Elkrb::Graph::Graph.new

        # Component 1: Two connected nodes
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)

        # Component 2: Two connected nodes
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)
        node4 = Elkrb::Graph::Node.new(id: "n4", width: 50, height: 30)

        # Component 3: Single isolated node
        node5 = Elkrb::Graph::Node.new(id: "n5", width: 50, height: 30)

        graph.children = [node1, node2, node3, node4, node5]

        # Edges connecting components
        port1 = Elkrb::Graph::Port.new(id: "p1", node: node1)
        port2 = Elkrb::Graph::Port.new(id: "p2", node: node2)
        port3 = Elkrb::Graph::Port.new(id: "p3", node: node3)
        port4 = Elkrb::Graph::Port.new(id: "p4", node: node4)

        edge1 = Elkrb::Graph::Edge.new(
          id: "e1",
          sources: [port1],
          targets: [port2],
        )
        edge2 = Elkrb::Graph::Edge.new(
          id: "e2",
          sources: [port3],
          targets: [port4],
        )

        graph.edges = [edge1, edge2]

        result = algorithm.layout(graph)

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children.size).to eq(5)

        # All nodes should have positions
        result.children.each do |node|
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end
      end
    end

    context "with row arrangement" do
      it "arranges components in a horizontal row" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "disco.componentArrangement" => "row" }

        # Three separate components (single nodes each)
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)

        graph.children = [node1, node2, node3]
        graph.edges = []

        algorithm.layout(graph)

        # Nodes should be arranged horizontally with spacing
        expect(node1.x).to be < node2.x
        expect(node2.x).to be < node3.x
      end
    end

    context "with column arrangement" do
      it "arranges components in a vertical column" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "disco.componentArrangement" => "column" }

        # Three separate components (single nodes each)
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)

        graph.children = [node1, node2, node3]
        graph.edges = []

        algorithm.layout(graph)

        # Nodes should be arranged vertically with spacing
        expect(node1.y).to be < node2.y
        expect(node2.y).to be < node3.y
      end
    end

    context "with grid arrangement" do
      it "arranges components in a grid" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "disco.componentArrangement" => "grid" }

        # Four separate components (single nodes each)
        nodes = Array.new(4) do |i|
          Elkrb::Graph::Node.new(id: "n#{i + 1}", width: 50, height: 30)
        end

        graph.children = nodes
        graph.edges = []

        result = algorithm.layout(graph)

        # With 4 nodes, should form a 2×2 grid
        # Check that we have 2 distinct x positions and 2 distinct y positions
        x_positions = result.children.map(&:x).uniq.sort
        y_positions = result.children.map(&:y).uniq.sort

        expect(x_positions.size).to be >= 2
        expect(y_positions.size).to be >= 2
      end
    end

    context "with the documented componentCompaction.strategy option" do
      it "arranges components in a column, matching README.adoc's key name" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = {
          "disco.componentCompaction.strategy" => "COLUMN",
        }

        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)

        graph.children = [node1, node2, node3]
        graph.edges = []

        algorithm.layout(graph)

        expect(node1.y).to be < node2.y
        expect(node2.y).to be < node3.y
      end
    end

    context "with each componentCompaction.strategy value" do
      include DiscoStrategyPositions

      it "stacks COLUMN components down one x" do
        xs, ys = disco_positions_for("COLUMN").transpose

        expect(xs.uniq.size).to eq(1)
        expect(ys.each_cons(2).map { |a, b| b - a }).to all(eq(50.0))
      end

      it "sets GRID components in a 2x2 block" do
        xs, ys = disco_positions_for("GRID").transpose

        expect([xs.uniq.size, ys.uniq.size]).to eq([2, 2])
      end

      it "sets ROW components along one y, 70 apart" do
        xs, ys = disco_positions_for("ROW").transpose

        expect(ys.uniq.size).to eq(1)
        expect(xs.each_cons(2).map { |a, b| b - a }).to all(eq(70.0))
      end

      it "packs POLYOMINO into a block, not a row" do
        xs, ys = disco_positions_for("POLYOMINO").transpose

        expect([xs.uniq.size > 1, ys.uniq.size > 1]).to eq([true, true])
      end

      it "packs POLYOMINO when no strategy is named" do
        graph = Elkrb::Graph::Graph.new(
          children: Array.new(4) do |i|
            Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 30)
          end,
          edges: [],
        )
        described_class.new.layout(graph)

        expect(graph.children.map { |n| [n.x, n.y] })
          .to eq(disco_positions_for("POLYOMINO"))
      end
    end

    context "with POLYOMINO compaction" do
      include PolyominoFixtures

      # Positions ELK's DisCo gives the same graphs (same sizes, same start
      # positions, no component layout), measured from the top-left of the
      # nodes. Components are packed; edges are the straight lines between
      # node centers.
      let(:unconnected) do
        [["a", 100, 100], ["b", 30, 30], ["c", 60, 20], ["d", 30, 30],
         ["e", 50, 80], ["f", 40, 40]]
      end
      let(:connected) do
        [["a", 80, 40, 0, 0], ["b", 40, 40, 120, 0], ["c", 60, 30, 0, 100],
         ["d", 70, 50, 200, 200], ["e", 20, 20, 0, 300],
         ["f", 90, 25, 150, 320]]
      end

      def expect_positions(graph, expected)
        actual = relative_positions(graph)

        expect(actual.keys).to eq(expected.keys)
        expected.each do |id, point|
          expect(actual.fetch(id))
            .to match(point.map { |value| be_within(1e-4).of(value) })
        end
      end

      it "places four equal components where ELK does" do
        graph = layout_disco(disco_graph(Array.new(4) do |i|
          ["n#{i}", 50, 30]
        end))

        expect_positions(graph,
                         "n0" => [52.443635, 52.443635], "n1" => [0.0, 0.0],
                         "n2" => [72.110002, 0.0], "n3" => [0.0, 104.887267])
      end

      it "places unconnected components where ELK does" do
        graph = layout_disco(disco_graph(unconnected))

        expect_positions(graph,
                         "a" => [73.257121, 88.257121],
                         "b" => [75.504747, 33.188093],
                         "c" => [15.470234, 210.138055],
                         "d" => [132.821401, 33.188093],
                         "e" => [0.0, 0.0], "f" => [197.420195, 32.28214])
      end

      it "places connected components with ratio and spacing as ELK does" do
        graph = layout_disco(disco_graph(
                               connected,
                               edges: [%w[a b], %w[b c], %w[e f]],
                               options: { "elk.aspectRatio" => 2.0,
                                          "disco.componentSpacing" => 10.0 },
                             ))

        expect_positions(graph,
                         "a" => [0.0, 26.152664], "b" => [120.0, 26.152664],
                         "c" => [0.0, 126.152664], "d" => [190.535861, 0.0],
                         "e" => [105.535861, 108.344262],
                         "f" => [255.535861, 128.344262])
      end

      it "moves a component as one piece" do
        graph = disco_graph(
          connected,
          edges: [%w[a b], %w[b c], %w[e f]],
          options: { "disco.componentSpacing" => 10.0 },
        )
        before = graph.children.to_h { |n| [n.id, [n.x, n.y]] }
        layout_disco(graph)
        after = graph.children.to_h { |n| [n.id, [n.x, n.y]] }
        shift = ->(id) {
          [after[id][0] - before[id][0], after[id][1] - before[id][1]]
        }

        near = ->(of) {
          match(shift.call(of).map do |v|
            be_within(1e-9).of(v)
          end)
        }

        expect(shift.call("b")).to near.call("a")
        expect(shift.call("c")).to near.call("a")
        expect(shift.call("f")).to near.call("e")
      end

      it "leaves no two nodes overlapping, over generated graphs" do
        rng = Random.new(20_241_011)
        100.times do
          nodes = Array.new(rng.rand(1..9)) do |i|
            ["n#{i}", rng.rand(5..120), rng.rand(5..120), rng.rand(0..400),
             rng.rand(0..400)]
          end
          edges = if nodes.size < 2
                    []
                  else
                    Array.new(rng.rand(0..4)) do
                      nodes.sample(2, random: rng).map(&:first)
                    end
                  end
          ratio = [1.0, 1.6, 0.5].sample(random: rng)
          options = { "elk.aspectRatio" => ratio }
          graph = layout_disco(disco_graph(nodes, edges: edges,
                                                  options: options))

          expect(overlapping_across_components(graph)).to eq([])
        end
      end

      it "takes less area than a row with one large and many small ones" do
        sizes = [["big", 200, 200]] + Array.new(8) { |i| ["s#{i}", 40, 40] }
        area = lambda do |strategy|
          key = "disco.componentCompaction.strategy"
          graph = layout_disco(disco_graph(sizes, options: { key => strategy }))
          graph.width * graph.height
        end

        expect(area.call("POLYOMINO")).to be < area.call("ROW") * 0.7
      end

      it "reads elk.aspectRatio" do
        wide = layout_disco(disco_graph(unconnected,
                                        options: { "elk.aspectRatio" => 4.0 }))
        tall = layout_disco(disco_graph(unconnected,
                                        options: { "elk.aspectRatio" => 0.25 }))

        expect(wide.width / wide.height).to be > tall.width / tall.height
      end

      it "rejects an aspect ratio of zero" do
        graph = disco_graph(unconnected, options: { "elk.aspectRatio" => 0.0 })

        expect do
          layout_disco(graph)
        end.to raise_error(Elkrb::ValidationError, /aspectRatio/)
      end
    end

    context "with the arrangement named in the graph and in the call" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          layout_options: { "disco.componentArrangement" => "column" },
          children: Array.new(3) do |i|
            Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 30)
          end,
          edges: [],
        )
      end

      it "keeps the graph's legacy key over the call's documented key" do
        described_class.new("disco.componentCompaction.strategy" => "POLYOMINO")
          .layout(graph)

        expect(graph.children.map(&:x).uniq.size).to eq(1)
      end

      it "takes the call's documented key when the graph names neither" do
        graph.layout_options = nil
        described_class.new("disco.componentCompaction.strategy" => "COLUMN")
          .layout(graph)

        expect(graph.children.map(&:x).uniq.size).to eq(1)
      end
    end

    context "with component spacing option" do
      it "respects custom component spacing" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = {
          "disco.componentArrangement" => "row",
          "disco.componentSpacing" => 50.0,
        }

        # Two separate components (single nodes each)
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        algorithm.layout(graph)

        # Spacing should be at least 50 pixels
        spacing = node2.x - (node1.x + node1.width)
        expect(spacing).to be >= 50.0
      end
    end

    context "with connected graph" do
      it "treats fully connected graph as single component" do
        graph = Elkrb::Graph::Graph.new

        # All nodes connected
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)
        node3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)

        graph.children = [node1, node2, node3]

        port1 = Elkrb::Graph::Port.new(id: "p1", node: node1)
        port2 = Elkrb::Graph::Port.new(id: "p2", node: node2)
        port3 = Elkrb::Graph::Port.new(id: "p3", node: node3)

        edge1 = Elkrb::Graph::Edge.new(
          id: "e1",
          sources: [port1],
          targets: [port2],
        )
        edge2 = Elkrb::Graph::Edge.new(
          id: "e2",
          sources: [port2],
          targets: [port3],
        )

        graph.edges = [edge1, edge2]

        result = algorithm.layout(graph)

        # All nodes should be positioned (single component)
        expect(result.children.all? { |n| n.x && n.y }).to be true
      end
    end

    context "with empty graph" do
      it "handles empty graph" do
        graph = Elkrb::Graph::Graph.new
        graph.children = []
        graph.edges = []

        result = algorithm.layout(graph)

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children).to be_empty
      end
    end

    context "with custom component algorithm" do
      it "uses specified algorithm for component layout" do
        graph = Elkrb::Graph::Graph.new
        graph.layout_options = { "disco.componentAlgorithm" => "box" }

        # Two separate components with multiple nodes each
        node1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
        node2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)

        graph.children = [node1, node2]
        graph.edges = []

        result = algorithm.layout(graph)

        # Should apply box algorithm to each component
        expect(result.children.all? { |n| n.x && n.y }).to be true
      end

      it "rejects an unknown component algorithm" do
        graph = Elkrb::Graph::Graph.from_hash(
          id: "root",
          layoutOptions: { "disco.componentAlgorithm" => "layred" },
          children: [
            { id: "a", width: 20, height: 20 },
            { id: "b", width: 20, height: 20 },
          ],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        )

        expect { algorithm.layout(graph) }
          .to raise_error(Elkrb::AlgorithmNotFoundError,
                          "Unknown layout algorithm: layred")
      end
    end

    context "with a JSON graph: a-b connected, c isolated" do
      it "finds exactly two components" do
        graph = Elkrb::Graph::Graph.from_hash(
          "id" => "r",
          "children" => [
            { "id" => "a", "width" => 30, "height" => 30 },
            { "id" => "b", "width" => 30, "height" => 30 },
            { "id" => "c", "width" => 30, "height" => 30 },
          ],
          "edges" => [
            { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
          ],
        )

        components = algorithm.send(:find_connected_components, graph)

        expect(components.size).to eq(2)
        ab_component = components.find { |c| c[:nodes].size == 2 }
        expect(ab_component[:nodes].map(&:id)).to contain_exactly("a", "b")
      end
    end

    context "with an edge that references port ids" do
      it "puts both owning nodes in one component" do
        # The "with connected graph" case above builds edges from
        # Port objects assigned straight into sources:/targets: --
        # since those are :string collections, lutaml-model stringifies
        # the Port to its #inspect text, not its id, so that test never
        # actually exercises port-id resolution. This one references
        # the real port ids NodeIndex resolves.
        graph = Elkrb::Graph::Graph.from_hash(
          "id" => "r",
          "children" => [
            {
              "id" => "a", "width" => 30, "height" => 30,
              "ports" => [{ "id" => "a_out" }]
            },
            {
              "id" => "b", "width" => 30, "height" => 30,
              "ports" => [{ "id" => "b_in" }]
            },
          ],
          "edges" => [
            { "id" => "e1", "sources" => ["a_out"], "targets" => ["b_in"] },
          ],
        )

        components = algorithm.send(:find_connected_components, graph)

        expect(components.size).to eq(1)
        expect(components.first[:nodes].map(&:id)).to contain_exactly("a", "b")
      end
    end

    context "with a two-node cycle" do
      it "does not duplicate the cycle's edges into the component" do
        graph = Elkrb::Graph::Graph.from_hash(
          "id" => "r",
          "children" => [
            { "id" => "a", "width" => 30, "height" => 30 },
            { "id" => "b", "width" => 30, "height" => 30 },
          ],
          "edges" => [
            { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
            { "id" => "e2", "sources" => ["b"], "targets" => ["a"] },
          ],
        )

        components = algorithm.send(:find_connected_components, graph)

        expect(components.first[:edges].map(&:id))
          .to contain_exactly("e1", "e2")
      end

      # Regression guard: a version of find_connected_components that
      # adds `connected_edges` to the component every time a node is
      # DEQUEUED (rather than once, after the whole component's node
      # set is known) records each edge twice — once from its source
      # side, once from its target side. Passed into a layered
      # sub-layout, cycle_breaker.rb then reverses that same back-edge
      # twice (swapping it back to its original direction), so the cycle
      # is never actually broken and layer assignment recurses forever
      # (SystemStackError).
      it "lays out the cyclic component without raising" do
        graph = Elkrb::Graph::Graph.from_hash(
          "id" => "r",
          "children" => [
            { "id" => "a", "width" => 30, "height" => 30 },
            { "id" => "b", "width" => 30, "height" => 30 },
          ],
          "edges" => [
            { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
            { "id" => "e2", "sources" => ["b"], "targets" => ["a"] },
          ],
        )

        expect { algorithm.layout(graph) }.not_to raise_error
      end
    end
    # ELK allows a node with no width or height.
    context "with a node that declares no size" do
      %w[row column grid].each do |arrangement|
        it "places it instead of raising, for the #{arrangement} arrangement" do
          graph = Elkrb::Graph::Graph.new
          graph.layout_options = { "disco.componentArrangement" => arrangement }
          graph.children = [Elkrb::Graph::Node.new(id: "a"),
                            Elkrb::Graph::Node.new(id: "b")]
          graph.edges = []

          algorithm.layout(graph)

          expect(graph.children.map(&:x)).to all(be_a(Numeric).and(be_finite))
          expect(graph.children.map(&:y)).to all(be_a(Numeric).and(be_finite))
        end
      end
    end
  end
end

RSpec.describe "Disco routing after components are repositioned" do
  # A port-connected component laid out after an isolated one is routed twice:
  # once inside its own coordinate space, then again once it has been shifted
  # into place. The first set is stale and must not survive into the result.
  let(:graph) do
    {
      "id" => "root",
      "children" => [
        { "id" => "iso", "width" => 10, "height" => 10 },
        { "id" => "a", "width" => 10, "height" => 10,
          "ports" => [{ "id" => "ap", "width" => 2, "height" => 2 }] },
        { "id" => "b", "width" => 10, "height" => 10,
          "ports" => [{ "id" => "bp", "width" => 2, "height" => 2 }] },
      ],
      "edges" => [{ "id" => "e1", "sources" => ["ap"], "targets" => ["bp"] }],
    }
  end

  it "keeps only the aligned route from the final routing pass" do
    result = Elkrb.layout(graph, algorithm: "disco")
    section = result.edges.first.sections.first

    expect(result.edges.first.sections.size).to eq(1)
    expect(section.bend_points).to be_empty
  end

  it "leaves no bend outside the laid-out graph" do
    result = Elkrb.layout(graph, algorithm: "disco")
    section = result.edges.first.sections.first

    section.bend_points.each do |point|
      expect(point.x).to be_between(0, result.width)
      expect(point.y).to be_between(0, result.height)
    end
  end
end
