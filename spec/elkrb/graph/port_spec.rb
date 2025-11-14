# frozen_string_literal: true

require "spec_helper"
require "elkrb/graph/port"
require "elkrb/graph/label"
require "elkrb/graph/layout_options"

RSpec.describe Elkrb::Graph::Port do
  describe "initialization" do
    it "creates a port with default attributes" do
      port = described_class.new
      expect(port.side).to eq("UNDEFINED")
      expect(port.index).to eq(-1)
      expect(port.offset).to eq(0.0)
    end

    it "creates a port with specified attributes" do
      port = described_class.new(
        id: "p1",
        x: 10.0,
        y: 20.0,
        width: 5.0,
        height: 5.0,
        side: "NORTH",
        index: 0,
        offset: 15.0,
      )

      expect(port.id).to eq("p1")
      expect(port.x).to eq(10.0)
      expect(port.y).to eq(20.0)
      expect(port.width).to eq(5.0)
      expect(port.height).to eq(5.0)
      expect(port.side).to eq("NORTH")
      expect(port.index).to eq(0)
      expect(port.offset).to eq(15.0)
    end
  end

  describe "port side constants" do
    it "defines NORTH constant" do
      expect(described_class::NORTH).to eq("NORTH")
    end

    it "defines SOUTH constant" do
      expect(described_class::SOUTH).to eq("SOUTH")
    end

    it "defines EAST constant" do
      expect(described_class::EAST).to eq("EAST")
    end

    it "defines WEST constant" do
      expect(described_class::WEST).to eq("WEST")
    end

    it "defines UNDEFINED constant" do
      expect(described_class::UNDEFINED).to eq("UNDEFINED")
    end

    it "defines SIDES array" do
      expect(described_class::SIDES).to contain_exactly(
        "NORTH", "SOUTH", "EAST", "WEST", "UNDEFINED"
      )
    end
  end

  describe "#side=" do
    let(:port) { described_class.new }

    it "accepts valid uppercase side value" do
      port.side = "NORTH"
      expect(port.side).to eq("NORTH")
    end

    it "accepts valid lowercase side value and converts to uppercase" do
      port.side = "south"
      expect(port.side).to eq("SOUTH")
    end

    it "accepts valid mixed case side value and converts to uppercase" do
      port.side = "EaSt"
      expect(port.side).to eq("EAST")
    end

    it "raises ArgumentError for invalid side value" do
      expect { port.side = "INVALID" }.to raise_error(
        ArgumentError, /Invalid port side: INVALID/
      )
    end

    it "accepts nil value without error" do
      expect { port.side = nil }.not_to raise_error
    end

    it "accepts all valid side constants" do
      described_class::SIDES.each do |side|
        expect { port.side = side }.not_to raise_error
        expect(port.side).to eq(side)
      end
    end
  end

  describe "#index attribute" do
    let(:port) { described_class.new }

    it "defaults to -1" do
      expect(port.index).to eq(-1)
    end

    it "can be set to positive value" do
      port.index = 5
      expect(port.index).to eq(5)
    end

    it "can be set to zero" do
      port.index = 0
      expect(port.index).to eq(0)
    end

    it "can remain negative" do
      port.index = -1
      expect(port.index).to eq(-1)
    end
  end

  describe "#offset attribute" do
    let(:port) { described_class.new }

    it "defaults to 0.0" do
      expect(port.offset).to eq(0.0)
    end

    it "can be set to positive value" do
      port.offset = 42.5
      expect(port.offset).to eq(42.5)
    end

    it "can be set to zero" do
      port.offset = 0.0
      expect(port.offset).to eq(0.0)
    end

    it "can be set to negative value" do
      port.offset = -10.0
      expect(port.offset).to eq(-10.0)
    end
  end

  describe "#detect_side" do
    let(:port) { described_class.new }
    let(:node_width) { 100.0 }
    let(:node_height) { 60.0 }

    context "when port position is not set" do
      it "returns UNDEFINED when x is nil" do
        port.y = 30.0
        expect(port.detect_side(node_width, node_height))
          .to eq(described_class::UNDEFINED)
      end

      it "returns UNDEFINED when y is nil" do
        port.x = 50.0
        expect(port.detect_side(node_width, node_height))
          .to eq(described_class::UNDEFINED)
      end

      it "returns UNDEFINED when both x and y are nil" do
        expect(port.detect_side(node_width, node_height))
          .to eq(described_class::UNDEFINED)
      end
    end

    context "when node dimensions are invalid" do
      it "returns UNDEFINED when node_width is nil" do
        port.x = 50.0
        port.y = 30.0
        expect(port.detect_side(nil, node_height))
          .to eq(described_class::UNDEFINED)
      end

      it "returns UNDEFINED when node_height is nil" do
        port.x = 50.0
        port.y = 30.0
        expect(port.detect_side(node_width, nil))
          .to eq(described_class::UNDEFINED)
      end

      it "returns UNDEFINED when node_width is zero" do
        port.x = 50.0
        port.y = 30.0
        expect(port.detect_side(0, node_height))
          .to eq(described_class::UNDEFINED)
      end

      it "returns UNDEFINED when node_height is zero" do
        port.x = 50.0
        port.y = 30.0
        expect(port.detect_side(node_width, 0))
          .to eq(described_class::UNDEFINED)
      end
    end

    context "with valid port and node dimensions" do
      it "detects NORTH for port at top center" do
        port.x = 50.0
        port.y = 0.0
        expect(port.detect_side(node_width, node_height))
          .to eq(described_class::NORTH)
      end

      it "detects SOUTH for port at bottom center" do
        port.x = 50.0
        port.y = 60.0
        expect(port.detect_side(node_width, node_height))
          .to eq(described_class::SOUTH)
      end

      it "detects WEST for port at left center" do
        port.x = 0.0
        port.y = 30.0
        expect(port.detect_side(node_width, node_height))
          .to eq(described_class::WEST)
      end

      it "detects EAST for port at right center" do
        port.x = 100.0
        port.y = 30.0
        expect(port.detect_side(node_width, node_height))
          .to eq(described_class::EAST)
      end

      it "detects side for port near top-left corner" do
        port.x = 10.0
        port.y = 5.0
        side = port.detect_side(node_width, node_height)
        expect([described_class::NORTH, described_class::WEST]).to include(side)
      end

      it "detects side for port near top-right corner" do
        port.x = 90.0
        port.y = 5.0
        side = port.detect_side(node_width, node_height)
        expect([described_class::NORTH, described_class::EAST]).to include(side)
      end

      it "detects side for port near bottom-left corner" do
        port.x = 10.0
        port.y = 55.0
        side = port.detect_side(node_width, node_height)
        expect([described_class::SOUTH, described_class::WEST]).to include(side)
      end

      it "detects side for port near bottom-right corner" do
        port.x = 90.0
        port.y = 55.0
        side = port.detect_side(node_width, node_height)
        expect([described_class::SOUTH, described_class::EAST]).to include(side)
      end
    end
  end

  describe "JSON serialization" do
    let(:port) do
      described_class.new(
        id: "p1",
        x: 10.0,
        y: 20.0,
        side: "NORTH",
        index: 2,
        offset: 15.0,
      )
    end

    it "serializes to JSON with all attributes" do
      json = port.to_json
      parsed = JSON.parse(json)

      expect(parsed["id"]).to eq("p1")
      expect(parsed["x"]).to eq(10.0)
      expect(parsed["y"]).to eq(20.0)
      expect(parsed["side"]).to eq("NORTH")
      expect(parsed["index"]).to eq(2)
      expect(parsed["offset"]).to eq(15.0)
    end

    it "deserializes from JSON with all attributes" do
      json_str = '{"id":"p1","x":10.0,"y":20.0,"side":"NORTH","index":2,"offset":15.0}'
      port = described_class.from_json(json_str)

      expect(port.id).to eq("p1")
      expect(port.x).to eq(10.0)
      expect(port.y).to eq(20.0)
      expect(port.side).to eq("NORTH")
      expect(port.index).to eq(2)
      expect(port.offset).to eq(15.0)
    end
  end

  describe "YAML serialization" do
    let(:port) do
      described_class.new(
        id: "p1",
        x: 10.0,
        y: 20.0,
        side: "SOUTH",
        index: 1,
        offset: 25.0,
      )
    end

    it "serializes to YAML with all attributes" do
      yaml_str = port.to_yaml
      parsed = described_class.from_yaml(yaml_str)

      expect(parsed.id).to eq("p1")
      expect(parsed.x).to eq(10.0)
      expect(parsed.y).to eq(20.0)
      expect(parsed.side).to eq("SOUTH")
      expect(parsed.index).to eq(1)
      expect(parsed.offset).to eq(25.0)
    end
  end

  describe "node reference" do
    let(:port) { described_class.new(id: "p1") }

    it "allows setting node reference" do
      node = double("node")
      port.node = node
      expect(port.node).to eq(node)
    end

    it "node reference is not serialized to JSON" do
      node = double("node")
      port.node = node
      json = port.to_json
      parsed = JSON.parse(json)
      expect(parsed).not_to have_key("node")
    end
  end
end
