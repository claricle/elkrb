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

  def edge_with_section(label, from_x, from_y, to_x, to_y)
    section = Elkrb::Graph::EdgeSection.new(
      start_point: Elkrb::Geometry::Point.new(x: from_x, y: from_y),
      end_point: Elkrb::Geometry::Point.new(x: to_x, y: to_y),
    )
    Elkrb::Graph::Edge.new(
      sources: ["a"], targets: ["b"], labels: [label], sections: [section],
    )
  end

  describe "#place_labels" do
    context "with node labels" do
      it "leaves a label alone when no placement option is set" do
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

        expect([label.x, label.y]).to eq([0.0, 0.0])
      end

      it "centers the label in the node, relative to the node, when asked" do
        label = Elkrb::Graph::Label.new(text: "Test", width: 30, height: 20)
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 50, y: 50, width: 100, height: 100, labels: [label],
          layout_options: {
            "elk.nodeLabels.placement" => "[H_CENTER,V_CENTER,INSIDE]",
          },
        )

        placer.send(:place_labels, Elkrb::Graph::Graph.new(children: [node]))

        expect([label.x, label.y]).to eq([35.0, 40.0])
      end

      {
        "INSIDE V_TOP H_LEFT" => [5.0, 5.0],
        "INSIDE V_TOP H_CENTER" => [35.0, 5.0],
        "INSIDE V_TOP H_RIGHT" => [65.0, 5.0],
        "INSIDE V_CENTER H_LEFT" => [5.0, 40.0],
        "INSIDE V_CENTER H_RIGHT" => [65.0, 40.0],
        "INSIDE V_BOTTOM H_LEFT" => [5.0, 75.0],
        "INSIDE V_BOTTOM H_CENTER" => [35.0, 75.0],
        "[H_RIGHT,V_BOTTOM,INSIDE]" => [65.0, 75.0],
        "OUTSIDE V_TOP H_CENTER" => [35.0, -25.0],
        "OUTSIDE V_TOP H_LEFT" => [0.0, -25.0],
        "OUTSIDE V_BOTTOM H_RIGHT" => [70.0, 105.0],
        "OUTSIDE V_CENTER H_LEFT" => [-35.0, 40.0],
        "OUTSIDE V_CENTER H_RIGHT" => [105.0, 40.0],
      }.each do |placement, expected|
        it "places a #{placement} label at #{expected.inspect} of its node" do
          label = Elkrb::Graph::Label.new(text: "T", width: 30, height: 20)
          node = Elkrb::Graph::Node.new(
            id: "n1", x: 50, y: 50, width: 100, height: 100, labels: [label],
            layout_options: { "elk.nodeLabels.placement" => placement },
          )

          placer.send(:place_labels, Elkrb::Graph::Graph.new(children: [node]))

          expect([label.x, label.y]).to eq(expected)
        end
      end

      it "places multiple labels stacked" do
        label1 = Elkrb::Graph::Label.new(text: "L1", width: 30, height: 20)
        label2 = Elkrb::Graph::Label.new(text: "L2", width: 30, height: 20)

        layout_opts = {}
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
        expect([label1.y, label2.y]).to eq([5.0, 30.0])
      end

      it "places labels outside when specified" do
        label = Elkrb::Graph::Label.new(text: "Test", width: 30, height: 20)

        layout_opts = {}
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

        expect([label.x, label.y]).to eq([35.0, -25.0])
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

        # Port is on the left side: the label sits left of the port,
        # relative to the port.
        expect([label.x, label.y]).to eq([-25.0, -2.5])
      end

      it "places port labels on a node that has no labels of its own" do
        label = Elkrb::Graph::Label.new(text: "P", width: 10, height: 10)
        port = Elkrb::Graph::Port.new(
          id: "p1", x: 100, y: 30, width: 8, height: 8, labels: [label],
        )
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 12, y: 12, width: 100, height: 60, ports: [port],
        )

        placer.send(:place_labels, Elkrb::Graph::Graph.new(children: [node]))

        expect([label.x, label.y]).to eq([13.0, -1.0])
      end

      it "places an INSIDE port label on the node side of the port" do
        label = Elkrb::Graph::Label.new(text: "P", width: 10, height: 10)
        port = Elkrb::Graph::Port.new(
          id: "p1", x: 0, y: 50, width: 10, height: 10, labels: [label],
          layout_options: { "elk.portLabels.placement" => "INSIDE" },
        )
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 50, y: 50, width: 100, height: 100, ports: [port],
        )

        placer.send(:place_labels, Elkrb::Graph::Graph.new(children: [node]))

        expect([label.x, label.y]).to eq([15.0, 0.0])
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

        # Path (0,0) -> (50,50) -> (100,0) has its midpoint at the bend.
        expect([label.x, label.y]).to eq([37.5, 42.5])
      end

      it "places a HEAD label above the section's end point" do
        label = Elkrb::Graph::Label.new(
          text: "E", width: 20, height: 10,
          layout_options: { "elk.edgeLabels.placement" => "HEAD" },
        )
        edge = edge_with_section(label, 0, 0, 100, 0)

        placer.send(:place_labels, Elkrb::Graph::Graph.new(edges: [edge]))

        expect([label.x, label.y]).to eq([90.0, -15.0])
      end

      it "places a TAIL label from the edge's option above the start point" do
        label = Elkrb::Graph::Label.new(text: "E", width: 20, height: 10)
        edge = edge_with_section(label, 0, 0, 100, 0)
        edge.layout_options = { "elk.edgeLabels.placement" => "TAIL" }

        placer.send(:place_labels, Elkrb::Graph::Graph.new(edges: [edge]))

        expect([label.x, label.y]).to eq([-10.0, -15.0])
      end

      it "gives a label on a zero-length section finite coordinates" do
        label = Elkrb::Graph::Label.new(text: "E", width: 20, height: 10)
        edge = edge_with_section(label, 7, 9, 7, 9)
        graph = Elkrb::Graph::Graph.new(edges: [edge])

        placer.send(:place_labels, graph)

        expect([label.x, label.y]).to eq([-3.0, 4.0])
        expect { graph.to_json }.not_to raise_error
      end

      it "skips a zero-length segment before the midpoint" do
        label = Elkrb::Graph::Label.new(text: "E", width: 20, height: 10)
        section = Elkrb::Graph::EdgeSection.new(
          start_point: Elkrb::Geometry::Point.new(x: 0, y: 0),
          end_point: Elkrb::Geometry::Point.new(x: 100, y: 0),
          bend_points: [Elkrb::Geometry::Point.new(x: 0, y: 0)],
        )
        edge = Elkrb::Graph::Edge.new(
          sources: ["a"], targets: ["b"], labels: [label], sections: [section],
        )

        placer.send(:place_labels, Elkrb::Graph::Graph.new(edges: [edge]))

        expect([label.x, label.y]).to eq([40.0, -5.0])
      end
    end

    context "with hierarchical graphs" do
      it "lets the child-level algorithm place labels in child nodes" do
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
        placer.layout(graph)

        # No placement option: the child's label is left at its default.
        expect([child_label.x, child_label.y]).to eq([0.0, 0.0])
      end
    end

    context "with label options" do
      it "respects label padding option" do
        label = Elkrb::Graph::Label.new(text: "Test", width: 30, height: 20)

        layout_opts = {}
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
        layout_opts = {}
        layout_opts["label.margin"] = 8

        node = Elkrb::Graph::Node.new(
          id: "n1",
          layout_options: layout_opts,
        )

        expect(placer.send(:label_margin_option, node)).to eq(8)
      end
    end

    # Label.new(text: "A") runs Label#initialize, which defaults width/height
    # to 0.0 even without deserialization, so a test built that way passes on
    # the current, unfixed code and proves nothing. Label.from_hash bypasses
    # #initialize exactly like from_json does, which is what actually
    # reproduces the crash.
    context "with a label that has only text (no width/height)" do
      it "treats missing label size as 0x0 in a centered placement" do
        label = Elkrb::Graph::Label.from_hash({ text: "A" })
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 0, y: 0, width: 10, height: 10, labels: [label],
          layout_options: {
            "elk.nodeLabels.placement" => "INSIDE V_CENTER H_CENTER",
          },
        )
        graph = Elkrb::Graph::Graph.new(children: [node])

        expect { placer.send(:place_labels, graph) }.not_to raise_error
        expect(label.x).to eq(5.0)
        expect(label.y).to eq(5.0)
      end

      it "treats missing label size as 0x0 in an INSIDE TOP placement" do
        label = Elkrb::Graph::Label.from_hash({ text: "A" })
        layout_opts = {}
        layout_opts["node.label.placement"] = "INSIDE TOP"
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 0, y: 0, width: 10, height: 10,
          labels: [label], layout_options: layout_opts,
        )
        graph = Elkrb::Graph::Graph.new(children: [node])

        expect { placer.send(:place_labels, graph) }.not_to raise_error
      end

      it "treats missing label size as 0x0 in an INSIDE BOTTOM placement" do
        label = Elkrb::Graph::Label.from_hash({ text: "A" })
        layout_opts = {}
        layout_opts["node.label.placement"] = "INSIDE BOTTOM"
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 0, y: 0, width: 10, height: 10,
          labels: [label], layout_options: layout_opts,
        )
        graph = Elkrb::Graph::Graph.new(children: [node])

        expect { placer.send(:place_labels, graph) }.not_to raise_error
      end

      it "treats missing label size as 0x0 in an INSIDE LEFT placement" do
        label = Elkrb::Graph::Label.from_hash({ text: "A" })
        layout_opts = {}
        layout_opts["node.label.placement"] = "INSIDE LEFT"
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 0, y: 0, width: 10, height: 10,
          labels: [label], layout_options: layout_opts,
        )
        graph = Elkrb::Graph::Graph.new(children: [node])

        expect { placer.send(:place_labels, graph) }.not_to raise_error
      end

      it "treats missing label size as 0x0 in an INSIDE RIGHT placement" do
        label = Elkrb::Graph::Label.from_hash({ text: "A" })
        layout_opts = {}
        layout_opts["node.label.placement"] = "INSIDE RIGHT"
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 0, y: 0, width: 10, height: 10,
          labels: [label], layout_options: layout_opts,
        )
        graph = Elkrb::Graph::Graph.new(children: [node])

        expect { placer.send(:place_labels, graph) }.not_to raise_error
      end

      it "treats missing label size as 0x0 in an OUTSIDE RIGHT placement" do
        label = Elkrb::Graph::Label.from_hash({ text: "A" })
        layout_opts = {}
        layout_opts["node.label.placement"] = "OUTSIDE RIGHT"
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 0, y: 0, width: 10, height: 10,
          labels: [label], layout_options: layout_opts,
        )
        graph = Elkrb::Graph::Graph.new(children: [node])

        expect { placer.send(:place_labels, graph) }.not_to raise_error
      end
    end

    context "with a port label that has only text (no width/height)" do
      it "treats missing label size as 0x0 in the default (OUTSIDE) placement" do
        node_label = Elkrb::Graph::Label.new(text: "N", width: 5, height: 5)
        port_label = Elkrb::Graph::Label.from_hash({ text: "P" })
        port = Elkrb::Graph::Port.new(id: "p1", x: 0, y: 50, labels: [port_label])
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 50, y: 50, width: 100, height: 100,
          labels: [node_label], ports: [port],
        )
        graph = Elkrb::Graph::Graph.new(children: [node])

        expect { placer.send(:place_labels, graph) }.not_to raise_error
        # Left port, 0x0 label, 5.0 margin, 0x0 port: right at -margin.
        expect([port_label.x, port_label.y]).to eq([-5.0, 0.0])
      end

      it "treats missing label size as 0x0 in an INSIDE placement" do
        node_label = Elkrb::Graph::Label.new(text: "N", width: 5, height: 5)
        port_label = Elkrb::Graph::Label.from_hash({ text: "P" })
        port_opts = {}
        port_opts["port.label.placement"] = "INSIDE"
        port = Elkrb::Graph::Port.new(
          id: "p1", x: 0, y: 50, labels: [port_label], layout_options: port_opts,
        )
        node = Elkrb::Graph::Node.new(
          id: "n1", x: 50, y: 50, width: 100, height: 100,
          labels: [node_label], ports: [port],
        )
        graph = Elkrb::Graph::Graph.new(children: [node])

        expect { placer.send(:place_labels, graph) }.not_to raise_error
        expect([port_label.x, port_label.y]).to eq([5.0, 0.0])
      end
    end

    context "with an edge label that has only text (no width/height)" do
      it "treats missing label size as 0x0 once the edge is routed" do
        graph = Elkrb::Graph::Graph.from_json(
          '{"id":"r","children":[{"id":"a","width":10,"height":10},' \
          '{"id":"b","width":10,"height":10}],"edges":[{"id":"e",' \
          '"sources":["a"],"targets":["b"],"labels":[{"text":"E"}]}]}',
        )

        expect { Elkrb.layout(graph) }.not_to raise_error
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

      # No placement option: the label is left at its default.
      expect([label.x, label.y]).to eq([0.0, 0.0])
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
