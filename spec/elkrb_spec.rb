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
    it "returns option metadata rendered from the registry, keyed by canonical id" do
      result = described_class.known_layout_options

      expect(result["elk.algorithm"][:values]).to include("layered", "force")
      expect(result["elk.direction"][:values]).to include("RIGHT")
      expect(result["elk.spacing.nodeNode"][:type]).to eq(:float)
      expect(result["elk.padding"][:parser]).to eq("Elkrb::Options::ElkPadding")
      expect(result["elk.hierarchyHandling"][:note]).to eq("cross-level edges are routed; no cross-level layering")
    end

    it "is the same table LayoutEngine renders, which no longer returns the empty stub" do
      expect(Elkrb::Layout::LayoutEngine.known_layout_options)
        .to eq(described_class.known_layout_options)
      expect(Elkrb::Layout::LayoutEngine.known_layout_options).not_to be_empty
    end
  end

  describe ".layout" do
    let(:hash_graph) do
      { "id" => "root",
        "children" => [{ "id" => "a", "width" => 10.0, "height" => 10.0 }] }
    end

    # The card settles the exact message, so the whole string is asserted.
    {
      nil => "NilClass",
      "{}" => "String",
      [] => "Array",
      42 => "Integer",
    }.each do |argument, class_name|
      it "rejects #{argument.inspect} by naming #{class_name}" do
        expect { described_class.layout(argument) }.to raise_error(
          ArgumentError,
          "graph must be a Hash or Elkrb::Graph::Graph, got #{class_name}",
        )
      end
    end

    # The documented contract: a Graph is mutated in place and returned, while
    # a Hash is converted to a fresh Graph and left untouched.
    context "with a Graph argument" do
      it "returns the very same object" do
        graph = Elkrb::Graph::Graph.from_hash(hash_graph)

        expect(described_class.layout(graph)).to equal(graph)
      end

      it "writes computed coordinates onto it" do
        graph = Elkrb::Graph::Graph.from_hash(hash_graph)
        described_class.layout(graph)

        expect(graph.children.first.x).not_to be_nil
      end
    end

    context "with a Hash argument" do
      it "returns a new Graph" do
        expect(described_class.layout(hash_graph))
          .to be_a(Elkrb::Graph::Graph)
      end

      it "leaves the input Hash untouched" do
        before = Marshal.dump(hash_graph)
        described_class.layout(hash_graph)

        expect(Marshal.dump(hash_graph)).to eq(before)
      end
    end
  end
end
