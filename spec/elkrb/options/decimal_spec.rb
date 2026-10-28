# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Options::Decimal do
  describe ".to_f" do
    { 5 => 5.0, 2.5 => 2.5, nil => 0.0, "5." => 5.0, " 1.e1 " => 10.0,
      "+2" => 2.0, ".5" => 0.5 }.each do |good, expected|
      it "reads #{good.inspect} as #{expected}" do
        expect(described_class.to_f(good)).to eq(expected)
      end
    end

    ["abc", "0x10", "1e", "", " ", "1_0", false, true, [1], {}].each do |bad|
      it "raises ArgumentError for #{bad.inspect}" do
        expect { described_class.to_f(bad) }
          .to raise_error(ArgumentError, /Invalid number/)
      end
    end
  end

  describe ".component" do
    it "prefers the Symbol key, then the String key, then the default" do
      expect([
               described_class.component({ x: 1, "x" => 2 }, :x, 9),
               described_class.component({ "x" => 2 }, :x, 9),
               described_class.component({}, :x, 9),
               described_class.component({ x: nil, "x" => nil }, :x, 9),
             ]).to eq([1, 2, 9, 9])
    end

    it "returns false and 0 as values, not as misses" do
      expect([
               described_class.component({ x: false }, :x, 9),
               described_class.component({ "x" => 0 }, :x, 9),
               described_class.component({ x: nil, "x" => false }, :x, 9),
             ]).to eq([false, 0, false])
    end
  end
end

RSpec.describe "Option value parsers reject a malformed component" do
  parsers = [Elkrb::Options::ElkPadding, Elkrb::Options::KVector]
  bad_hashes = [{ top: false, x: false }, { "left" => "abc", "y" => "0x10" }]

  parsers.product(bad_hashes).each do |parser, hash|
    it "#{parser.name.split('::').last}.parse raises for #{hash.inspect}" do
      expect { parser.parse(hash) }.to raise_error(ArgumentError)
    end
  end

  it "ElkPadding.parse reads an absent side as 0" do
    expect(Elkrb::Options::ElkPadding.parse({ top: "3" }).to_h)
      .to eq(left: 0.0, top: 3.0, right: 0.0, bottom: 0.0)
  end
end
