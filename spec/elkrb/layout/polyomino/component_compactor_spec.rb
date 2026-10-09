# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Polyomino::ComponentCompactor do
  def rectangle(left, top, width, height)
    [[left, top], [left, top + height],
     [left + width, top + height], [left + width, top]]
  end

  def moved_boxes(components, offsets)
    components.zip(offsets).map do |shapes, (dx, dy)|
      xs, ys = shapes.flatten(1).transpose
      [xs.min + dx, ys.min + dy, xs.max + dx, ys.max + dy]
    end
  end

  def overlapping?(first, second)
    first[0] < second[2] && second[0] < first[2] &&
      first[1] < second[3] && second[1] < first[3]
  end

  describe "#offsets" do
    it "returns nothing for no components" do
      expect(described_class.new([], aspect_ratio: 1.0).offsets).to eq([])
    end

    it "keeps moved components clear of each other, over generated ones" do
      rng = Random.new(20_241_010)
      200.times do
        components = Array.new(rng.rand(1..9)) do
          [rectangle(rng.rand(-50..50), rng.rand(-50..50), rng.rand(5..140),
                     rng.rand(5..140))]
        end
        ratio = [1.0, 1.6, 0.5].sample(random: rng)

        boxes = moved_boxes(components,
                            described_class.new(components,
                                                aspect_ratio: ratio).offsets)

        expect(boxes.combination(2).select do |a, b|
          overlapping?(a, b)
        end).to eq([])
      end
    end

    it "counts a connecting shape as part of its component" do
      nodes = [rectangle(0, 0, 20, 20), rectangle(300, 0, 20, 20)]
      linked = [nodes + [rectangle(10, 5, 300, 10)], [rectangle(0, 0, 20, 20)]]
      unlinked = [nodes, [rectangle(0, 0, 20, 20)]]

      expect(described_class.new(linked, aspect_ratio: 1.0).offsets)
        .not_to eq(described_class.new(unlinked, aspect_ratio: 1.0).offsets)
    end
  end
end
