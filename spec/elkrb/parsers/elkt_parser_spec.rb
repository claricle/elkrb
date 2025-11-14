# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/elkrb/parsers/elkt_parser"

RSpec.describe Elkrb::Parsers::ElktParser do
  describe ".parse" do
    it "parses empty graph" do
      input = ""
      result = described_class.parse(input)

      expect(result).to include(
        id: "root",
        children: [],
        edges: [],
      )
    end

    it "parses simple nodes" do
      input = <<~ELKT
        node n1
        node n2
        node n3
      ELKT

      result = described_class.parse(input)

      expect(result[:children].length).to eq(3)
      expect(result[:children][0][:id]).to eq("n1")
      expect(result[:children][1][:id]).to eq("n2")
      expect(result[:children][2][:id]).to eq("n3")
    end

    it "parses simple edges" do
      input = <<~ELKT
        node n1
        node n2
        edge n1 -> n2
      ELKT

      result = described_class.parse(input)

      expect(result[:edges].length).to eq(1)
      expect(result[:edges][0]).to include(
        sources: ["n1"],
        targets: ["n2"],
      )
    end

    it "parses edges with spaces around arrow" do
      input = <<~ELKT
        node n1
        node n2
        edge n1->n2
        edge n2 -> n1
      ELKT

      result = described_class.parse(input)

      expect(result[:edges].length).to eq(2)
      expect(result[:edges][0][:sources]).to eq(["n1"])
      expect(result[:edges][0][:targets]).to eq(["n2"])
    end

    it "parses named edges" do
      input = <<~ELKT
        node n1
        node n2
        edge e1: n1 -> n2
      ELKT

      result = described_class.parse(input)

      expect(result[:edges][0][:id]).to eq("e1")
    end

    it "parses algorithm property" do
      input = <<~ELKT
        algorithm: layered
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.algorithm"]).to eq("layered")
    end

    it "parses direction property" do
      input = <<~ELKT
        direction: DOWN
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.direction"]).to eq("DOWN")
    end

    it "parses spacing properties" do
      input = <<~ELKT
        spacing.nodeNode: 50
        spacing.edgeNode: 30.5
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.spacing.nodeNode"]).to eq(50)
      expect(result[:layoutOptions]["elk.spacing.edgeNode"]).to eq(30.5)
    end

    it "parses integer values" do
      input = <<~ELKT
        spacing.nodeNode: 100
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.spacing.nodeNode"]).to eq(100)
    end

    it "parses float values" do
      input = <<~ELKT
        spacing.nodeNode: 50.75
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.spacing.nodeNode"]).to eq(50.75)
    end

    it "parses boolean values" do
      input = <<~ELKT
        option1: true
        option2: false
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.option1"]).to eq(true)
      expect(result[:layoutOptions]["elk.option2"]).to eq(false)
    end

    it "parses nodes with blocks" do
      input = <<~ELKT
        node n1 {
          layout [ size: 100, 60 ]
        }
      ELKT

      result = described_class.parse(input)

      expect(result[:children][0][:width]).to eq(100.0)
      expect(result[:children][0][:height]).to eq(60.0)
    end

    it "parses layout size" do
      input = <<~ELKT
        node n1 {
          layout [ size: 50, 30 ]
        }
      ELKT

      result = described_class.parse(input)

      expect(result[:children][0][:width]).to eq(50.0)
      expect(result[:children][0][:height]).to eq(30.0)
    end

    it "parses layout position" do
      input = <<~ELKT
        node n1 {
          layout [ position: 100, 200 ]
        }
      ELKT

      result = described_class.parse(input)

      expect(result[:children][0][:x]).to eq(100.0)
      expect(result[:children][0][:y]).to eq(200.0)
    end

    it "parses line comments" do
      input = <<~ELKT
        // This is a comment
        node n1
        // Another comment
        node n2
      ELKT

      result = described_class.parse(input)

      expect(result[:children].length).to eq(2)
    end

    it "parses block comments" do
      input = <<~ELKT
        /* This is a
           block comment */
        node n1
        node n2
      ELKT

      result = described_class.parse(input)

      expect(result[:children].length).to eq(2)
    end

    it "parses inline comments" do
      input = <<~ELKT
        node n1 // Comment after node
        edge n1 -> n2 // Comment after edge
        node n2
      ELKT

      result = described_class.parse(input)

      expect(result[:children].length).to eq(2)
      expect(result[:edges].length).to eq(1)
    end

    it "parses edges with port references" do
      input = <<~ELKT
        node n1
        node n2
        edge n1.p1 -> n2.p2
      ELKT

      result = described_class.parse(input)

      expect(result[:edges][0]).to include(
        sources: ["n1"],
        targets: ["n2"],
        sourcePort: "p1",
        targetPort: "p2",
      )
    end

    it "parses edges with source port only" do
      input = <<~ELKT
        node n1
        node n2
        edge n1.p1 -> n2
      ELKT

      result = described_class.parse(input)

      expect(result[:edges][0][:sourcePort]).to eq("p1")
      expect(result[:edges][0]).not_to have_key(:targetPort)
    end

    it "parses edges with target port only" do
      input = <<~ELKT
        node n1
        node n2
        edge n1 -> n2.p2
      ELKT

      result = described_class.parse(input)

      expect(result[:edges][0]).not_to have_key(:sourcePort)
      expect(result[:edges][0][:targetPort]).to eq("p2")
    end

    it "parses self-loop edges" do
      input = <<~ELKT
        node n1
        edge n1 -> n1
      ELKT

      result = described_class.parse(input)

      expect(result[:edges][0]).to include(
        sources: ["n1"],
        targets: ["n1"],
      )
    end

    it "parses labels" do
      input = <<~ELKT
        node n1 {
          label "Node 1"
        }
      ELKT

      result = described_class.parse(input)

      expect(result[:children][0][:labels]).to be_an(Array)
      expect(result[:children][0][:labels][0][:text]).to eq("Node 1")
    end

    it "parses ports" do
      input = <<~ELKT
        node n1 {
          port p1
        }
      ELKT

      result = described_class.parse(input)

      expect(result[:children][0][:ports]).to be_an(Array)
      expect(result[:children][0][:ports][0][:id]).to eq("p1")
    end

    it "parses nested nodes" do
      input = <<~ELKT
        node parent {
          node child1
          node child2
        }
      ELKT

      result = described_class.parse(input)

      expect(result[:children][0][:children]).to be_an(Array)
      expect(result[:children][0][:children].length).to eq(2)
      expect(result[:children][0][:children][0][:id]).to eq("child1")
      expect(result[:children][0][:children][1][:id]).to eq("child2")
    end

    it "sets default width and height for nodes" do
      input = <<~ELKT
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:children][0][:width]).to eq(40)
      expect(result[:children][0][:height]).to eq(40)
    end

    it "generates edge IDs automatically" do
      input = <<~ELKT
        node n1
        node n2
        edge n1 -> n2
        edge n2 -> n1
      ELKT

      result = described_class.parse(input)

      expect(result[:edges][0][:id]).to match(/^e\d+$/)
      expect(result[:edges][1][:id]).to match(/^e\d+$/)
    end

    it "parses complex graph from example" do
      input = <<~ELKT
        algorithm: layered
        direction: DOWN
        spacing.nodeNode: 50

        node n1 {
          layout [ size: 100, 60 ]
          label "Node 1"
        }

        node n2 {
          layout [ size: 100, 60 ]
          label "Node 2"
        }

        edge n1 -> n2
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.algorithm"]).to eq("layered")
      expect(result[:layoutOptions]["elk.direction"]).to eq("DOWN")
      expect(result[:layoutOptions]["elk.spacing.nodeNode"]).to eq(50)
      expect(result[:children].length).to eq(2)
      expect(result[:edges].length).to eq(1)
    end

    it "handles properties with elk prefix" do
      input = <<~ELKT
        elk.algorithm: layered
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.algorithm"]).to eq("layered")
    end

    it "parses multiple edges between same nodes" do
      input = <<~ELKT
        node n1
        node n2
        edge n1 -> n2
        edge n1 -> n2
        edge n1 -> n2
      ELKT

      result = described_class.parse(input)

      expect(result[:edges].length).to eq(3)
    end

    it "parses string property values" do
      input = <<~ELKT
        customProp: someValue
        node n1
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.customProp"]).to eq("someValue")
    end

    it "handles empty lines gracefully" do
      input = <<~ELKT
        node n1


        node n2

        edge n1 -> n2
      ELKT

      result = described_class.parse(input)

      expect(result[:children].length).to eq(2)
      expect(result[:edges].length).to eq(1)
    end

    it "parses real ELK layered example" do
      input = <<~ELKT
        edge node1-> node2
        edge node2-> node3
        edge node3-> node4

        node node1
        node node2
        node node3
        node node4
      ELKT

      result = described_class.parse(input)

      expect(result[:children].length).to eq(4)
      expect(result[:edges].length).to eq(3)
    end

    it "parses real ELK box example" do
      input = <<~ELKT
        algorithm: box
        spacing.nodeNode: 2.0

        node node2{
          layout [ size: 30, 30 ]
        }
        node node3{
          layout [ size: 20, 20 ]
        }
      ELKT

      result = described_class.parse(input)

      expect(result[:layoutOptions]["elk.algorithm"]).to eq("box")
      expect(result[:layoutOptions]["elk.spacing.nodeNode"]).to eq(2.0)
      expect(result[:children][0][:width]).to eq(30.0)
      expect(result[:children][1][:width]).to eq(20.0)
    end
  end

  describe "error handling" do
    it "raises error for invalid edge syntax" do
      input = <<~ELKT
        node n1
        edge n1 n2
      ELKT

      expect { described_class.parse(input) }.to raise_error(
        Elkrb::Parsers::ElktParser::ParseError,
        /Invalid edge syntax/,
      )
    end
  end
end
