# frozen_string_literal: true

require "spec_helper"

# Rows that need a hand-built graph rather than the table's 4-node fixture.
RSpec.describe "option plumbing, direct rows" do
  describe "elk.edgeRouting on an edge, under fixed" do
    let(:legacy) { bends({ "edge.routing" => "orthogonal" }, "fixed") }

    it "gives the bend points the private edge.routing key gave" do
      expect(bends({ "elk.edgeRouting" => "ORTHOGONAL" }, "fixed"))
        .to eq(legacy)
    end

    it "is case-insensitive, as the lowercase legacy value was" do
      expect(bends({ "elk.edgeRouting" => "orthogonal" }, "fixed"))
        .to eq(legacy)
    end

    it "bends where the unrouted edge does not" do
      orthogonal = bends({ "elk.edgeRouting" => "ORTHOGONAL" }, "fixed")

      expect([bends({}, "fixed").size, orthogonal.size]).to eq([0, 2])
    end
  end

  describe "elk.edgeRouting on the graph and on the call" do
    let(:polyline) { { "elk.edgeRouting" => "POLYLINE" } }
    let(:orthogonal) { { "elk.edgeRouting" => "ORTHOGONAL" } }

    it "lets the graph's POLYLINE beat the call's ORTHOGONAL" do
      expect(bends({}, "fixed", polyline, orthogonal)).to eq([])
    end

    it "bends where the graph says ORTHOGONAL" do
      expect(bends({}, "fixed", orthogonal).size).to eq(2)
    end
  end

  describe "elk.edgeRouting on an edge from a port to a node" do
    let(:orthogonal) { { "elk.edgeRouting" => "ORTHOGONAL" } }

    it "bends where the unrouted edge does not" do
      expect([port_to_node_bends({}).size,
              port_to_node_bends(orthogonal).size]).to eq([0, 2])
    end

    it "lets the graph's POLYLINE beat the call's ORTHOGONAL" do
      polyline = { "elk.edgeRouting" => "POLYLINE" }

      expect(port_to_node_bends({}, polyline, orthogonal)).to eq([])
    end
  end

  describe "elk.direction on an edge, under SPLINES" do
    let(:splines) { { "elk.edgeRouting" => "SPLINES" } }
    let(:down) { bends({ "elk.direction" => "DOWN" }, "fixed", splines) }

    it "reads the direction case-insensitively" do
      expect(bends({ "elk.direction" => "down" }, "fixed", splines))
        .to eq(down)
    end

    it "moves the spline's bend points" do
      expect(down).not_to eq(bends({}, "fixed", splines))
    end

    it "steers DOWN differently from RIGHT" do
      expect(down)
        .not_to eq(bends({ "elk.direction" => "RIGHT" }, "fixed", splines))
    end
  end

  describe "label.placement on a port" do
    it "places the port label as elk.portLabels.placement does" do
      expect(port_label_position({ "label.placement" => "INSIDE" }))
        .to eq(port_label_position({ "elk.portLabels.placement" => "INSIDE" }))
    end

    it "moves the port label" do
      expect(port_label_position({ "label.placement" => "INSIDE" }))
        .not_to eq(port_label_position({}))
    end

    it "beats the call's elk.portLabels.placement" do
      outside = { "elk.portLabels.placement" => "OUTSIDE" }

      expect(port_label_position({ "label.placement" => "INSIDE" }, outside))
        .to eq(port_label_position({ "label.placement" => "INSIDE" }))
    end

    it "follows the call's elk.portLabels.placement when the port names none" do
      inside = { "elk.portLabels.placement" => "INSIDE" }

      expect(port_label_position({}, inside))
        .to eq(port_label_position({ "label.placement" => "INSIDE" }))
    end

    it "is not moved by the call's elk.nodeLabels.placement" do
      inside = { "elk.nodeLabels.placement" => "INSIDE V_TOP H_LEFT" }

      expect(port_label_position({}, inside)).to eq(port_label_position({}))
    end

    it "yields to elk.portLabels.placement" do
      both = { "label.placement" => "INSIDE",
               "elk.portLabels.placement" => "OUTSIDE" }

      expect(port_label_position(both)).to eq(port_label_position({}))
    end
  end

  describe "elk.selfLoopSide" do
    let(:south) { { "elk.selfLoopSide" => "SOUTH" } }
    let(:north) { { "elk.selfLoopSide" => "NORTH" } }

    it "is read from the loop's edge" do
      expect(self_loop_bends(south, {})).not_to eq(self_loop_bends({}, {}))
    end

    it "is read from the node when the edge names none" do
      expect(self_loop_bends({}, north)).to eq(self_loop_bends(north, {}))
    end

    it "prefers the edge's side over the node's" do
      expect(self_loop_bends(south, north)).to eq(self_loop_bends(south, {}))
    end

    it "puts the two sides in different places" do
      expect(self_loop_bends(south, {})).not_to eq(self_loop_bends(north, {}))
    end
  end

  describe "elk.hierarchyHandling on a nested graph" do
    algorithms = Elkrb::Layout::AlgorithmRegistry.available_algorithms
    values = %w[INCLUDE_CHILDREN SEPARATE_CHILDREN]

    # The registry calls this :partial with the note "cross-level edges are
    # routed; no cross-level layering". Nothing reads the id, so the layout
    # is the same for every value; this pins that, so wiring the id turns the
    # row red and it has to be rewritten against what the wiring does.
    algorithms.each do |name|
      values.each do |value|
        it "#{name} lays out identically with #{value}" do
          option = { "elk.hierarchyHandling" => value }

          expect(laid_out(nested_graph(option), name))
            .to eq(laid_out(nested_graph, name))
        end
      end
    end
  end
end
