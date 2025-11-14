# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Elkrb::Options" do
  describe Elkrb::Options::ElkPadding do
    describe ".parse" do
      it "parses padding from string" do
        padding = described_class.parse("[left=2, top=3, right=4, bottom=5]")
        expect(padding.left).to eq(2.0)
        expect(padding.top).to eq(3.0)
        expect(padding.right).to eq(4.0)
        expect(padding.bottom).to eq(5.0)
      end

      it "parses padding from hash with symbol keys" do
        padding = described_class.parse(
          left: 10, top: 20, right: 30, bottom: 40,
        )
        expect(padding.left).to eq(10.0)
        expect(padding.top).to eq(20.0)
        expect(padding.right).to eq(30.0)
        expect(padding.bottom).to eq(40.0)
      end

      it "parses padding from hash with string keys" do
        padding = described_class.parse(
          "left" => 5, "top" => 6, "right" => 7, "bottom" => 8,
        )
        expect(padding.left).to eq(5.0)
        expect(padding.top).to eq(6.0)
        expect(padding.right).to eq(7.0)
        expect(padding.bottom).to eq(8.0)
      end

      it "returns same object if already ElkPadding" do
        original = described_class.new(left: 1, top: 2, right: 3, bottom: 4)
        parsed = described_class.parse(original)
        expect(parsed).to be(original)
      end

      it "raises error for invalid input" do
        expect { described_class.parse(123) }.to raise_error(ArgumentError)
      end
    end

    describe "#to_s" do
      it "converts to string representation" do
        padding = described_class.new(left: 2, top: 3, right: 3, bottom: 2)
        expect(padding.to_s).to eq("[left=2.0, top=3.0, right=3.0, bottom=2.0]")
      end
    end

    describe "#to_h" do
      it "converts to hash" do
        padding = described_class.new(left: 1, top: 2, right: 3, bottom: 4)
        expect(padding.to_h).to eq(
          left: 1.0, top: 2.0, right: 3.0, bottom: 4.0,
        )
      end
    end

    describe "#==" do
      it "compares padding objects" do
        p1 = described_class.new(left: 1, top: 2, right: 3, bottom: 4)
        p2 = described_class.new(left: 1, top: 2, right: 3, bottom: 4)
        p3 = described_class.new(left: 5, top: 6, right: 7, bottom: 8)

        expect(p1).to eq(p2)
        expect(p1).not_to eq(p3)
      end
    end
  end

  describe Elkrb::Options::KVector do
    describe ".parse" do
      it "parses vector from string" do
        vector = described_class.parse("(23, 43)")
        expect(vector.x).to eq(23.0)
        expect(vector.y).to eq(43.0)
      end

      it "parses vector from string without spaces" do
        vector = described_class.parse("(10,20)")
        expect(vector.x).to eq(10.0)
        expect(vector.y).to eq(20.0)
      end

      it "parses vector from hash with symbol keys" do
        vector = described_class.parse(x: 5, y: 10)
        expect(vector.x).to eq(5.0)
        expect(vector.y).to eq(10.0)
      end

      it "parses vector from hash with string keys" do
        vector = described_class.parse("x" => 15, "y" => 25)
        expect(vector.x).to eq(15.0)
        expect(vector.y).to eq(25.0)
      end

      it "parses vector from array" do
        vector = described_class.parse([30, 40])
        expect(vector.x).to eq(30.0)
        expect(vector.y).to eq(40.0)
      end

      it "returns same object if already KVector" do
        original = described_class.new(1, 2)
        parsed = described_class.parse(original)
        expect(parsed).to be(original)
      end

      it "raises error for array with wrong size" do
        expect do
          described_class.parse([1, 2, 3])
        end.to raise_error(ArgumentError)
      end

      it "raises error for invalid input" do
        expect do
          described_class.parse("invalid")
        end.to raise_error(ArgumentError)
      end
    end

    describe "#to_s" do
      it "converts to string representation" do
        vector = described_class.new(23, 43)
        expect(vector.to_s).to eq("(23.0, 43.0)")
      end
    end

    describe "#to_h" do
      it "converts to hash" do
        vector = described_class.new(10, 20)
        expect(vector.to_h).to eq(x: 10.0, y: 20.0)
      end
    end

    describe "#to_a" do
      it "converts to array" do
        vector = described_class.new(5, 15)
        expect(vector.to_a).to eq([5.0, 15.0])
      end
    end

    describe "#==" do
      it "compares vector objects" do
        v1 = described_class.new(1, 2)
        v2 = described_class.new(1, 2)
        v3 = described_class.new(3, 4)

        expect(v1).to eq(v2)
        expect(v1).not_to eq(v3)
      end
    end
  end

  describe Elkrb::Options::KVectorChain do
    describe ".parse" do
      it "parses chain from string" do
        chain = described_class.parse("( {1,2}, {3,4} )")
        expect(chain.size).to eq(2)
        expect(chain[0].x).to eq(1.0)
        expect(chain[0].y).to eq(2.0)
        expect(chain[1].x).to eq(3.0)
        expect(chain[1].y).to eq(4.0)
      end

      it "parses chain from string without spaces" do
        chain = described_class.parse("({5,6},{7,8})")
        expect(chain.size).to eq(2)
        expect(chain[0].x).to eq(5.0)
        expect(chain[0].y).to eq(6.0)
        expect(chain[1].x).to eq(7.0)
        expect(chain[1].y).to eq(8.0)
      end

      it "parses chain from array of arrays" do
        chain = described_class.parse([[10, 20], [30, 40]])
        expect(chain.size).to eq(2)
        expect(chain[0].x).to eq(10.0)
        expect(chain[0].y).to eq(20.0)
        expect(chain[1].x).to eq(30.0)
        expect(chain[1].y).to eq(40.0)
      end

      it "parses chain from array of hashes" do
        chain = described_class.parse([{ x: 1, y: 2 }, { x: 3, y: 4 }])
        expect(chain.size).to eq(2)
        expect(chain[0].x).to eq(1.0)
        expect(chain[0].y).to eq(2.0)
        expect(chain[1].x).to eq(3.0)
        expect(chain[1].y).to eq(4.0)
      end

      it "returns same object if already KVectorChain" do
        original = described_class.new([[1, 2], [3, 4]])
        parsed = described_class.parse(original)
        expect(parsed).to be(original)
      end
    end

    describe "#add" do
      it "adds vector to chain" do
        chain = described_class.new
        chain.add([1, 2])
        chain.add([3, 4])

        expect(chain.size).to eq(2)
        expect(chain[0].x).to eq(1.0)
        expect(chain[1].x).to eq(3.0)
      end

      it "supports << syntax" do
        chain = described_class.new
        chain << [1, 2]
        chain << [3, 4]

        expect(chain.size).to eq(2)
      end
    end

    describe "#each" do
      it "iterates over vectors" do
        chain = described_class.new([[1, 2], [3, 4]])
        coords = []
        # Disabling because we are testing `each` method here.
        # TODO: somehow `map` doesn't work when `each` is defined.
        # rubocop:disable all
        chain.each { |v| coords << [v.x, v.y] }
        # rubocop:enable all

        expect(coords).to eq([[1.0, 2.0], [3.0, 4.0]])
      end
    end

    describe "#to_s" do
      it "converts to string representation" do
        chain = described_class.new([[1, 2], [3, 4]])
        expect(chain.to_s).to eq("( {1.0, 2.0}, {3.0, 4.0} )")
      end

      it "returns empty parens for empty chain" do
        chain = described_class.new
        expect(chain.to_s).to eq("()")
      end
    end

    describe "#==" do
      it "compares chain objects" do
        c1 = described_class.new([[1, 2], [3, 4]])
        c2 = described_class.new([[1, 2], [3, 4]])
        c3 = described_class.new([[5, 6], [7, 8]])

        expect(c1).to eq(c2)
        expect(c1).not_to eq(c3)
      end
    end
  end
end
