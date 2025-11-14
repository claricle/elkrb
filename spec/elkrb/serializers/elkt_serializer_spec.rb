# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/elkrb/serializers/elkt_serializer"

RSpec.describe Elkrb::Serializers::ElktSerializer do
  let(:serializer) { described_class.new }

  describe "#serialize" do
    it "serializes empty graph" do
      graph = {
        id: "root",
        children: [],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to eq("\n")
    end

    it "serializes simple nodes" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("node n1")
      expect(result).to include("node n2")
    end

    it "serializes simple edges" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"] },
        ],
      }

      result = serializer.serialize(graph)

      expect(result).to include("edge n1 -> n2")
    end

    it "serializes nodes with custom dimensions" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 100, height: 60 },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("node n1 {")
      expect(result).to include("layout [ size: 100, 60 ]")
      expect(result).to include("}")
    end

    it "serializes algorithm option" do
      graph = {
        id: "root",
        layoutOptions: {
          "elk.algorithm" => "layered",
        },
        children: [],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("algorithm: layered")
    end

    it "serializes direction option" do
      graph = {
        id: "root",
        layoutOptions: {
          "elk.direction" => "DOWN",
        },
        children: [],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("direction: DOWN")
    end

    it "serializes spacing options" do
      graph = {
        id: "root",
        layoutOptions: {
          "elk.spacing.nodeNode" => 50,
        },
        children: [],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("spacing.nodeNode: 50")
    end

    it "serializes float values" do
      graph = {
        id: "root",
        layoutOptions: {
          "elk.spacing.nodeNode" => 50.5,
        },
        children: [],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("spacing.nodeNode: 50.5")
    end

    it "serializes boolean values" do
      graph = {
        id: "root",
        layoutOptions: {
          "elk.option1" => true,
          "elk.option2" => false,
        },
        children: [],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("option1: true")
      expect(result).to include("option2: false")
    end

    it "serializes node labels" do
      graph = {
        id: "root",
        children: [
          {
            id: "n1",
            width: 100,
            height: 60,
            labels: [{ text: "Node 1" }],
          },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include('label "Node 1"')
    end

    it "serializes node position" do
      graph = {
        id: "root",
        children: [
          {
            id: "n1",
            width: 100,
            height: 60,
            x: 50,
            y: 100,
          },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("layout [ position: 50, 100 ]")
    end

    it "serializes ports" do
      graph = {
        id: "root",
        children: [
          {
            id: "n1",
            width: 100,
            height: 60,
            ports: [{ id: "p1" }],
          },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("port p1")
    end

    it "serializes edges with port references" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [
          {
            id: "e1",
            sources: ["n1"],
            targets: ["n2"],
            sourcePort: "p1",
            targetPort: "p2",
          },
        ],
      }

      result = serializer.serialize(graph)

      expect(result).to include("edge n1.p1 -> n2.p2")
    end

    it "serializes edges with source port only" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [
          {
            id: "e1",
            sources: ["n1"],
            targets: ["n2"],
            sourcePort: "p1",
          },
        ],
      }

      result = serializer.serialize(graph)

      expect(result).to include("edge n1.p1 -> n2")
    end

    it "serializes edges with target port only" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [
          {
            id: "e1",
            sources: ["n1"],
            targets: ["n2"],
            targetPort: "p2",
          },
        ],
      }

      result = serializer.serialize(graph)

      expect(result).to include("edge n1 -> n2.p2")
    end

    it "omits auto-generated edge IDs" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [
          { id: "e0", sources: ["n1"], targets: ["n2"] },
        ],
      }

      result = serializer.serialize(graph)

      expect(result).to include("edge n1 -> n2")
      expect(result).not_to include("e0:")
    end

    it "includes custom edge IDs" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [
          { id: "myEdge", sources: ["n1"], targets: ["n2"] },
        ],
      }

      result = serializer.serialize(graph)

      expect(result).to include("edge myEdge: n1 -> n2")
    end

    it "serializes nested nodes" do
      graph = {
        id: "root",
        children: [
          {
            id: "parent",
            width: 200,
            height: 150,
            children: [
              { id: "child1", width: 40, height: 40 },
              { id: "child2", width: 40, height: 40 },
            ],
          },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("node parent {")
      expect(result).to include("node child1")
      expect(result).to include("node child2")
    end

    it "formats numbers without trailing zeros" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 100.0, height: 60.0 },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("layout [ size: 100, 60 ]")
      expect(result).not_to include(".0")
    end

    it "serializes complete graph" do
      graph = {
        id: "root",
        layoutOptions: {
          "elk.algorithm" => "layered",
          "elk.direction" => "DOWN",
          "elk.spacing.nodeNode" => 50,
        },
        children: [
          {
            id: "n1",
            width: 100,
            height: 60,
            labels: [{ text: "Node 1" }],
          },
          {
            id: "n2",
            width: 100,
            height: 60,
            labels: [{ text: "Node 2" }],
          },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"] },
        ],
      }

      result = serializer.serialize(graph)

      expect(result).to include("algorithm: layered")
      expect(result).to include("direction: DOWN")
      expect(result).to include("spacing.nodeNode: 50")
      expect(result).to include("node n1 {")
      expect(result).to include('label "Node 1"')
      expect(result).to include("edge n1 -> n2")
    end

    it "handles options without elk prefix" do
      graph = {
        id: "root",
        layoutOptions: {
          "algorithm" => "layered",
        },
        children: [],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("algorithm: layered")
    end

    it "serializes self-loop edges" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n1"] },
        ],
      }

      result = serializer.serialize(graph)

      expect(result).to include("edge n1 -> n1")
    end

    it "serializes multiple edges" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"] },
          { id: "e2", sources: ["n2"], targets: ["n1"] },
        ],
      }

      result = serializer.serialize(graph)

      expect(result.scan("edge").length).to eq(2)
    end

    it "adds blank line between options and nodes" do
      graph = {
        id: "root",
        layoutOptions: {
          "elk.algorithm" => "layered",
        },
        children: [
          { id: "n1", width: 40, height: 40 },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)
      lines = result.split("\n")

      algorithm_idx = lines.index { |l| l.include?("algorithm") }
      lines.index { |l| l.include?("node n1") }

      expect(lines[algorithm_idx + 1].strip).to be_empty
    end

    it "adds blank line between nodes and edges" do
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 40, height: 40 },
          { id: "n2", width: 40, height: 40 },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"] },
        ],
      }

      result = serializer.serialize(graph)
      lines = result.split("\n")

      node_idx = lines.rindex { |l| l.include?("node") }
      lines.index { |l| l.include?("edge") }

      expect(lines[node_idx + 1].strip).to be_empty
    end

    it "supports custom indentation" do
      serializer = described_class.new(indent_size: 4)
      graph = {
        id: "root",
        children: [
          {
            id: "parent",
            width: 100,
            height: 60,
            children: [
              { id: "child", width: 40, height: 40 },
            ],
          },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("    node child")
    end

    it "serializes port with layout options" do
      graph = {
        id: "root",
        children: [
          {
            id: "n1",
            width: 100,
            height: 60,
            ports: [
              {
                id: "p1",
                layoutOptions: {
                  "elk.port.side" => "WEST",
                },
              },
            ],
          },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("port p1 {")
      expect(result).to include("port.side: WEST")
    end

    it "serializes nested edges" do
      graph = {
        id: "root",
        children: [
          {
            id: "parent",
            width: 200,
            height: 150,
            children: [
              { id: "child1", width: 40, height: 40 },
              { id: "child2", width: 40, height: 40 },
            ],
            edges: [
              { id: "e1", sources: ["child1"], targets: ["child2"] },
            ],
          },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result).to include("edge child1 -> child2")
    end
  end

  describe "round-trip conversion" do
    it "can parse its own output" do
      require_relative "../../../lib/elkrb/parsers/elkt_parser"

      graph = {
        id: "root",
        layoutOptions: {
          "elk.algorithm" => "layered",
          "elk.spacing.nodeNode" => 50,
        },
        children: [
          { id: "n1", width: 100, height: 60 },
          { id: "n2", width: 100, height: 60 },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"] },
        ],
      }

      elkt = serializer.serialize(graph)
      parsed = Elkrb::Parsers::ElktParser.parse(elkt)

      expect(parsed[:layoutOptions]["elk.algorithm"]).to eq("layered")
      expect(parsed[:children].length).to eq(2)
      expect(parsed[:edges].length).to eq(1)
    end
  end
end
