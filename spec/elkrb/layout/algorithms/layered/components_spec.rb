# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::Layered::Components::RowPacker do
  def offsets(sizes, spacing: 20.0, aspect_ratio: 1.6)
    described_class.new(sizes, spacing: spacing, aspect_ratio: aspect_ratio)
      .offsets
  end

  it "places the box with the smaller area first" do
    # Limit is 1.6 * sqrt(2600), so both fit in one row.
    expect(offsets([[50.0, 50.0], [10.0, 10.0]]))
      .to eq([[30.0, 0.0], [0.0, 0.0]])
  end

  it "keeps the given order between boxes of equal area" do
    expect(offsets([[10.0, 10.0], [10.0, 10.0]]))
      .to eq([[0.0, 0.0], [0.0, 30.0]])
  end

  it "starts a row below the box above it, smallest area first" do
    sizes = [[10.0, 10.0], [10.0, 30.0], [10.0, 20.0]]

    expect(offsets(sizes, aspect_ratio: 0.1))
      .to eq([[0.0, 0.0], [0.0, 70.0], [0.0, 30.0]])
  end

  it "starts a row below the tallest box of the row above" do
    sizes = [[10.0, 10.0], [10.0, 20.0], [10.0, 25.0]]

    expect(offsets(sizes, spacing: 5.0, aspect_ratio: 1.2))
      .to eq([[0.0, 0.0], [15.0, 0.0], [0.0, 25.0]])
  end

  it "fits a row up to sqrt(total area) times the aspect ratio" do
    sizes = [[10.0, 10.0]] * 4
    # sqrt(400) * 1.5 = 30: two boxes and their gap are 25 wide, three are 40.
    expect(offsets(sizes, spacing: 5.0, aspect_ratio: 1.5))
      .to eq([[0.0, 0.0], [15.0, 0.0], [0.0, 15.0], [15.0, 15.0]])
  end

  it "never makes a row narrower than the widest box" do
    expect(offsets([[100.0, 1.0], [10.0, 1.0]], aspect_ratio: 0.1))
      .to eq([[0.0, 21.0], [0.0, 0.0]])
  end

  it "takes the square root in single precision, as ELK does" do
    # Two 7x7 boxes: sqrt(98) rounds up in a float, so 2 * root is 19.79899...
    # and the second box fits beside the first in the float but not in a
    # double (19.798989...).
    root = [Math.sqrt(98.0)].pack("f").unpack1("f")
    gap = (2 * root) - 14.0

    expect(offsets([[7.0, 7.0], [7.0, 7.0]], spacing: gap, aspect_ratio: 2.0))
      .to eq([[0.0, 0.0], [7.0 + gap, 0.0]])
  end

  describe "#size" do
    it "is the far edge of the boxes, and at least the spacing wide" do
      packer = described_class.new([[10.0, 10.0], [10.0, 30.0]],
                                   spacing: 20.0, aspect_ratio: 5.0)

      expect(packer.size(packer.offsets)).to eq([40.0, 30.0])
    end
  end
end
