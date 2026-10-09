# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::BkNodePlacer do
  def place(alignment: :smallest, **layout)
    bk_placer(**layout).first.place(alignment: alignment)
  end

  describe "alignment" do
    it "puts the ports of a lone edge on one line" do
      # Ports sit mid-side: a's at 5 and b's at 15, so a drops 10 below b.
      expect(place(layers: [%w[a], %w[b]], edges: [%w[a b]],
                   heights: { "a" => 10, "b" => 30 }))
        .to eq("a" => 10.0, "b" => 0.0)
    end

    it "aligns a parent's first port with its first child" do
      # a's two ports sit at 10 and 20 of 30; b's single port at 15.
      expect(place(layers: [%w[a], %w[b c]], edges: [%w[a b], %w[a c]],
                   heights: { "a" => 30, "b" => 30, "c" => 30 }))
        .to eq("a" => 5.0, "b" => 0.0, "c" => 40.0)
    end

    it "aligns a child's first port with its first parent" do
      # WEST lists run bottom to top, so listing c's edge first leaves a's
      # on b's upper port (10): b = 0 + 15 - 10.
      expect(place(layers: [%w[a c], %w[b]], edges: [%w[c b], %w[a b]],
                   heights: { "a" => 30, "b" => 30, "c" => 30 }))
        .to eq("a" => 0.0, "b" => 5.0, "c" => 40.0)
    end
  end

  describe "compaction" do
    it "keeps neighbours the configured spacing apart" do
      expect(place(layers: [%w[a b]], edges: [], heights: { "a" => 10 },
                   spacing: 7.0))
        .to eq("a" => 0.0, "b" => 17.0)
    end

    it "starts every layer at zero when nothing joins them" do
      expect(place(layers: [%w[a], %w[b]], edges: [])).to eq(
        "a" => 0.0, "b" => 0.0,
      )
    end
  end

  describe "type 1 conflicts" do
    # m -> n crosses the long edge's inner segment d1 -> d2. If m and n joined
    # a block, d1 or d2 would have to leave the long edge's line.
    let(:conflict) do
      {
        layers: [%w[p x], %w[d1 m], %w[n d2], %w[q y]],
        edges: [%w[p q], %w[x m], %w[m n], %w[n y]],
        dummies: { "d1" => [0, 1], "d2" => [0, 2] },
      }
    end

    it "keeps a long edge's dummies on one line" do
      positions = place(**conflict)

      expect(positions.fetch("__elkrb_dummy_0_1"))
        .to eq(positions.fetch("__elkrb_dummy_0_2"))
    end
  end

  describe "balanced mode" do
    let(:fan_out) do
      {
        layers: [%w[a], %w[b c]], edges: [%w[a b], %w[a c]],
        heights: { "a" => 30, "b" => 30, "c" => 30 }
      }
    end

    it "takes the narrowest pass by default" do
      expect(place(**fan_out).fetch("a")).to eq(5.0)
    end

    it "takes the mean of the two middle passes when balanced" do
      # The four passes put a at 5, 35, 5 and 35 once their bounds are
      # aligned, so the mean of the middle two is 20.
      expect(place(**fan_out, alignment: :balanced).fetch("a")).to eq(20.0)
    end
  end

  describe "balanced mode across crossing edges" do
    # Four passes put a1 at 0, 50, 75 and 0 once downward passes share the
    # narrowest pass's start and upward passes its end; the mean of the
    # middle two is 25. Aligning the upward passes on the start gives 37.5.
    it "aligns upward passes on the narrowest pass's end" do
      positions = place(
        layers: [%w[a1 a2], %w[b1 b2]], edges: [%w[a1 b2], %w[a2 b1]],
        heights: { "a1" => 10, "a2" => 20, "b1" => 60, "b2" => 20 },
        alignment: :balanced
      )

      expect(positions).to eq(
        "a1" => 25.0, "a2" => 45.0, "b1" => 0.0, "b2" => 70.0,
      )
    end
  end

  it "places nothing for no layers" do
    expect(place(layers: [], edges: [])).to eq({})
  end
end
