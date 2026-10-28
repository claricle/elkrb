# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::PortOrder do
  def order_for(**)
    bk_placer(**).last
  end

  def targets(order, item, side)
    order.visual(item, side).map { |port| port.others.map(&:item_id) }
  end

  describe "#visual" do
    let(:order) do
      order_for(layers: [%w[a], %w[b c]], edges: [%w[a b], %w[a c]])
    end

    it "lists EAST ports top to bottom in edge order" do
      expect(targets(order, "a", :east)).to eq([%w[b], %w[c]])
    end

    it "lists WEST ports top to bottom though stored bottom to top" do
      many = order_for(layers: [%w[a c], %w[b]], edges: [%w[a b], %w[c b]])

      expect(targets(many, "b", :west)).to eq([%w[c], %w[a]])
    end
  end

  describe "#sort!" do
    let(:order) do
      order_for(layers: [%w[a], %w[b c d]],
                edges: [%w[a b], %w[a c], %w[a d]])
    end
    let(:rank) { { "b" => 2, "c" => 0, "d" => 1 } }

    it "orders a list ascending by the block's value" do
      order.sort!("a", :east) { |port| rank.fetch(port.others.first.item_id) }

      expect(targets(order, "a", :east)).to eq([%w[c], %w[d], %w[b]])
    end

    it "keeps equal values in their current order" do
      order.sort!("a", :east) { |_port| 0 }

      expect(targets(order, "a", :east)).to eq([%w[b], %w[c], %w[d]])
    end

    it "shows an ascending WEST list upside down" do
      many = order_for(layers: [%w[a b c], %w[d]],
                       edges: [%w[a d], %w[b d], %w[c d]])
      many.sort!("d", :west) do |port|
        { "a" => 0, "b" => 1, "c" => 2 }.fetch(port.others.first.item_id)
      end

      expect(targets(many, "d", :west)).to eq([%w[c], %w[b], %w[a]])
    end
  end

  describe "ports" do
    it "puts declared ports first, in declaration order, then edge slots" do
      first = Elkrb::Graph::Port.new(id: "p1")
      second = Elkrb::Graph::Port.new(id: "p2")
      source = Elkrb::Graph::Node.new(id: "s", ports: [first, second])
      sink = Elkrb::Graph::Node.new(id: "t")
      graph = Elkrb::Graph::Graph.new(
        id: "root", children: [source, sink],
        edges: [
          Elkrb::Graph::Edge.new(id: "plain", sources: ["s"], targets: ["t"]),
          Elkrb::Graph::Edge.new(id: "via2", sources: ["p2"], targets: ["t"]),
          Elkrb::Graph::Edge.new(id: "via1", sources: ["p1"], targets: ["t"]),
        ]
      )
      order = described_class.new(
        [[source], [sink]], Elkrb::Layout::NodeIndex.build(graph)
      )

      expect(order.visual("s", :east).map do |port|
        port.segments.first.edge.id
      end)
        .to eq(%w[via1 via2 plain])
    end

    it "gives edges that share a declared port one slot" do
      port = Elkrb::Graph::Port.new(id: "shared")
      source = Elkrb::Graph::Node.new(id: "s", ports: [port])
      sinks = %w[t u].map { |id| Elkrb::Graph::Node.new(id: id) }
      graph = Elkrb::Graph::Graph.new(
        id: "root", children: [source, *sinks],
        edges: sinks.map do |sink|
          Elkrb::Graph::Edge.new(
            id: "to_#{sink.id}", sources: ["shared"], targets: [sink.id],
          )
        end
      )
      order = described_class.new(
        [[source], sinks], Elkrb::Layout::NodeIndex.build(graph)
      )

      expect(order.visual("s", :east).map { |slot| slot.segments.length })
        .to eq([2])
    end
  end

  describe "segments" do
    it "cuts a long edge into one segment per layer gap" do
      order = order_for(
        layers: [%w[a], %w[d1], %w[d2], %w[b]], edges: [%w[a b]],
        dummies: { "d1" => [0, 1], "d2" => [0, 2] }
      )

      expect(order.segments.map do |s|
        [s.from_port.item_id, s.to_port.item_id]
      end)
        .to eq([["a", "__elkrb_dummy_0_1"],
                ["__elkrb_dummy_0_1", "__elkrb_dummy_0_2"],
                ["__elkrb_dummy_0_2", "b"]])
    end

    it "gives a reversed edge the earlier layer as its source side" do
      order = order_for(layers: [%w[a], %w[b]], edges: [%w[b a]])

      expect(order.segments.map do |s|
        [s.from_port.item_id, s.to_port.item_id]
      end)
        .to eq([%w[a b]])
    end

    it "ignores an edge that skips a layer without a dummy there" do
      order = order_for(layers: [%w[a], %w[x], %w[b]], edges: [%w[a b]])

      expect(order.segments).to be_empty
    end

    it "ignores edges inside one layer and self-loops" do
      order = order_for(layers: [%w[a b]], edges: [%w[a b], %w[a a]])

      expect(order.segments).to be_empty
    end
  end
end
