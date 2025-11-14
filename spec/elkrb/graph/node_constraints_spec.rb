# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Graph::NodeConstraints do
  describe "initialization" do
    it "creates constraints with default values" do
      constraints = described_class.new

      expect(constraints.fixed_position).to be false
      expect(constraints.layer).to be_nil
      expect(constraints.align_group).to be_nil
      expect(constraints.align_direction).to be_nil
      expect(constraints.relative_to).to be_nil
      expect(constraints.relative_offset).to be_nil
      expect(constraints.position_priority).to eq(0)
    end

    it "creates constraints with fixed_position" do
      constraints = described_class.new(fixed_position: true)

      expect(constraints.fixed_position).to be true
    end

    it "creates constraints with layer assignment" do
      constraints = described_class.new(layer: 2)

      expect(constraints.layer).to eq(2)
    end

    it "creates constraints with alignment" do
      constraints = described_class.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      expect(constraints.align_group).to eq("databases")
      expect(constraints.align_direction).to eq("horizontal")
    end

    it "creates constraints with relative positioning" do
      offset = Elkrb::Graph::RelativeOffset.new(x: 150, y: 0)
      constraints = described_class.new(
        relative_to: "backend",
        relative_offset: offset,
      )

      expect(constraints.relative_to).to eq("backend")
      expect(constraints.relative_offset.x).to eq(150)
      expect(constraints.relative_offset.y).to eq(0)
    end
  end

  describe "align_direction validation" do
    it "accepts horizontal direction" do
      constraints = described_class.new

      expect do
        constraints.align_direction = "horizontal"
      end.not_to raise_error

      expect(constraints.align_direction).to eq("horizontal")
    end

    it "accepts vertical direction" do
      constraints = described_class.new

      expect do
        constraints.align_direction = "vertical"
      end.not_to raise_error

      expect(constraints.align_direction).to eq("vertical")
    end

    it "normalizes direction to lowercase" do
      constraints = described_class.new
      constraints.align_direction = "HORIZONTAL"

      expect(constraints.align_direction).to eq("horizontal")
    end

    it "raises error for invalid direction" do
      constraints = described_class.new

      expect do
        constraints.align_direction = "diagonal"
      end.to raise_error(ArgumentError, /Invalid align_direction/)
    end

    it "allows nil direction" do
      constraints = described_class.new

      expect do
        constraints.align_direction = nil
      end.not_to raise_error

      expect(constraints.align_direction).to be_nil
    end
  end

  describe "JSON serialization" do
    it "serializes to JSON" do
      offset = Elkrb::Graph::RelativeOffset.new(x: 100, y: 50)
      constraints = described_class.new(
        fixed_position: true,
        layer: 1,
        align_group: "backend",
        align_direction: "horizontal",
        relative_to: "api",
        relative_offset: offset,
        position_priority: 5,
      )

      json = constraints.to_json
      parsed = JSON.parse(json)

      expect(parsed["fixedPosition"]).to be true
      expect(parsed["layer"]).to eq(1)
      expect(parsed["alignGroup"]).to eq("backend")
      expect(parsed["alignDirection"]).to eq("horizontal")
      expect(parsed["relativeTo"]).to eq("api")
      expect(parsed["relativeOffset"]["x"]).to eq(100)
      expect(parsed["relativeOffset"]["y"]).to eq(50)
      expect(parsed["positionPriority"]).to eq(5)
    end

    it "deserializes from JSON" do
      json = <<~JSON
        {
          "fixedPosition": true,
          "layer": 2,
          "alignGroup": "databases"
        }
      JSON

      constraints = described_class.from_json(json)

      expect(constraints.fixed_position).to be true
      expect(constraints.layer).to eq(2)
      expect(constraints.align_group).to eq("databases")
    end
  end

  describe "YAML serialization" do
    it "serializes to YAML" do
      constraints = described_class.new(
        fixed_position: true,
        layer: 1,
      )

      yaml = constraints.to_yaml
      parsed = YAML.safe_load(yaml)

      expect(parsed["fixedPosition"]).to be true
      expect(parsed["layer"]).to eq(1)
    end

    it "deserializes from YAML" do
      yaml = <<~YAML
        fixedPosition: true
        layer: 2
        alignGroup: databases
        alignDirection: horizontal
      YAML

      constraints = described_class.from_yaml(yaml)

      expect(constraints.fixed_position).to be true
      expect(constraints.layer).to eq(2)
      expect(constraints.align_group).to eq("databases")
      expect(constraints.align_direction).to eq("horizontal")
    end
  end
end

RSpec.describe Elkrb::Graph::RelativeOffset do
  describe "initialization" do
    it "creates offset with default values" do
      offset = described_class.new

      expect(offset.x).to eq(0.0)
      expect(offset.y).to eq(0.0)
    end

    it "creates offset with custom values" do
      offset = described_class.new(x: 150, y: 75)

      expect(offset.x).to eq(150)
      expect(offset.y).to eq(75)
    end
  end

  describe "JSON serialization" do
    it "serializes to JSON" do
      offset = described_class.new(x: 100, y: 50)

      json = offset.to_json
      parsed = JSON.parse(json)

      expect(parsed["x"]).to eq(100)
      expect(parsed["y"]).to eq(50)
    end

    it "deserializes from JSON" do
      json = '{"x": 200, "y": 100}'

      offset = described_class.from_json(json)

      expect(offset.x).to eq(200)
      expect(offset.y).to eq(100)
    end
  end
end
