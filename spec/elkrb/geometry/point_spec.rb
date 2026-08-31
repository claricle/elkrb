# frozen_string_literal: true

require "spec_helper"
require "elkrb/geometry/point"

RSpec.describe Elkrb::Geometry::Point do
  describe "construction" do
    it "defaults both coordinates to zero" do
      point = described_class.new

      expect(point.x).to eq(0.0)
      expect(point.y).to eq(0.0)
    end

    it "accepts keyword coordinates" do
      point = described_class.new(x: 3.0, y: 4.0)

      expect(point.x).to eq(3.0)
      expect(point.y).to eq(4.0)
    end

    it "rejects positional coordinates" do
      expect { described_class.new(1.0, 2.0) }.to raise_error(ArgumentError)
    end
  end

  # The three serialization invariants the initialize shape rests on. Deleting
  # `initialize` outright breaks the first. The second is the point of Do 4's
  # second half: the branch that was removed WAS reachable -- an unknown
  # keyword hit it and produced a fictitious (0,0) -- so restoring it turns
  # that example red.
  describe "serialization of a bare instance" do
    it "renders explicit zeros when built with no arguments" do
      expect(JSON.parse(described_class.new.to_json))
        .to eq("x" => 0.0, "y" => 0.0)
    end

    it "renders nothing when built with only unknown keywords" do
      expect(JSON.parse(described_class.new(foo: 1).to_json)).to eq({})
    end

    # The missing coordinate IS defaulted internally -- Point.new(x: 1).y is
    # 0.0 -- it is only omitted from the serialized output, because a default
    # lutaml never marked as set does not render. Pinned because it is
    # surprising and no card owns it, so a later change is deliberate.
    it "renders only the coordinate it was given" do
      expect(JSON.parse(described_class.new(x: 1.0).to_json)).to eq("x" => 1.0)
    end
  end

  describe "arithmetic" do
    let(:a) { described_class.new(x: 1.0, y: 2.0) }
    let(:b) { described_class.new(x: 4.0, y: 6.0) }

    it "adds coordinatewise" do
      expect(a + b).to eq(described_class.new(x: 5.0, y: 8.0))
    end

    it "subtracts coordinatewise" do
      expect(b - a).to eq(described_class.new(x: 3.0, y: 4.0))
    end

    it "scales by a factor" do
      expect(a * 3).to eq(described_class.new(x: 3.0, y: 6.0))
    end

    it "divides by a factor" do
      expect(b / 2).to eq(described_class.new(x: 2.0, y: 3.0))
    end

    it "measures distance to another point" do
      expect(a.distance_to(b)).to eql(5.0)
    end
  end

  describe "#==" do
    it "is true for equal coordinates" do
      expect(described_class.new(x: 1.0, y: 2.0))
        .to eq(described_class.new(x: 1.0, y: 2.0))
    end

    it "is false for a non-point" do
      expect(described_class.new(x: 1.0, y: 2.0)).not_to eq("1,2")
    end
  end

  describe "#to_h" do
    it "returns symbol-keyed coordinates" do
      expect(described_class.new(x: 1.0, y: 2.0).to_h).to eql(x: 1.0, y: 2.0)
    end
  end
end
