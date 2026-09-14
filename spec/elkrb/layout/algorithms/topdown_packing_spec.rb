# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::TopdownPacking do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with a basic graph (3-5 nodes)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: {
            "algorithm" => "topdownpacking",
            "elk.spacing.nodeNode" => 10.0,
          },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 50, height: 40),
          Elkrb::Graph::Node.new(id: "node2", width: 40, height: 30),
          Elkrb::Graph::Node.new(id: "node3", width: 60, height: 35),
          Elkrb::Graph::Node.new(id: "node4", width: 30, height: 25),
        ]
      end

      it "arranges nodes in a grid pattern" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # For 4 nodes, should create a 2x2 grid
        # Verify grid structure (nodes should align in rows/columns)
        nodes = graph.children.sort_by { |n| [n.y, n.x] }

        # Top row nodes should have similar y values
        expect((nodes[0].y - nodes[1].y).abs).to be < 1.0
        # Bottom row nodes should have similar y values
        expect((nodes[2].y - nodes[3].y).abs).to be < 1.0
      end

      it "keeps each node's own declared width and height" do
        algorithm.layout(graph)

        # Every node here declared its own size; a size-less node is the
        # only one that takes the grid cell size, so these stay as given.
        expect(graph.children.map(&:width)).to eq([50.0, 40.0, 60.0, 30.0])
        expect(graph.children.map(&:height)).to eq([40.0, 30.0, 35.0, 25.0])
      end

      it "verifies no overlaps between nodes" do
        algorithm.layout(graph)

        # Check for no overlaps
        graph.children.combination(2).each do |node1, node2|
          overlap_x = (node1.x < node2.x + node2.width) &&
            (node1.x + node1.width > node2.x)
          overlap_y = (node1.y < node2.y + node2.height) &&
            (node1.y + node1.height > node2.y)

          expect(overlap_x && overlap_y).to be false
        end
      end

      it "sets graph dimensions correctly" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0

        # Graph should be large enough to contain all nodes
        graph.children.each do |node|
          expect(node.x + node.width).to be <= graph.width
          expect(node.y + node.height).to be <= graph.height
        end
      end
    end

    context "with declared node sizes (tree-family-14)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "topdownpacking" },
        )
      end

      it "keeps every node's declared width and height instead of the cell size" do
        graph.children = %w[a b c d].map do |id|
          Elkrb::Graph::Node.new(id: id, width: 100, height: 50)
        end

        algorithm.layout(graph)

        expect(graph.children.map { |n| [n.width, n.height] }.uniq).to eq([[100.0, 50.0]])
      end

      it "gives a size-less node the (width-averaged) cell size while declared nodes keep their own" do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", width: 100, height: 50),
          Elkrb::Graph::Node.new(id: "b", width: 100, height: 50),
          Elkrb::Graph::Node.new(id: "c", width: 100, height: 50),
          Elkrb::Graph::Node.new(id: "d"),
        ]

        algorithm.layout(graph)

        sized, sizeless = graph.children.partition { |n| n.id != "d" }

        expect(sized.map { |n| [n.width, n.height] }).to eq([[100.0, 50.0]] * 3)
        # avg width = (100+100+100+0.0)/4 = 75.0 -- the size-less node
        # contributes 0.0, not its own size, to that average.
        expect([sizeless.first.width, sizeless.first.height]).to eq([75.0, 75.0])
      end

      it "gives a size-less node the (height-averaged) cell size while declared nodes keep their own" do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", width: 20, height: 200),
          Elkrb::Graph::Node.new(id: "b", width: 20, height: 200),
          Elkrb::Graph::Node.new(id: "c", width: 20, height: 200),
          Elkrb::Graph::Node.new(id: "d"),
        ]

        algorithm.layout(graph)

        sized, sizeless = graph.children.partition { |n| n.id != "d" }

        expect(sized.map { |n| [n.width, n.height] }).to eq([[20.0, 200.0]] * 3)
        # avg height = (200+200+200+0.0)/4 = 150.0 here dominates the base
        # dimension -- the size-less node's own (absent) height is 0.0,
        # not its own size, in that average.
        expect([sizeless.first.width, sizeless.first.height]).to eq([150.0, 150.0])
      end

      it "does not let a declared node larger than the average cell overlap its neighbours" do
        # A declared node can be larger than the grid-cell size (which is
        # only an average). Advancing the grid by the cell size regardless
        # would let such a node overlap the node placed after it.
        graph.children = [
          Elkrb::Graph::Node.new(id: "tiny", width: 10, height: 10),
          Elkrb::Graph::Node.new(id: "small", width: 30, height: 20),
          Elkrb::Graph::Node.new(id: "medium", width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "large", width: 80, height: 60),
          Elkrb::Graph::Node.new(id: "huge", width: 120, height: 100),
        ]

        algorithm.layout(graph)

        # Uniform-grid code (e.g. resizing every node to one averaged cell
        # size) never overlaps here either, so the overlap check alone
        # would pass for the wrong reason. Pin each node's own declared
        # size too, so a regression that clobbers declared sizes back to
        # a uniform cell fails this example directly.
        declared_sizes = {
          "tiny" => [10.0, 10.0],
          "small" => [30.0, 20.0],
          "medium" => [50.0, 50.0],
          "large" => [80.0, 60.0],
          "huge" => [120.0, 100.0],
        }
        graph.children.each do |node|
          expect([node.width, node.height]).to eq(declared_sizes[node.id])
        end

        graph.children.combination(2).each do |node1, node2|
          overlap_x = (node1.x < node2.x + node2.width) &&
            (node1.x + node1.width > node2.x)
          overlap_y = (node1.y < node2.y + node2.height) &&
            (node1.y + node1.height > node2.y)

          expect(overlap_x && overlap_y).to be(false), "#{node1.id} and #{node2.id} overlap"
        end
      end
    end

    context "with degenerate declared sizes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "topdownpacking" },
        )
      end

      it "falls back to a default cell size when no node declares any width or height" do
        graph.children = %w[a b c d].map { |id| Elkrb::Graph::Node.new(id: id) }

        algorithm.layout(graph)

        # Every node is completely size-less and no nodeWidth option is
        # set, so the width/height average degenerates to zero. Without a
        # fallback every node would silently collapse to a 0x0 footprint.
        expect(graph.children.map { |n| [n.width, n.height] }.uniq)
          .to eq([[described_class::DEFAULT_CELL_SIZE, described_class::DEFAULT_CELL_SIZE]])
      end

      it "does not crash and keeps declared sizes when a declared width is NaN" do
        # Heterogeneous declared sizes, deliberately not all equal to the
        # cell size the algorithm computes -- code that clobbers every
        # node to a uniform cell size (as unfixed code does, since it
        # can't isolate the NaN node) would pass a vaguer assertion here
        # even though it discards every OTHER node's declared size too.
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", width: 30, height: 30),
          Elkrb::Graph::Node.new(id: "h", width: Float::NAN, height: 80),
          Elkrb::Graph::Node.new(id: "c", width: 60, height: 60),
          Elkrb::Graph::Node.new(id: "d", width: 90, height: 40),
        ]

        expect { algorithm.layout(graph) }.not_to raise_error

        by_id = graph.children.to_h { |n| [n.id, [n.width, n.height]] }
        expect(by_id["a"]).to eq([30.0, 30.0])
        expect(by_id["c"]).to eq([60.0, 60.0])
        expect(by_id["d"]).to eq([90.0, 40.0])

        # The NaN node's width is unusable and falls back to the computed
        # cell width -- pinned to the exact value (not merely `be_finite`,
        # which would also pass for a wrong-but-finite fallback) so a
        # regression to the guard is caught directly: avg_height =
        # (30+80+60+40)/4 = 52.5 dominates avg_width = (30+0+60+90)/4 = 45.0
        # (the NaN node contributes 0.0), so node_height = 52.5 becomes the
        # base dimension and node_width = 52.5 * aspect_ratio(1.0).
        # Its own declared height is untouched.
        expect(by_id["h"][0]).to eq(52.5)
        expect(by_id["h"][1]).to eq(80.0)

        graph.children.each do |node|
          expect(node.x).to be_finite
          expect(node.y).to be_finite
        end
      end

      it "does not crash and does not propagate Infinity when a declared height is infinite" do
        graph.children = [
          Elkrb::Graph::Node.new(id: "a", width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "h", width: 50, height: Float::INFINITY),
          Elkrb::Graph::Node.new(id: "c", width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "d", width: 50, height: 50),
        ]

        expect { algorithm.layout(graph) }.not_to raise_error

        inf_node = graph.children.find { |n| n.id == "h" }
        # Pinned to the exact value: avg_width = (50+50+50+50)/4 = 50.0
        # dominates avg_height = (50+0+50+50)/4 = 37.5 (the Infinity node
        # contributes 0.0), so node_width = 50.0 is the base dimension and
        # node_height = 50.0 / aspect_ratio(1.0) becomes the fallback.
        expect(inf_node.height).to eq(50.0)
        expect(inf_node.x).to be_finite
        expect(inf_node.y).to be_finite
      end

      it "does not let an Infinity-width node dominate the average and corrupt a sized peer's fallback" do
        # This is the mutant-coverage gap: a spec whose fixture happens to
        # land where the guarded and unguarded avg_width already coincide
        # cannot kill a mutant that deletes the finite_dimension guard on
        # the sum. Here the Infinity node's width is large enough relative
        # to its peers that the guarded and unguarded averages genuinely
        # diverge, so removing the guard changes the asserted value.
        graph.children = [
          Elkrb::Graph::Node.new(id: "inf", width: Float::INFINITY, height: 10),
          Elkrb::Graph::Node.new(id: "p1", width: 100, height: 10),
          Elkrb::Graph::Node.new(id: "p2", width: 100, height: 10),
        ]

        expect { algorithm.layout(graph) }.not_to raise_error

        # Guarded: avg_width = (0+100+100)/3 = 66.666... (finite).
        # Unguarded (Infinity included in the sum): avg_width = Infinity.
        expected_cell_width = 200.0 / 3.0
        by_id = graph.children.to_h { |n| [n.id, [n.width, n.height]] }

        # The peers' own declared sizes are untouched.
        expect(by_id["p1"]).to eq([100.0, 10.0])
        expect(by_id["p2"]).to eq([100.0, 10.0])

        # The Infinity node's own width is unusable and falls back to the
        # computed cell width; its own declared height is untouched.
        expect(by_id["inf"][0]).to eq(expected_cell_width)
        expect(by_id["inf"][1]).to eq(10.0)
      end

      it "treats a negative declared width the same as size-less, instead of letting it invert its own box" do
        # Before this file's declared-size-preserving change, every node
        # got the SAME shared, uniformly-averaged cell size, so a negative
        # declared value could corrupt the aggregate but no single node
        # could ever show its OWN negative value while its neighbours
        # stayed normal. Preserving each node's own size is exactly what
        # lets one node's negative value flow into its own box for the
        # first time -- inverting it ([x, x+width] with width < 0) and
        # producing a false-negative overlap against a neighbour under the
        # standard min/max overlap formula (used both below and in
        # base_algorithm.rb's calculate_bounding_box). Rejecting non-
        # positive values the same way NaN/Infinity are rejected closes
        # this by falling back to the grid cell size instead.
        graph.children = [
          Elkrb::Graph::Node.new(id: "neg", width: -80.0, height: 70.0),
          Elkrb::Graph::Node.new(id: "p1", width: 50.0, height: 50.0),
          Elkrb::Graph::Node.new(id: "p2", width: 50.0, height: 50.0),
          Elkrb::Graph::Node.new(id: "p3", width: 50.0, height: 50.0),
        ]

        algorithm.layout(graph)

        # The peers' own declared sizes are untouched.
        by_id = graph.children.to_h { |n| [n.id, [n.width, n.height]] }
        expect(by_id["p1"]).to eq([50.0, 50.0])
        expect(by_id["p2"]).to eq([50.0, 50.0])
        expect(by_id["p3"]).to eq([50.0, 50.0])

        # The negative-width node's own width is unusable and falls back
        # to the computed cell width (avg_height = (70+50+50+50)/4 = 55.0
        # dominates avg_width = (0+50+50+50)/4 = 37.5, since the negative
        # value contributes 0.0, so node_width = 55.0). Its own declared
        # height (70.0) is positive and finite, so it is kept as-is.
        expect(by_id["neg"]).to eq([55.0, 70.0])

        # No box is inverted, so the standard overlap formula finds none.
        graph.children.combination(2).each do |node1, node2|
          overlap_x = (node1.x < node2.x + node2.width) &&
            (node1.x + node1.width > node2.x)
          overlap_y = (node1.y < node2.y + node2.height) &&
            (node1.y + node1.height > node2.y)

          expect(overlap_x && overlap_y).to be(false), "#{node1.id} and #{node2.id} overlap"
        end
      end
    end

    context "with many nodes (20+ nodes)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: {
            "algorithm" => "topdownpacking",
            "elk.spacing.nodeNode" => 5.0,
          },
        )
      end

      before do
        graph.children = (1..25).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 30 + ((i % 5) * 10),
            height: 20 + ((i % 4) * 10),
          )
        end
      end

      it "arranges all nodes in a grid" do
        algorithm.layout(graph)

        # All nodes should be positioned
        expect(graph.children.all? { |n| n.x.is_a?(Numeric) }).to be true
        expect(graph.children.all? { |n| n.y.is_a?(Numeric) }).to be true

        # For 25 nodes, should create a 5x5 grid
        # Verify that nodes are arranged in rows
        nodes_by_row = graph.children.group_by { |n| n.y.round }
        expect(nodes_by_row.size).to be <= 5
      end

      it "maintains proper spacing between nodes" do
        algorithm.layout(graph)

        # Check spacing between adjacent nodes
        sorted_nodes = graph.children.sort_by { |n| [n.y, n.x] }

        # Check horizontal spacing on first row
        row_nodes = sorted_nodes.select do |n|
          (n.y - sorted_nodes.first.y).abs < 1.0
        end
        if row_nodes.size > 1
          spacing = row_nodes[1].x - (row_nodes[0].x + row_nodes[0].width)
          expect(spacing).to be >= 4.0 # Allow small floating point variance
        end
      end

      it "verifies no overlaps with many nodes" do
        algorithm.layout(graph)

        # Check for no overlaps
        graph.children.combination(2).each do |node1, node2|
          overlap_x = (node1.x < node2.x + node2.width) &&
            (node1.x + node1.width > node2.x)
          overlap_y = (node1.y < node2.y + node2.height) &&
            (node1.y + node1.height > node2.y)

          expect(overlap_x && overlap_y).to be false
        end
      end
    end

    context "with different aspect ratios" do
      let(:aspect_ratio) { 2.0 }

      let(:graph) do
        opts = {}
        opts["algorithm"] = "topdownpacking"
        opts["topdownpacking.aspectRatio"] = aspect_ratio

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..9).map do |i|
          Elkrb::Graph::Node.new(id: "node#{i}", width: 50, height: 50)
        end
      end

      it "does not reshape declared node sizes" do
        algorithm.layout(graph)

        # Every node already declared its own size, so the aspect ratio
        # option — which only governs the grid cell size — never touches
        # them; only a size-less node would take a reshaped cell size.
        graph.children.each do |node|
          expect([node.width, node.height]).to eq([50.0, 50.0])
        end
      end

      it "creates a proper grid with aspect ratio 2.0" do
        algorithm.layout(graph)

        # For 9 nodes, should create a 3x3 grid
        nodes_by_y = graph.children.group_by { |n| n.y.round }
        expect(nodes_by_y.size).to eq(3)
      end
    end

    context "with various node sizes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "topdownpacking" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "tiny", width: 10, height: 10),
          Elkrb::Graph::Node.new(id: "small", width: 30, height: 20),
          Elkrb::Graph::Node.new(id: "medium", width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "large", width: 80, height: 60),
          Elkrb::Graph::Node.new(id: "huge", width: 120, height: 100),
        ]
      end

      it "keeps each node's own declared size instead of normalizing" do
        algorithm.layout(graph)

        expect(graph.children.map(&:width)).to eq([10.0, 30.0, 50.0, 80.0, 120.0])
        expect(graph.children.map(&:height)).to eq([10.0, 20.0, 50.0, 60.0, 100.0])
      end

      it "positions all nodes correctly" do
        algorithm.layout(graph)

        graph.children.each do |node|
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end
      end
    end

    context "with a single node" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "topdownpacking" },
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 50, height: 40),
        ]
      end

      it "positions the single node correctly" do
        algorithm.layout(graph)

        node = graph.children.first
        # After padding, node will be offset by padding amount
        expect(node.x).to be >= 0.0
        expect(node.y).to be >= 0.0
      end

      it "sets appropriate graph dimensions" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0
      end
    end

    context "with no nodes (empty graph)" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "topdownpacking" },
        )
      end

      before do
        graph.children = []
      end

      it "handles empty graph gracefully" do
        algorithm.layout(graph)

        expect(graph.width).to eq(0)
        expect(graph.height).to eq(0)
      end
    end

    context "with custom node width option" do
      let(:graph) do
        opts = {}
        opts["algorithm"] = "topdownpacking"
        opts["topdownpacking.nodeWidth"] = 100.0
        opts["topdownpacking.aspectRatio"] = 1.5

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        # Size-less: topdownpacking.nodeWidth sets the grid cell size, which
        # only ever applies to a node with no declared size of its own.
        graph.children = (1..6).map { |i| Elkrb::Graph::Node.new(id: "node#{i}") }
      end

      it "respects custom node width" do
        algorithm.layout(graph)

        graph.children.each do |node|
          expect(node.width).to eq(100.0)
        end
      end

      it "calculates height from width and aspect ratio" do
        algorithm.layout(graph)

        graph.children.each do |node|
          expected_height = 100.0 / 1.5
          expect(node.height).to be_within(0.1).of(expected_height)
        end
      end
    end

    context "with a non-finite topdownpacking option and a fully size-less graph" do
      # finite_dimension was only ever applied to per-node width/height,
      # never to these two options. When every node is size-less (so the
      # fallback cell size actually gets computed and used), an unguarded
      # NaN reaches the identical Array#max call in
      # calculate_bounding_box that finite_dimension exists to protect
      # against for per-node sizes, and raises the identical
      # ArgumentError: comparison of Float with NaN failed. Masked
      # whenever any node has its own finite declared size (that node's
      # own value wins over the poisoned cell size), which is exactly why
      # this needs its own size-less-graph coverage.
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "topdownpacking" }.merge(layout_option),
        )
      end

      before do
        graph.children = (1..4).map { |i| Elkrb::Graph::Node.new(id: "n#{i}") }
      end

      shared_examples "falls back to the default cell size" do
        it "does not crash and falls back to the default cell size" do
          expect { algorithm.layout(graph) }.not_to raise_error

          expect(graph.children.map { |n| [n.width, n.height] }.uniq)
            .to eq([[described_class::DEFAULT_CELL_SIZE, described_class::DEFAULT_CELL_SIZE]])
        end
      end

      context "with aspectRatio: NaN" do
        let(:layout_option) { { "topdownpacking.aspectRatio" => Float::NAN } }

        include_examples "falls back to the default cell size"
      end

      context "with aspectRatio: Infinity" do
        let(:layout_option) { { "topdownpacking.aspectRatio" => Float::INFINITY } }

        include_examples "falls back to the default cell size"
      end

      context "with nodeWidth: NaN" do
        let(:layout_option) { { "topdownpacking.nodeWidth" => Float::NAN } }

        include_examples "falls back to the default cell size"
      end

      context "with nodeWidth: Infinity" do
        let(:layout_option) { { "topdownpacking.nodeWidth" => Float::INFINITY } }

        include_examples "falls back to the default cell size"
      end
    end

    context "grid dimension calculations" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: { "algorithm" => "topdownpacking" },
        )
      end

      it "creates 3x3 grid for 9 nodes" do
        graph.children = (1..9).map { |i| Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 50) }
        algorithm.layout(graph)

        # Should create 3x3 grid
        unique_y = graph.children.map { |n| n.y.round }.uniq.sort
        unique_x = graph.children.map { |n| n.x.round }.uniq.sort

        expect(unique_y.size).to eq(3)
        expect(unique_x.size).to eq(3)
      end

      it "creates 4x3 grid for 10 nodes" do
        graph.children = (1..10).map { |i| Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 50) }
        algorithm.layout(graph)

        # Should create 4x3 grid (4 columns, 3 rows since sqrt(10) ≈ 3.16 -> 4 cols)
        unique_y = graph.children.map { |n| n.y.round }.uniq.sort
        unique_x = graph.children.map { |n| n.x.round }.uniq.sort

        expect(unique_x.size).to eq(4)
        expect(unique_y.size).to eq(3)
      end

      it "creates 5x5 grid for 25 nodes" do
        graph.children = (1..25).map { |i| Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 50) }
        algorithm.layout(graph)

        # Should create 5x5 grid
        unique_y = graph.children.map { |n| n.y.round }.uniq.sort
        unique_x = graph.children.map { |n| n.x.round }.uniq.sort

        expect(unique_y.size).to eq(5)
        expect(unique_x.size).to eq(5)
      end
    end
  end
end
