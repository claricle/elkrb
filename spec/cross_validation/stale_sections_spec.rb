# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "stale section replacement" do
  let(:payload) do
    path = File.expand_path("../fixtures/corpus/stale_sections.json", __dir__)
    JSON.parse(File.read(path))
  end

  def layout(graph)
    Elkrb.layout(graph, algorithm: payload.fetch("algorithm"))
  end

  def serialized_sections(graph)
    JSON.parse(graph.to_json).fetch("edges").first.fetch("sections")
  end

  it "discards the fixture's stale coordinates and extra section state" do
    sections = serialized_sections(layout(payload.fetch("graph")))

    expect(sections.length).to eq(1)
    expect(sections.first.fetch("startPoint")).to eq("x" => 42.0, "y" => 27.0)
    expect(sections.first.fetch("endPoint")).to eq("x" => 62.0, "y" => 27.0)
  end

  it "produces identical sections when the laid-out graph is laid out again" do
    first = layout(payload.fetch("graph"))
    first_sections = serialized_sections(first)

    second_sections = serialized_sections(layout(first))

    expect(second_sections).to eq(first_sections)
    expect(second_sections.first.fetch("bendPoints", []).length)
      .to eq(first_sections.first.fetch("bendPoints", []).length)
  end
end
