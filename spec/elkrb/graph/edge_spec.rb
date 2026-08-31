# frozen_string_literal: true

require "spec_helper"

# Both endpoint pairs are exercised from one table so neither legacy hook can be
# reverted without an example going red.
edge_endpoints = [
  { canonical: "sources", legacy: "source", port: "sourcePort",
    reader: :sources },
  { canonical: "targets", legacy: "target", port: "targetPort",
    reader: :targets },
]

RSpec.describe Elkrb::Graph::Edge do
  describe "legacy elkjs endpoint keys" do
    edge_endpoints.each do |ep|
      context "for #{ep[:canonical]}" do
        it "reads the legacy #{ep[:legacy]} key into #{ep[:canonical]}" do
          edge = described_class.from_json(
            { "id" => "e", ep[:legacy] => "n1" }.to_json,
          )

          expect(edge.public_send(ep[:reader])).to eq(["n1"])
        end

        it "reads the legacy #{ep[:legacy]} key from a Hash" do
          edge = described_class.from_hash("id" => "e", ep[:legacy] => "n1")

          expect(edge.public_send(ep[:reader])).to eq(["n1"])
        end

        it "reads #{ep[:port]} with no node key present" do
          edge = described_class.from_json(
            { "id" => "e", ep[:port] => "p1" }.to_json,
          )

          expect(edge.public_send(ep[:reader])).to eq(["p1"])
        end

        # Both document orders: the winner is set by the order the mappings
        # are declared in, not by the order the keys appear in the document.
        it "prefers #{ep[:port]} over #{ep[:legacy]}" do
          edge = described_class.from_json(
            { "id" => "e", ep[:legacy] => "n1", ep[:port] => "p1" }.to_json,
          )

          expect(edge.public_send(ep[:reader])).to eq(["p1"])
        end

        it "prefers #{ep[:port]} with the document order reversed" do
          edge = described_class.from_json(
            { "id" => "e", ep[:port] => "p1", ep[:legacy] => "n1" }.to_json,
          )

          expect(edge.public_send(ep[:reader])).to eq(["p1"])
        end

        it "prefers a non-empty #{ep[:canonical]} over #{ep[:legacy]}" do
          edge = described_class.from_json(
            { "id" => "e", ep[:canonical] => ["c1"],
              ep[:legacy] => "n1" }.to_json,
          )

          expect(edge.public_send(ep[:reader])).to eq(["c1"])
        end

        it "treats an explicit empty #{ep[:canonical]} as absent" do
          edge = described_class.from_json(
            { "id" => "e", ep[:canonical] => [], ep[:legacy] => "n1" }.to_json,
          )

          expect(edge.public_send(ep[:reader])).to eq(["n1"])
        end

        it "keeps an explicit empty #{ep[:canonical]} with no legacy key" do
          edge = described_class.from_json(
            { "id" => "e", ep[:canonical] => [] }.to_json,
          )

          expect(edge.public_send(ep[:reader])).to eq([])
        end

        it "keeps a multi-element #{ep[:canonical]}" do
          edge = described_class.from_json(
            { "id" => "e", ep[:canonical] => %w[a b] }.to_json,
          )

          expect(edge.public_send(ep[:reader])).to eq(%w[a b])
        end

        it "emits neither #{ep[:legacy]} nor #{ep[:port]} on write" do
          edge = described_class.from_json(
            { "id" => "e", ep[:legacy] => "n1" }.to_json,
          )

          keys = JSON.parse(edge.to_json).keys

          expect(keys).to include(ep[:canonical])
          expect(keys).not_to include(ep[:legacy], ep[:port])
        end
      end
    end

    it "lays out a primitive edge with real endpoints and a section" do
      result = Elkrb.layout(
        "id" => "root",
        "children" => [
          { "id" => "a", "width" => 10.0, "height" => 10.0 },
          { "id" => "b", "width" => 10.0, "height" => 10.0 },
        ],
        "edges" => [{ "id" => "e", "source" => "a", "target" => "b" }],
      )
      edge = result.edges.first

      expect(edge.sources).to eq(["a"])
      expect(edge.targets).to eq(["b"])
      expect(edge.sections).not_to be_empty
    end

    it "normalises a primitive edge to sources and targets only" do
      edge = described_class.from_json(
        %({"id":"e","source":"a","target":"b"}),
      )

      expect(JSON.parse(edge.to_json))
        .to eq("id" => "e", "sources" => ["a"], "targets" => ["b"])
    end
  end

  describe "junctionPoints and container" do
    let(:source) do
      %({"id":"e","sources":["a"],"targets":["b"],) +
        %("junctionPoints":[{"x":1.0,"y":1.0}],"container":"root"})
    end

    it "round-trips both through JSON" do
      edge = described_class.from_json(source)

      expect(JSON.parse(edge.to_json)).to eq(JSON.parse(source))
    end

    it "reads junctionPoints as Point instances" do
      edge = described_class.from_json(source)

      expect(edge.junction_points.first)
        .to eq(Elkrb::Geometry::Point.new(x: 1.0, y: 1.0))
    end

    it "round-trips both through YAML" do
      yaml = "id: e\ncontainer: root\njunction_points:\n- x: 1.0\n  y: 1.0\n"

      expect(YAML.safe_load(described_class.from_yaml(yaml).to_yaml))
        .to eq(YAML.safe_load(yaml))
    end

    it "omits both keys when the input carried neither" do
      edge = described_class.from_json(%({"id":"e","sources":["a"]}))

      expect(JSON.parse(edge.to_json).keys)
        .not_to include("junctionPoints", "container")
    end
  end
end

RSpec.describe Elkrb::Graph::EdgeSection do
  # Both formats, both attributes: updating only the key_value block would
  # otherwise pass, which is a defect this repo has shipped before.
  %w[incoming outgoing].each do |direction|
    describe "#{direction}_sections" do
      let(:camel) { "#{direction}Sections" }
      let(:snake) { "#{direction}_sections" }
      let(:reader) { :"#{direction}_sections" }

      it "round-trips through JSON" do
        source = { "id" => "s0", camel => %w[s1 s2] }.to_json

        expect(JSON.parse(described_class.from_json(source).to_json))
          .to eq(JSON.parse(source))
      end

      it "reads the collection from JSON" do
        section = described_class.from_json(
          { "id" => "s0", camel => %w[s1 s2] }.to_json,
        )

        expect(section.public_send(reader)).to eq(%w[s1 s2])
      end

      it "round-trips through YAML" do
        yaml = "id: s0\n#{snake}:\n- s1\n- s2\n"

        expect(YAML.safe_load(described_class.from_yaml(yaml).to_yaml))
          .to eq(YAML.safe_load(yaml))
      end
    end
  end
end
