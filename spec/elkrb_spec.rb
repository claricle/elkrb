# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb do
  describe ".known_layout_algorithms" do
    it "returns algorithm metadata without raising" do
      result = described_class.known_layout_algorithms

      expect(result).to be_an(Array)
      layered = result.find { |alg| alg[:id] == "layered" }
      expect(layered).to include(
        id: "layered",
        name: a_kind_of(String),
        description: a_kind_of(String),
        category: a_kind_of(String),
      )
      expect([true, false]).to include(layered[:supports_hierarchy])
    end
  end

  describe ".known_layout_options" do
    it "returns option metadata whose algorithm values list is populated" do
      result = described_class.known_layout_options

      expect(result["algorithm"][:values]).to include("layered", "force")
      expect(result["elk.direction"][:values]).to eq(%w[UP DOWN LEFT RIGHT])
    end
  end
end
