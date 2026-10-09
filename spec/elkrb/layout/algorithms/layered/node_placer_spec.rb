# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::NodePlacer do
  describe "directional placement" do
    let(:layers) do
      [
        [Elkrb::Graph::Node.new(id: "a", width: 30.0, height: 20.0)],
        [
          Elkrb::Graph::Node.new(id: "b", width: 10.0, height: 10.0),
          Elkrb::Graph::Node.new(id: "c", width: 20.0, height: 20.0),
        ],
      ]
    end

    it "centres RIGHT layers on the cross axis" do
      described_class.new(
        Elkrb::Graph::Graph.new(id: "r"), layers,
        direction: "RIGHT", layer_spacing: 7.0, node_spacing: 5.0
      ).place_nodes

      expect(layers.flatten.map { |node| [node.x, node.y] })
        .to eq([[0.0, 7.5], [37.0, 0.0], [37.0, 15.0]])
    end

    it "maps DOWN onto y and stacks nodes along x" do
      described_class.new(
        Elkrb::Graph::Graph.new(id: "r"), layers,
        direction: "DOWN", layer_spacing: 7.0, node_spacing: 5.0
      ).place_nodes

      expect(layers.flatten.map { |node| [node.x, node.y] })
        .to eq([[2.5, 0.0], [0.0, 27.0], [15.0, 27.0]])
    end

    it "mirrors LEFT within the placed bounding box" do
      described_class.new(
        Elkrb::Graph::Graph.new(id: "r"), layers,
        direction: "LEFT", layer_spacing: 7.0, node_spacing: 5.0
      ).place_nodes

      expect(layers.flatten.map { |node| [node.x, node.y] })
        .to eq([[27.0, 7.5], [10.0, 0.0], [0.0, 15.0]])
    end

    it "mirrors UP within the placed bounding box" do
      described_class.new(
        Elkrb::Graph::Graph.new(id: "r"), layers,
        direction: "UP", layer_spacing: 7.0, node_spacing: 5.0
      ).place_nodes

      expect(layers.flatten.map { |node| [node.x, node.y] })
        .to eq([[2.5, 27.0], [0.0, 10.0], [15.0, 0.0]])
    end
  end

  describe "#calculate_layer_widths" do
    # place_nodes reads this array by layer index, so an empty layer has to
    # contribute an entry at its own position. A `return` inside the map
    # handed back a bare Integer, and Integer#[] is bit reference rather
    # than element access, so every layer read 0 without raising.
    #
    # LayerAssigner can leave only layer 0 empty, so the LEADING gap is the
    # realism anchor: the one empty-layer shape the pipeline can actually
    # produce. The INTERIOR gap is a unit contract rather than a shape the
    # pipeline builds, and it is what separates a positional 0 from one
    # prepended to a compacted list. Keep both -- they answer different
    # questions, and neither substitutes for the other.
    #
    # The layer sizes are load-bearing as well. At two nodes the multiplier
    # is evaluated at 1, so (n - 1) * spacing and a flat constant spacing
    # agree; a third node tells those apart, and a fourth refuses a clamp
    # on the gap count.
    #
    # The SINGLETON layer is the one shape a guard of `length < 2` swallows
    # while every other size still agrees, and it is the commonest layer
    # the pipeline builds -- size 1 outnumbers size 2 in a fuzz of the real
    # LayerAssigner. It sits directly after the leading gap because that is
    # the arrangement a real graph produces.
    #
    # b is 30.5 and i is 7.25, not round numbers, so the width term cannot
    # be truncated to Integer and stay green. Fractional dimensions are
    # ordinary input -- the elkt parser accepts 1.5e-3 and -8.0 -- and this
    # gem exists for output parity with elkjs and Java ELK.
    #
    # Spacing is set to 5.0 rather than left at the 20.0 default so the
    # example fails if the term stops reading the configured value.
    #
    # Every occupied total is distinct, and c is 60.0 so its layer does not
    # tie with the four-node one. Two equal totals let a swap of just those
    # two layers through: the empty positions pin the coarse shape, but
    # only distinct values pin ADJACENT order, which is what "positionally
    # aligned" claims. Keep them unequal, and keep them out of ascending
    # order -- 65.0 before 55.0 is what refuses a sort of the occupied
    # entries.
    def node(id, width)
      Elkrb::Graph::Node.new(id: id, width: width, height: 10.0)
    end

    let(:layers) do
      [
        [],
        [node("i", 7.25)],
        [node("a", 10.0), node("b", 30.5)],
        [],
        [node("c", 60.0), node("d", nil)],
        [
          node("e", 10.0),
          node("f", 10.0),
          node("g", 10.0),
          node("h", 10.0),
        ],
      ]
    end

    it "returns one width per layer, not a bare Integer" do
      placer = described_class.new(
        Elkrb::Graph::Graph.new(id: "r"),
        layers,
        node_spacing: 5.0,
      )

      expect(placer.send(:calculate_layer_widths))
        .to eq([0, 7.25, 45.5, 0, 65.0, 55.0])
    end
  end
end
