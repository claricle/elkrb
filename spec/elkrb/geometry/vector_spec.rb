# frozen_string_literal: true

require "spec_helper"
require "elkrb/geometry/vector"

RSpec.describe Elkrb::Geometry::Vector do
  describe "construction" do
    it "defaults both components to zero" do
      expect([described_class.new.x, described_class.new.y]).to eql([0.0, 0.0])
    end

    it "coerces positional components to floats" do
      vector = described_class.new(3, 4)

      expect([vector.x, vector.y]).to eql([3.0, 4.0])
    end
  end

  describe "arithmetic" do
    let(:a) { described_class.new(1.0, 2.0) }
    let(:b) { described_class.new(4.0, 6.0) }

    it "adds componentwise" do
      expect(a + b).to eq(described_class.new(5.0, 8.0))
    end

    it "subtracts componentwise" do
      expect(b - a).to eq(described_class.new(3.0, 4.0))
    end

    it "scales by a factor" do
      expect(a * 3).to eq(described_class.new(3.0, 6.0))
    end
  end

  describe "#==" do
    it "is true for equal components" do
      expect(described_class.new(1.0, 2.0)).to eq(described_class.new(1.0, 2.0))
    end

    it "is false for a non-vector" do
      expect(described_class.new(1.0, 2.0)).not_to eq("1,2")
    end
  end
end
