# frozen_string_literal: true

require "spec_helper"
require "elkrb/geometry/rectangle"

RSpec.describe Elkrb::Geometry::Rectangle do
  subject(:rect) { described_class.new(1.0, 2.0, 30.0, 40.0) }

  describe "#position" do
    it "returns the origin as a Point" do
      expect(rect.position).to eq(Elkrb::Geometry::Point.new(x: 1.0, y: 2.0))
    end

    it "returns a Point instance" do
      expect(rect.position).to be_a(Elkrb::Geometry::Point)
    end
  end

  describe "#center" do
    it "returns the midpoint as a Point" do
      expect(rect.center).to eq(Elkrb::Geometry::Point.new(x: 16.0, y: 22.0))
    end

    it "returns a Point instance" do
      expect(rect.center).to be_a(Elkrb::Geometry::Point)
    end
  end

  describe "#size" do
    it "returns the extent as a Dimension" do
      expect(rect.size).to eq(Elkrb::Geometry::Dimension.new(30.0, 40.0))
    end
  end

  describe "edges" do
    it "reports left, right, top and bottom" do
      expect([rect.left, rect.right, rect.top, rect.bottom])
        .to eql([1.0, 31.0, 2.0, 42.0])
    end
  end

  describe "#area" do
    it "multiplies width by height" do
      expect(rect.area).to eq(1200.0)
    end
  end

  describe "#contains?" do
    it "is true for an interior point" do
      expect(rect.contains?(Elkrb::Geometry::Point.new(x: 10.0, y: 10.0)))
        .to be true
    end

    it "is false for a point outside" do
      expect(rect.contains?(Elkrb::Geometry::Point.new(x: 100.0, y: 10.0)))
        .to be false
    end
  end

  describe "#intersects?" do
    it "is true for an overlapping rectangle" do
      expect(rect.intersects?(described_class.new(10.0, 10.0, 5.0, 5.0)))
        .to be true
    end

    it "is false for a disjoint rectangle" do
      expect(rect.intersects?(described_class.new(500.0, 500.0, 5.0, 5.0)))
        .to be false
    end
  end
end
