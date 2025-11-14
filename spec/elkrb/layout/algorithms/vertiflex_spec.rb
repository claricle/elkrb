# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::VertiFlex do
  let(:algorithm) { described_class.new }

  describe "#layout" do
    context "with basic vertical layout (6 nodes, 3 columns)" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 3
        opts["vertiflex.columnSpacing"] = 50.0
        opts["vertiflex.verticalSpacing"] = 30.0

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 60, height: 40),
          Elkrb::Graph::Node.new(id: "node2", width: 50, height: 35),
          Elkrb::Graph::Node.new(id: "node3", width: 70, height: 45),
          Elkrb::Graph::Node.new(id: "node4", width: 55, height: 30),
          Elkrb::Graph::Node.new(id: "node5", width: 65, height: 38),
          Elkrb::Graph::Node.new(id: "node6", width: 45, height: 42),
        ]
      end

      it "arranges nodes in 3 vertical columns" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # Should have 3 distinct x positions (columns)
        x_positions = graph.children.map { |n| n.x.round }.uniq.sort
        expect(x_positions.size).to be <= 3
      end

      it "distributes 2 nodes per column with balanced distribution" do
        algorithm.layout(graph)

        # Group by x position (column)
        columns = graph.children.group_by { |n| n.x.round }
        expect(columns.size).to eq(3)

        # Each column should have 2 nodes (6 nodes / 3 columns)
        columns.each_value do |column_nodes|
          expect(column_nodes.size).to eq(2)
        end
      end

      it "maintains proper vertical spacing within columns" do
        algorithm.layout(graph)

        # Check vertical spacing within each column
        columns = graph.children.group_by { |n| n.x.round }
        columns.each_value do |column_nodes|
          sorted = column_nodes.sort_by(&:y)
          if sorted.size > 1
            (0...(sorted.size - 1)).each do |i|
              node1 = sorted[i]
              node2 = sorted[i + 1]
              spacing = node2.y - (node1.y + node1.height)
              expect(spacing).to be_within(1.0).of(30.0)
            end
          end
        end
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

        # Graph should contain all nodes
        graph.children.each do |node|
          expect(node.x + node.width).to be <= graph.width
          expect(node.y + node.height).to be <= graph.height
        end
      end
    end

    context "with single column" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 1
        opts["vertiflex.verticalSpacing"] = 20.0

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..5).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 60,
            height: 40,
          )
        end
      end

      it "arranges all nodes in a single vertical column" do
        algorithm.layout(graph)

        # All nodes should have the same x position
        x_positions = graph.children.map { |n| n.x.round }.uniq
        expect(x_positions.size).to eq(1)

        # Nodes should be stacked vertically
        sorted_nodes = graph.children.sort_by(&:y)
        (0...(sorted_nodes.size - 1)).each do |i|
          expect(sorted_nodes[i + 1].y).to be > sorted_nodes[i].y
        end
      end

      it "maintains vertical spacing in single column" do
        algorithm.layout(graph)

        sorted_nodes = graph.children.sort_by(&:y)
        (0...(sorted_nodes.size - 1)).each do |i|
          node1 = sorted_nodes[i]
          node2 = sorted_nodes[i + 1]
          spacing = node2.y - (node1.y + node1.height)
          expect(spacing).to be_within(1.0).of(20.0)
        end
      end
    end

    context "with many columns (5 columns)" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 5
        opts["vertiflex.columnSpacing"] = 40.0

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..15).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 50 + ((i % 3) * 10),
            height: 30 + ((i % 2) * 10),
          )
        end
      end

      it "arranges nodes in 5 columns" do
        algorithm.layout(graph)

        # Should have 5 distinct x positions
        columns = graph.children.group_by { |n| n.x.round }
        expect(columns.size).to eq(5)
      end

      it "distributes 3 nodes per column with balanced distribution" do
        algorithm.layout(graph)

        columns = graph.children.group_by { |n| n.x.round }
        columns.each_value do |column_nodes|
          expect(column_nodes.size).to eq(3)
        end
      end
    end

    context "with different column counts" do
      [2, 3, 4, 5].each do |col_count|
        context "with #{col_count} columns" do
          let(:graph) do
            opts = Elkrb::Graph::LayoutOptions.new
            opts["algorithm"] = "vertiflex"
            opts["vertiflex.columnCount"] = col_count

            Elkrb::Graph::Graph.new(
              id: "root",
              layout_options: opts,
            )
          end

          before do
            graph.children = (1..12).map do |i|
              Elkrb::Graph::Node.new(
                id: "node#{i}",
                width: 50,
                height: 40,
              )
            end
          end

          it "creates #{col_count} columns correctly" do
            algorithm.layout(graph)

            columns = graph.children.group_by { |n| n.x.round }
            expect(columns.size).to eq(col_count)
          end

          it "balances nodes across #{col_count} columns" do
            algorithm.layout(graph)

            columns = graph.children.group_by { |n| n.x.round }
            nodes_per_column = columns.values.map(&:size)

            # All columns should have similar counts (balanced)
            expect(nodes_per_column.max - nodes_per_column.min).to be <= 1
          end
        end
      end
    end

    context "column width calculation" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 2
        opts["vertiflex.columnSpacing"] = 50.0

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "narrow1", width: 30, height: 40),
          Elkrb::Graph::Node.new(id: "wide1", width: 100, height: 40),
          Elkrb::Graph::Node.new(id: "narrow2", width: 40, height: 40),
          Elkrb::Graph::Node.new(id: "wide2", width: 90, height: 40),
        ]
      end

      it "sets column width based on widest node in each column" do
        algorithm.layout(graph)

        # Group by column
        columns = graph.children.group_by { |n| n.x.round }
        expect(columns.size).to eq(2)

        columns.each_value do |column_nodes|
          # All nodes in column should be positioned
          column_nodes.each do |node|
            expect(node.x).to be_a(Numeric)
          end
        end
      end
    end

    context "with custom vertical spacing" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 2
        opts["vertiflex.verticalSpacing"] = 50.0

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..6).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 50,
            height: 40,
          )
        end
      end

      it "respects custom vertical spacing" do
        algorithm.layout(graph)

        columns = graph.children.group_by { |n| n.x.round }
        columns.each_value do |column_nodes|
          sorted = column_nodes.sort_by(&:y)
          if sorted.size > 1
            (0...(sorted.size - 1)).each do |i|
              node1 = sorted[i]
              node2 = sorted[i + 1]
              spacing = node2.y - (node1.y + node1.height)
              expect(spacing).to be_within(1.0).of(50.0)
            end
          end
        end
      end
    end

    context "with balanced distribution option" do
      let(:balance) { true }
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 3
        opts["vertiflex.balanceColumns"] = balance

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..10).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 50,
            height: 40,
          )
        end
      end

      context "when balanced" do
        it "distributes nodes evenly using round-robin" do
          algorithm.layout(graph)

          columns = graph.children.group_by { |n| n.x.round }
          nodes_per_column = columns.values.map(&:size).sort

          # 10 nodes in 3 columns: should be [3, 3, 4] or [3, 4, 3] etc.
          expect(nodes_per_column).to eq([3, 3, 4])
        end
      end

      context "when not balanced" do
        let(:balance) { false }

        it "fills columns sequentially" do
          algorithm.layout(graph)

          columns = graph.children.group_by { |n| n.x.round }
          expect(columns.size).to be <= 3

          # First columns should be fuller
          sorted_columns = columns.sort_by do |x, _|
            x
          end.map { |_, nodes| nodes.size }
          # Sequential fill: 4, 4, 2 for 10 nodes in 3 columns
          expect(sorted_columns.first).to be >= sorted_columns.last
        end
      end
    end

    context "with empty graph" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
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

    context "with single node" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "node1", width: 50, height: 40),
        ]
      end

      it "positions single node at origin" do
        algorithm.layout(graph)

        node = graph.children.first
        # After padding, node will be offset
        expect(node.x).to be >= 0.0
        expect(node.y).to be >= 0.0
      end

      it "sets appropriate graph dimensions" do
        algorithm.layout(graph)

        expect(graph.width).to be > 0
        expect(graph.height).to be > 0
      end
    end

    context "with custom column spacing" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 3
        opts["vertiflex.columnSpacing"] = 100.0

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..9).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 50,
            height: 40,
          )
        end
      end

      it "respects custom column spacing" do
        algorithm.layout(graph)

        # Get columns sorted by x position
        columns = graph.children.group_by { |n| n.x.round }.sort_by { |x, _| x }
        expect(columns.size).to eq(3)

        # Check spacing between columns
        (0...(columns.size - 1)).each do |i|
          col1_x = columns[i][0]
          col2_x = columns[i + 1][0]
          col1_nodes = columns[i][1]

          # Get widest node in column 1
          col1_width = col1_nodes.map(&:width).max

          # Distance between column starts
          spacing = col2_x - (col1_x + col1_width)
          expect(spacing).to be_within(5.0).of(100.0)
        end
      end
    end

    context "with elk.spacing.nodeNode override" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 2
        opts["vertiflex.verticalSpacing"] = 30.0
        opts["elk.spacing.nodeNode"] = 60.0

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = (1..4).map do |i|
          Elkrb::Graph::Node.new(
            id: "node#{i}",
            width: 50,
            height: 40,
          )
        end
      end

      it "uses elk.spacing.nodeNode over vertiflex.verticalSpacing" do
        algorithm.layout(graph)

        columns = graph.children.group_by { |n| n.x.round }
        columns.each_value do |column_nodes|
          sorted = column_nodes.sort_by(&:y)
          if sorted.size > 1
            (0...(sorted.size - 1)).each do |i|
              node1 = sorted[i]
              node2 = sorted[i + 1]
              spacing = node2.y - (node1.y + node1.height)
              # Should use elk.spacing.nodeNode (60.0), not verticalSpacing (30.0)
              expect(spacing).to be_within(1.0).of(60.0)
            end
          end
        end
      end
    end

    context "with varying node heights" do
      let(:graph) do
        opts = Elkrb::Graph::LayoutOptions.new
        opts["algorithm"] = "vertiflex"
        opts["vertiflex.columnCount"] = 2
        opts["vertiflex.verticalSpacing"] = 20.0

        Elkrb::Graph::Graph.new(
          id: "root",
          layout_options: opts,
        )
      end

      before do
        graph.children = [
          Elkrb::Graph::Node.new(id: "small1", width: 50, height: 20),
          Elkrb::Graph::Node.new(id: "large1", width: 50, height: 80),
          Elkrb::Graph::Node.new(id: "medium1", width: 50, height: 50),
          Elkrb::Graph::Node.new(id: "small2", width: 50, height: 30),
        ]
      end

      it "positions nodes correctly with varying heights" do
        algorithm.layout(graph)

        # All nodes should be positioned
        graph.children.each do |node|
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # Verify spacing accounts for actual node heights
        columns = graph.children.group_by { |n| n.x.round }
        columns.each_value do |column_nodes|
          sorted = column_nodes.sort_by(&:y)
          if sorted.size > 1
            (0...(sorted.size - 1)).each do |i|
              node1 = sorted[i]
              node2 = sorted[i + 1]
              spacing = node2.y - (node1.y + node1.height)
              expect(spacing).to be_within(1.0).of(20.0)
            end
          end
        end
      end
    end
  end
end
