# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Graph::Label do
  # `properties` is the one open map every other model already carries; without
  # it an elkjs label silently loses whatever the caller parked there.
  describe "properties" do
    it "round-trips through JSON" do
      source = %({"id":"l","text":"A","properties":{"kind":"title"}})

      expect(JSON.parse(described_class.from_json(source).to_json))
        .to eq(JSON.parse(source))
    end

    it "reads the map from JSON" do
      label = described_class.from_json(
        %({"id":"l","properties":{"kind":"title"}}),
      )

      expect(label.properties).to eq("kind" => "title")
    end

    it "round-trips through YAML" do
      yaml = "id: l\nproperties:\n  kind: title\n"

      expect(YAML.safe_load(described_class.from_yaml(yaml).to_yaml))
        .to eq(YAML.safe_load(yaml))
    end

    it "omits the key when the input carried none" do
      label = described_class.from_json(%({"id":"l","text":"A"}))

      expect(JSON.parse(label.to_json)).not_to have_key("properties")
    end
  end
end
