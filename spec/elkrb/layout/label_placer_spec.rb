# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::LabelPlacer do
  let(:placer_class) do
    Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
      def layout_flat(graph, _options = {})
        # Simple positioning for testing
        graph.children&.each_with_index do |node, index|
          node.x = index * 100.0
          node.y = 0.0
        end
        graph
      end
    end
  end

  let(:placer) { placer_class.new }

  describe "#place_labels" do
    context "with node labels" do
      it "places labels in the center by default" do
        label = Elkrb::Graph::Label.new(
          text: "Test",
          width: 30,
          height: 20,
        )

        node = Elkrb::Graph::Node.new(
          id: "n1",
          x: 50,
          y: 50,
          width: 100,
          height: 100,
          labels: [label],
        )

        graph = Elkrb::Graph::Graph.new(children: [node])

        placer.send(:place_labels, graph)

        # Label should be centered in node
        expect(label.x).to eq(50 + ((100 - 30) / 2.0))
        expect(label.y).to eq(50 + ((100 - 20) / 2.0))
      end

      it "places multiple labels stacked" do
        label1 = Elkrb::Graph::Label.new(text: "L1", width: 30, height: 20)
        label2 = Elkrb::Graph::Label.new(text: "L2", width: 30, height: 20)

        layout_opts = Elkrb::Graph::LayoutOptions.new
        layout_opts["node.label.placement"] = "INSIDE TOP"

        node = Elkrb::Graph::Node.new(
          id: "n1",
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          labels: [label1, label2],
          layout_options: layout_opts,
        )

        graph = Elkrb::Graph::Graph.new(children: [node])
        placer.send(:place_labels, graph)

        # Labels should be stacked vertically
        expect(label1.y).to be < label2.y
      end

      it "places labels outside when specified" do
        label = Elkrb::Graph::Label.new(text: "Test", width: 30, height: 20)

        layout_opts = Elkrb::Graph::LayoutOptions.new
        layout_opts["node.label.placement"] = "OUTSIDE TOP"

        node = Elkrb::Graph::Node.new(
          id: "n1",
          x: 50,
          y: 50,
          width: 100,
          height: 100,
          labels: [label],
          layout_options: layout_opts,
        )

        graph = Elkrb::Graph::Graph.new(children: [node])
        placer.send(:place_labels, graph)

        # Label should be above the node
        expect(label.y).to be < 50
      end
    end

    context "with port labels" do
      it "places port labels outside by default" do
        label = Elkrb::Graph::Label.new(text: "P1", width: 20, height: 15)

        port = Elkrb::Graph::Port.new(
          id: "p1",
          x: 0,
          y: 50,
          width: 10,
          height: 10,
          labels: [label],
        )

        node = Elkrb::Graph::Node.new(
          id: "n1",
          x: 50,
          y: 50,
          width: 100,
          height: 100,
          ports: [port],
        )

        graph = Elkrb::Graph::Graph.new(children: [node])
        placer.send(:place_labels, graph)

        # Port is on left side, label should be to the left
        expect(label.x).to be < 50
      end

      it "determines port side correctly" do
        node = Elkrb::Graph::Node.new(
          id: "n1",
          width: 100,
          height: 100,
        )

        # Port on left
        port_left = Elkrb::Graph::Port.new(x: 0, y: 50)
        expect(placer.send(:port_side, node, port_left)).to eq(:left)

        # Port on right
        port_right = Elkrb::Graph::Port.new(x: 100, y: 50)
        expect(placer.send(:port_side, node, port_right)).to eq(:right)

        # Port on top
        port_top = Elkrb::Graph::Port.new(x: 50, y: 0)
        expect(placer.send(:port_side, node, port_top)).to eq(:top)

        # Port on bottom
        port_bottom = Elkrb::Graph::Port.new(x: 50, y: 100)
        expect(placer.send(:port_side, node, port_bottom)).to eq(:bottom)
      end
    end

    context "with edge labels" do
      it "places edge labels at the center of edge path" do
        label = Elkrb::Graph::Label.new(text: "E1", width: 25, height: 15)

        section = Elkrb::Graph::EdgeSection.new(
          start_point: Elkrb::Geometry::Point.new(x: 0, y: 0),
          end_point: Elkrb::Geometry::Point.new(x: 100, y: 100),
        )

        edge = Elkrb::Graph::Edge.new(
          sources: ["n1"],
          targets: ["n2"],
          labels: [label],
          sections: [section],
        )

        graph = Elkrb::Graph::Graph.new(edges: [edge])
        placer.send(:place_labels, graph)

        # Label should be near the center of the edge
        expect(label.x).to be_within(5).of(50 - (25 / 2.0))
        expect(label.y).to be_within(5).of(50 - (15 / 2.0))
      end

      it "handles edges with bend points" do
        label = Elkrb::Graph::Label.new(text: "E1", width: 25, height: 15)

        section = Elkrb::Graph::EdgeSection.new(
          start_point: Elkrb::Geometry::Point.new(x: 0, y: 0),
          end_point: Elkrb::Geometry::Point.new(x: 100, y: 0),
          bend_points: [
            Elkrb::Geometry::Point.new(x: 50, y: 50),
          ],
        )

        edge = Elkrb::Graph::Edge.new(
          sources: ["n1"],
          targets: ["n2"],
          labels: [label],
          sections: [section],
        )

        graph = Elkrb::Graph::Graph.new(edges: [edge])
        placer.send(:place_labels, graph)

        # Label position should be calculated
        expect(label.x).not_to be_nil
        expect(label.y).not_to be_nil
      end
    end

    context "with hierarchical graphs" do
      it "recursively places labels in child nodes" do
        child_label = Elkrb::Graph::Label.new(
          text: "Child",
          width: 30,
          height: 20,
        )

        child_node = Elkrb::Graph::Node.new(
          id: "child",
          x: 10,
          y: 10,
          width: 50,
          height: 50,
          labels: [child_label],
        )

        parent_node = Elkrb::Graph::Node.new(
          id: "parent",
          x: 0,
          y: 0,
          width: 200,
          height: 200,
          children: [child_node],
        )

        graph = Elkrb::Graph::Graph.new(children: [parent_node])
        placer.send(:place_labels, graph)

        # Child label should be positioned
        expect(child_label.x).not_to be_nil
        expect(child_label.y).not_to be_nil
      end
    end

    context "with label options" do
      it "respects label padding option" do
        label = Elkrb::Graph::Label.new(text: "Test", width: 30, height: 20)

        layout_opts = Elkrb::Graph::LayoutOptions.new
        layout_opts["node.label.placement"] = "INSIDE TOP"
        layout_opts["label.padding"] = 10

        node = Elkrb::Graph::Node.new(
          id: "n1",
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          labels: [label],
          layout_options: layout_opts,
        )

        expect(placer.send(:label_padding_option, node)).to eq(10)
      end

      it "respects label margin option" do
        layout_opts = Elkrb::Graph::LayoutOptions.new
        layout_opts["label.margin"] = 8

        node = Elkrb::Graph::Node.new(
          id: "n1",
          layout_options: layout_opts,
        )

        expect(placer.send(:label_margin_option, node)).to eq(8)
      end
    end
  end

  describe "integration with algorithms" do
    it "automatically places labels after layout" do
      label = Elkrb::Graph::Label.new(text: "Test", width: 30, height: 20)

      node = Elkrb::Graph::Node.new(
        id: "n1",
        width: 100,
        height: 100,
        labels: [label],
      )

      graph = Elkrb::Graph::Graph.new(children: [node])

      # Layout should trigger label placement
      placer.layout(graph)

      # Label should be positioned
      expect(label.x).not_to be_nil
      expect(label.y).not_to be_nil
    end

    it "allows disabling label placement" do
      label = Elkrb::Graph::Label.new(text: "Test", width: 30, height: 20)

      node = Elkrb::Graph::Node.new(
        id: "n1",
        width: 100,
        height: 100,
        labels: [label],
      )

      graph = Elkrb::Graph::Graph.new(children: [node])

      # Store initial label coordinates
      initial_x = label.x
      initial_y = label.y

      # Layout with label placement disabled
      placer_disabled = placer_class.new("label.placement.disabled" => true)
      placer_disabled.layout(graph)

      # Labels should keep their initial coordinates (not repositioned)
      expect(label.x).to eq(initial_x)
      expect(label.y).to eq(initial_y)
    end
  end
end
