# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::AlgorithmRegistry do
  # AlgorithmRegistry holds process-wide state; any example that
  # registers a test double must not leak into the rest of the suite.
  around do |example|
    algorithms_before = described_class.instance_variable_get(:@algorithms).dup
    metadata_before = described_class.instance_variable_get(:@metadata).dup
    example.run
    described_class.instance_variable_set(:@algorithms, algorithms_before)
    described_class.instance_variable_set(:@metadata, metadata_before)
  end

  describe ".get" do
    it "resolves camelCase, snake_case, and the ELK-prefixed form to the same class" do
      camel = described_class.get("sporeOverlap")
      snake = described_class.get("spore_overlap")
      prefixed = described_class.get("org.eclipse.elk.sporeOverlap")

      expect(camel).to eq(Elkrb::Layout::Algorithms::SporeOverlap)
      expect(snake).to eq(camel)
      expect(prefixed).to eq(camel)
    end

    it "keeps resolving the five legacy run-together names that predate snake_case folding" do
      expect(described_class.get("mrTree")).to eq(Elkrb::Layout::Algorithms::MRTree)
      expect(described_class.get("rectPacking")).to eq(Elkrb::Layout::Algorithms::RectPacking)
      expect(described_class.get("topdownPacking")).to eq(Elkrb::Layout::Algorithms::TopdownPacking)
      expect(described_class.get("libAvoid")).to eq(Elkrb::Layout::Algorithms::Libavoid)
      expect(described_class.get("vertiFlex")).to eq(Elkrb::Layout::Algorithms::VertiFlex)
    end
  end

  describe ".register" do
    it "normalises the registered name the same way .get does" do
      described_class.register("MyTestAlgo", Elkrb::Layout::Algorithms::Box)

      expect(described_class.get("MyTestAlgo")).to eq(Elkrb::Layout::Algorithms::Box)
      expect(described_class.get("my_test_algo")).to eq(Elkrb::Layout::Algorithms::Box)
    end

    it "replaces a legacy run-together registration instead of adding a second entry" do
      count_before = described_class.available_algorithms.size

      described_class.register("mrTree", Elkrb::Layout::Algorithms::Box)

      expect(described_class.available_algorithms.size).to eq(count_before)
      expect(described_class.available_algorithms.grep(/mr/)).to eq(["mrtree"])
      expect(described_class.get("mrTree")).to eq(Elkrb::Layout::Algorithms::Box)
      expect(described_class.get("mrtree")).to eq(Elkrb::Layout::Algorithms::Box)
    end
  end

  describe ".algorithm_info" do
    it "includes supported_options sourced from the options registry" do
      info = described_class.algorithm_info("layered")

      expect(info[:supported_options]).to include("elk.direction",
                                                  "elk.spacing.nodeNode")
      expect(info[:supported_options]).not_to include("elk.force.iterations")
    end

    it "returns the real registered metadata for a legacy-fallback name, not an empty hash" do
      info = described_class.algorithm_info("mrTree")

      expect(info[:id]).to eq("mrtree")
      expect(info[:name]).to eq("Multi-Rooted Tree")
      expect(info[:description]).not_to eq("")
    end

    it "excludes core (algorithms: :all) options for a compatible-interface registration that does not inherit BaseAlgorithm" do
      described_class.register("compat_test", String)

      info = described_class.algorithm_info("compat_test")

      expect(info[:supported_options]).not_to include("elk.padding",
                                                      "elk.spacing.nodeNode")
    end

    it "still advertises the selector for a compatible-interface registration, which LayoutEngine honours" do
      described_class.register("selector_test", String)

      expect(described_class.algorithm_info("selector_test")[:supported_options])
        .to include("elk.algorithm")
    end
  end
end
