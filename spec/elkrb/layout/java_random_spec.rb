# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::JavaRandom do
  # Every expected value below was printed by java.util.Random (JDK 21) for
  # the same calls, in the same order.
  subject(:random) { described_class.new(42) }

  it "draws doubles, floats and ints in java.util.Random's sequence" do
    drawn = [random.next_double, random.next_int(5), random.next_float.round(7),
             random.next_int(100), random.next_int(8), random.next_bits(32)]

    expect(drawn).to eq(
      [0.7275636800328681, 3, 0.0479393, 70, 7, 1_190_043_011],
    )
  end

  it "rejects a bound that is not positive" do
    expect { random.next_int(0) }.to raise_error(ArgumentError, /positive/)
  end

  it "draws nextInt(5) for seed 7 as java.util.Random does" do
    seeded = described_class.new(7)

    expect(Array.new(8) { seeded.next_int(5) }).to eq([1, 4, 0, 4, 0, 4, 3, 4])
  end

  describe "#next_long" do
    it "draws a signed 64-bit value as java.util.Random does" do
      expect(random.next_long).to eq(-5_025_562_857_975_149_833)
    end

    it "keeps the sign of a positive draw" do
      expect(described_class.new(-5).next_long).to eq(4_967_725_915_334_898_755)
    end

    it "continues the same sequence for the next draw" do
      random.next_long

      expect([random.next_bits(1), random.next_int(100)]).to eq([1, 84])
    end
  end

  describe "#seed=" do
    it "restarts the sequence like Random#setSeed" do
      seed = random.next_long
      random.seed = seed

      expect(random.next_double).to eq(0.47497692040880735)
    end
  end
end
