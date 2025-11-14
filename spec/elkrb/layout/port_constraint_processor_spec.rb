# frozen_string_literal: true

require "spec_helper"
require "elkrb/graph/graph"
require "elkrb/graph/node"
require "elkrb/graph/port"
require "elkrb/layout/port_constraint_processor"

RSpec.describe Elkrb::Layout::PortConstraintProcessor do
  # Create a test class that includes the module
  let(:processor_class) do
    Class.new do
      include Elkrb::Layout::PortConstraintProcessor
    end
  end

  let(:processor) { processor_class.new }

  describe "#apply_port_constraints" do
    let(:graph) { Elkrb::Graph::Graph.new }

    context "when graph has no children" do
      it "does not raise error" do
        expect { processor.apply_port_constraints(graph) }.not_to raise_error
      end
    end

    context "when graph has nodes with ports" do
      let(:node) do
        Elkrb::Graph::Node.new(
          id: "n1",
          width: 100,
          height: 60,
          ports: [
            Elkrb::Graph::Port.new(id: "p1", x: 10, y: 0),
            Elkrb::Graph::Port.new(id: "p2", x: 90, y: 60),
          ],
        )
      end

      before do
        graph.children = [node]
      end

      it "processes all node ports" do
        processor.apply_port_constraints(graph)

        expect(node.ports[0].side).not_to eq(Elkrb::Graph::Port::UNDEFINED)
        expect(node.ports[1].side).not_to eq(Elkrb::Graph::Port::UNDEFINED)
      end

      it "assigns indices to ports" do
        processor.apply_port_constraints(graph)

        expect(node.ports[0].index).to be >= 0
        expect(node.ports[1].index).to be >= 0
      end
    end
  end

  describe "#detect_port_sides" do
    let(:node) do
      Elkrb::Graph::Node.new(
        id: "n1",
        width: 100,
        height: 60,
      )
    end

    context "with ports on different sides" do
      before do
        node.ports = [
          Elkrb::Graph::Port.new(id: "p1", x: 50, y: 0),    # Top
          Elkrb::Graph::Port.new(id: "p2", x: 50, y: 60),   # Bottom
          Elkrb::Graph::Port.new(id: "p3", x: 0, y: 30),    # Left
          Elkrb::Graph::Port.new(id: "p4", x: 100, y: 30), # Right
        ]
      end

      it "detects NORTH side for top ports" do
        processor.send(:detect_port_sides, node)
        expect(node.ports[0].side).to eq(Elkrb::Graph::Port::NORTH)
      end

      it "detects SOUTH side for bottom ports" do
        processor.send(:detect_port_sides, node)
        expect(node.ports[1].side).to eq(Elkrb::Graph::Port::SOUTH)
      end

      it "detects WEST side for left ports" do
        processor.send(:detect_port_sides, node)
        expect(node.ports[2].side).to eq(Elkrb::Graph::Port::WEST)
      end

      it "detects EAST side for right ports" do
        processor.send(:detect_port_sides, node)
        expect(node.ports[3].side).to eq(Elkrb::Graph::Port::EAST)
      end
    end

    context "with explicitly set sides" do
      before do
        node.ports = [
          Elkrb::Graph::Port.new(id: "p1", x: 50, y: 30, side: "WEST"),
        ]
      end

      it "does not override explicitly set sides" do
        processor.send(:detect_port_sides, node)
        expect(node.ports[0].side).to eq(Elkrb::Graph::Port::WEST)
      end
    end

    context "with corner positions" do
      before do
        node.ports = [
          Elkrb::Graph::Port.new(id: "p1", x: 10, y: 10),   # Top-left corner
          Elkrb::Graph::Port.new(id: "p2", x: 90, y: 10),   # Top-right corner
          Elkrb::Graph::Port.new(id: "p3", x: 10, y: 50),   # Bottom-left corner
          Elkrb::Graph::Port.new(id: "p4", x: 90, y: 50), # Bottom-right corner
        ]
      end

      it "assigns ports to nearest side for top-left" do
        processor.send(:detect_port_sides, node)
        # Should be NORTH or WEST (whichever is closer)
        expect([Elkrb::Graph::Port::NORTH, Elkrb::Graph::Port::WEST])
          .to include(node.ports[0].side)
      end

      it "assigns ports to nearest side for top-right" do
        processor.send(:detect_port_sides, node)
        expect([Elkrb::Graph::Port::NORTH, Elkrb::Graph::Port::EAST])
          .to include(node.ports[1].side)
      end

      it "assigns ports to nearest side for bottom-left" do
        processor.send(:detect_port_sides, node)
        expect([Elkrb::Graph::Port::SOUTH, Elkrb::Graph::Port::WEST])
          .to include(node.ports[2].side)
      end

      it "assigns ports to nearest side for bottom-right" do
        processor.send(:detect_port_sides, node)
        expect([Elkrb::Graph::Port::SOUTH, Elkrb::Graph::Port::EAST])
          .to include(node.ports[3].side)
      end
    end
  end

  describe "#group_ports_by_side" do
    let(:ports) do
      [
        Elkrb::Graph::Port.new(id: "p1", side: "NORTH"),
        Elkrb::Graph::Port.new(id: "p2", side: "NORTH"),
        Elkrb::Graph::Port.new(id: "p3", side: "SOUTH"),
        Elkrb::Graph::Port.new(id: "p4", side: "EAST"),
      ]
    end

    it "groups ports by side" do
      grouped = processor.send(:group_ports_by_side, ports)
      expect(grouped.keys).to contain_exactly("NORTH", "SOUTH", "EAST")
    end

    it "groups multiple ports on same side" do
      grouped = processor.send(:group_ports_by_side, ports)
      expect(grouped["NORTH"].length).to eq(2)
    end

    it "groups single port on side" do
      grouped = processor.send(:group_ports_by_side, ports)
      expect(grouped["SOUTH"].length).to eq(1)
      expect(grouped["EAST"].length).to eq(1)
    end
  end

  describe "#order_ports_on_side" do
    let(:node) do
      Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60)
    end

    context "with NORTH side ports" do
      let(:ports) do
        [
          Elkrb::Graph::Port.new(id: "p1", x: 70, index: -1),
          Elkrb::Graph::Port.new(id: "p2", x: 30, index: -1),
          Elkrb::Graph::Port.new(id: "p3", x: 50, index: -1),
        ]
      end

      it "orders ports by x position" do
        processor.send(:order_ports_on_side, node, "NORTH", ports)
        expect(ports.map(&:id)).to eq(["p2", "p3", "p1"])
      end

      it "assigns sequential indices" do
        processor.send(:order_ports_on_side, node, "NORTH", ports)
        expect(ports.map(&:index)).to eq([0, 1, 2])
      end
    end

    context "with WEST side ports" do
      let(:ports) do
        [
          Elkrb::Graph::Port.new(id: "p1", y: 40, index: -1),
          Elkrb::Graph::Port.new(id: "p2", y: 10, index: -1),
          Elkrb::Graph::Port.new(id: "p3", y: 25, index: -1),
        ]
      end

      it "orders ports by y position" do
        processor.send(:order_ports_on_side, node, "WEST", ports)
        expect(ports.map(&:id)).to eq(["p2", "p3", "p1"])
      end

      it "assigns sequential indices" do
        processor.send(:order_ports_on_side, node, "WEST", ports)
        expect(ports.map(&:index)).to eq([0, 1, 2])
      end
    end

    context "with explicit indices" do
      let(:ports) do
        [
          Elkrb::Graph::Port.new(id: "p1", x: 30, index: 2),
          Elkrb::Graph::Port.new(id: "p2", x: 70, index: 0),
          Elkrb::Graph::Port.new(id: "p3", x: 50, index: 1),
        ]
      end

      it "orders ports by index" do
        processor.send(:order_ports_on_side, node, "NORTH", ports)
        expect(ports.map(&:id)).to eq(["p2", "p3", "p1"])
      end

      it "preserves explicit indices" do
        processor.send(:order_ports_on_side, node, "NORTH", ports)
        expect(ports.map(&:index)).to eq([0, 1, 2])
      end
    end

    context "with mixed explicit and implicit indices" do
      let(:ports) do
        [
          Elkrb::Graph::Port.new(id: "p1", x: 30, index: -1),
          Elkrb::Graph::Port.new(id: "p2", x: 70, index: 0),
          Elkrb::Graph::Port.new(id: "p3", x: 50, index: -1),
        ]
      end

      it "prioritizes explicit indices over position" do
        processor.send(:order_ports_on_side, node, "NORTH", ports)
        expect(ports.first.id).to eq("p2")
      end
    end
  end

  describe "#position_ports_on_boundaries" do
    let(:node) do
      Elkrb::Graph::Node.new(id: "n1", width: 120, height: 80)
    end

    context "with NORTH side ports" do
      let(:ports_by_side) do
        {
          "NORTH" => [
            Elkrb::Graph::Port.new(id: "p1", index: 0),
            Elkrb::Graph::Port.new(id: "p2", index: 1),
            Elkrb::Graph::Port.new(id: "p3", index: 2),
          ],
        }
      end

      it "positions ports on top edge" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        ports_by_side["NORTH"].each do |port|
          expect(port.y).to eq(0)
        end
      end

      it "distributes ports evenly" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        x_positions = ports_by_side["NORTH"].map(&:x)
        expect(x_positions).to eq([30.0, 60.0, 90.0])
      end

      it "sets port offsets" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        ports_by_side["NORTH"].each do |port|
          expect(port.offset).to eq(port.x)
        end
      end
    end

    context "with SOUTH side ports" do
      let(:ports_by_side) do
        {
          "SOUTH" => [
            Elkrb::Graph::Port.new(id: "p1", index: 0),
            Elkrb::Graph::Port.new(id: "p2", index: 1),
          ],
        }
      end

      it "positions ports on bottom edge" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        ports_by_side["SOUTH"].each do |port|
          expect(port.y).to eq(80)
        end
      end

      it "distributes ports evenly" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        x_positions = ports_by_side["SOUTH"].map(&:x)
        expect(x_positions).to eq([40.0, 80.0])
      end
    end

    context "with WEST side ports" do
      let(:ports_by_side) do
        {
          "WEST" => [
            Elkrb::Graph::Port.new(id: "p1", index: 0),
            Elkrb::Graph::Port.new(id: "p2", index: 1),
          ],
        }
      end

      it "positions ports on left edge" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        ports_by_side["WEST"].each do |port|
          expect(port.x).to eq(0)
        end
      end

      it "distributes ports evenly" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        y_positions = ports_by_side["WEST"].map(&:y)
        expect(y_positions).to(be_all { |y| y > 0 && y < 80 })
      end

      it "sets port offsets" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        ports_by_side["WEST"].each do |port|
          expect(port.offset).to eq(port.y)
        end
      end
    end

    context "with EAST side ports" do
      let(:ports_by_side) do
        {
          "EAST" => [
            Elkrb::Graph::Port.new(id: "p1", index: 0),
            Elkrb::Graph::Port.new(id: "p2", index: 1),
            Elkrb::Graph::Port.new(id: "p3", index: 2),
          ],
        }
      end

      it "positions ports on right edge" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        ports_by_side["EAST"].each do |port|
          expect(port.x).to eq(120)
        end
      end

      it "distributes ports evenly" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)
        y_positions = ports_by_side["EAST"].map(&:y)
        expect(y_positions).to eq([20.0, 40.0, 60.0])
      end
    end

    context "with ports on all sides" do
      let(:ports_by_side) do
        {
          "NORTH" => [Elkrb::Graph::Port.new(id: "p1", index: 0)],
          "SOUTH" => [Elkrb::Graph::Port.new(id: "p2", index: 0)],
          "WEST" => [Elkrb::Graph::Port.new(id: "p3", index: 0)],
          "EAST" => [Elkrb::Graph::Port.new(id: "p4", index: 0)],
        }
      end

      it "positions all ports correctly" do
        processor.send(:position_ports_on_boundaries, node, ports_by_side)

        expect(ports_by_side["NORTH"][0].y).to eq(0)
        expect(ports_by_side["SOUTH"][0].y).to eq(80)
        expect(ports_by_side["WEST"][0].x).to eq(0)
        expect(ports_by_side["EAST"][0].x).to eq(120)
      end
    end
  end

  describe "#process_node_ports" do
    let(:node) do
      Elkrb::Graph::Node.new(
        id: "n1",
        width: 100,
        height: 60,
        ports: [
          Elkrb::Graph::Port.new(id: "p1", x: 25, y: 0),
          Elkrb::Graph::Port.new(id: "p2", x: 75, y: 0),
          Elkrb::Graph::Port.new(id: "p3", x: 0, y: 30),
        ],
      )
    end

    it "detects sides, orders, and positions ports" do
      processor.send(:process_node_ports, node)

      # Ports should have sides detected
      expect(node.ports.all? { |p| p.side != "UNDEFINED" }).to be true

      # Ports should have indices
      expect(node.ports.all? { |p| p.index >= 0 }).to be true

      # Ports should have updated positions
      north_ports = node.ports.select { |p| p.side == "NORTH" }
      expect(north_ports.all? { |p| p.y == 0 }).to be true
    end

    context "when node has no ports" do
      let(:node_no_ports) do
        Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60)
      end

      it "does not raise error" do
        expect do
          processor.send(:process_node_ports, node_no_ports)
        end.not_to raise_error
      end
    end

    context "when node has zero dimensions" do
      let(:node_zero_dims) do
        Elkrb::Graph::Node.new(
          id: "n1",
          width: 0,
          height: 0,
          ports: [Elkrb::Graph::Port.new(id: "p1")],
        )
      end

      it "does not process ports" do
        processor.send(:process_node_ports, node_zero_dims)
        expect(node_zero_dims.ports[0].side).to eq("UNDEFINED")
      end
    end
  end
end
