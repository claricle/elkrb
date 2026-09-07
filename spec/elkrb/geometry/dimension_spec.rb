# frozen_string_literal: true

require "spec_helper"
require "elkrb/geometry/dimension"

RSpec.describe Elkrb::Geometry::Dimension do
  describe "construction" do
    it "defaults both extents to zero" do
      expect([described_class.new.width, described_class.new.height])
        .to eql([0.0, 0.0])
    end

    it "coerces positional extents to floats" do
      dimension = described_class.new(30, 40)

      expect([dimension.width, dimension.height]).to eql([30.0, 40.0])
    end
  end

  describe "#area" do
    it "multiplies width by height" do
      expect(described_class.new(30.0, 40.0).area).to eq(1200.0)
    end
  end

  describe "#==" do
    it "is true for equal extents" do
      expect(described_class.new(3.0, 4.0)).to eq(described_class.new(3.0, 4.0))
    end

    it "is false for a non-dimension" do
      expect(described_class.new(3.0, 4.0)).not_to eq("3x4")
    end
  end

  describe "#to_h" do
    it "returns symbol-keyed extents" do
      expect(described_class.new(3.0, 4.0).to_h).to eq(width: 3.0, height: 4.0)
    end
  end
end
