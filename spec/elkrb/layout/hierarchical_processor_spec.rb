# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::HierarchicalProcessor do
  def layout_json(document, options = {})
    Elkrb.layout(JSON.parse(JSON.generate(document)), options)
  end

  def compound_unsized
    fixture = JSON.parse(
      File.read("spec/fixtures/corpus/compound_unsized.json"),
    )
    fixture.fetch("graph")
  end

  it "does not expose the removed hierarchical call option" do
    expect(Elkrb.known_layout_options).not_to have_key("hierarchical")
  end

  it "sizes compounds before laying out their parent level" do
    result = layout_json(compound_unsized)
    parent, sibling = result.children

    expect([parent.x, parent.y, parent.width, parent.height])
      .to eq([12.0, 12.0, 104.0, 54.0])
    expect([sibling.x, sibling.y]).to eq([136.0, 24.0])
    expect([result.width, result.height]).to eq([178.0, 78.0])
    expect(result).to have_no_overlapping_siblings
  end

  it "applies compound padding once and routes its edge in local coordinates" do
    parent = layout_json(compound_unsized).children.first
    first, second = parent.children
    section = parent.edges.first.sections.first

    expect([first.x, first.y, second.x, second.y])
      .to eq([12.0, 12.0, 62.0, 12.0])
    expect([section.start_point.x, section.start_point.y])
      .to all(be_between(0, parent.width))
    expect([section.end_point.x, section.end_point.y])
      .to all(be_between(0, parent.width))
  end

  it "honours a compound's own padding" do
    result = layout_json(
      "id" => "root",
      "children" => [{
        "id" => "p",
        "layoutOptions" => {
          "elk.padding" => "[top=30,left=30,bottom=30,right=30]",
        },
        "children" => [{ "id" => "c1", "width" => 80, "height" => 30 }],
      }],
      "edges" => [],
    )
    parent = result.children.first

    expect([parent.children.first.x, parent.children.first.y])
      .to eq([30.0, 30.0])
    expect([parent.width, parent.height]).to eq([140.0, 90.0])
  end

  it "leaves cross-level edges unrouted in separate-children mode" do
    result = layout_json(
      "id" => "root",
      "children" => [
        {
          "id" => "p",
          "children" => [{ "id" => "c1", "width" => 30, "height" => 30 }],
          "edges" => [],
        },
        { "id" => "q", "width" => 30, "height" => 30 },
      ],
      "edges" => [{ "id" => "cross", "sources" => ["c1"],
                    "targets" => ["q"] }],
    )

    expect(result.edges.first.sections).to be_nil.or be_empty
  end

  it "recomputes a compound's declared size" do
    graph = compound_unsized
    graph.fetch("children").first.merge!("width" => 10, "height" => 10)

    parent = layout_json(graph).children.first

    expect([parent.width, parent.height]).to eq([104.0, 54.0])
  end

  it "sizes compounds while leaving unsized leaves unsized" do
    result = layout_json(
      "id" => "root",
      "children" => [
        {
          "id" => "p",
          "children" => [{ "id" => "c", "width" => 30, "height" => 30 }],
          "edges" => [],
        },
        { "id" => "leaf" },
      ],
      "edges" => [],
    )
    parent, leaf = result.children

    expect([parent.width, parent.height]).to eq([54.0, 54.0])
    expect([leaf.width, leaf.height]).to eq([nil, nil])
    expect(JSON.parse(result.to_json).fetch("children").last)
      .not_to include("width", "height")
  end

  it "places ports after computing an unsized compound's dimensions" do
    result = layout_json(
      "id" => "root",
      "children" => [{
        "id" => "p",
        "ports" => [
          { "id" => "west", "side" => "WEST" },
          { "id" => "east", "side" => "EAST" },
        ],
        "children" => [{ "id" => "c", "width" => 30, "height" => 30 }],
        "edges" => [],
      }],
      "edges" => [],
    )
    parent = result.children.first
    west, east = parent.ports

    expect([parent.width, parent.height]).to eq([54.0, 54.0])
    expect([west.x, west.y]).to eq([0.0, 27.0])
    expect([east.x, east.y]).to eq([54.0, 27.0])
  end

  it "uses a compound's pinned algorithm while retaining the root algorithm" do
    result = layout_json(
      "id" => "root",
      "layoutOptions" => { "elk.algorithm" => "layered" },
      "children" => [
        {
          "id" => "p",
          "layoutOptions" => { "elk.algorithm" => "box" },
          "children" => [
            { "id" => "c1", "width" => 30, "height" => 30 },
            { "id" => "c2", "width" => 30, "height" => 30 },
            { "id" => "c3", "width" => 30, "height" => 30 },
          ],
          "edges" => [],
        },
        { "id" => "q", "width" => 30, "height" => 30 },
      ],
      "edges" => [{ "id" => "e", "sources" => ["p"], "targets" => ["q"] }],
    )
    parent, sibling = result.children

    expect(parent.children.map(&:y)).to eq([15.0, 15.0, 60.0])
    expect(sibling.x - (parent.x + parent.width)).to eq(20.0)
  end

  it "inherits the root pin when the call names a different algorithm" do
    result = layout_json(
      {
        "id" => "root",
        "layoutOptions" => { "elk.algorithm" => "box" },
        "children" => [{
          "id" => "p",
          "children" => [
            { "id" => "c1", "width" => 30, "height" => 30 },
            { "id" => "c2", "width" => 30, "height" => 30 },
            { "id" => "c3", "width" => 30, "height" => 30 },
          ],
          "edges" => [],
        }],
        "edges" => [],
      },
      algorithm: "layered",
    )

    expect(result.children.first.children.map(&:y)).to eq([15.0, 15.0, 60.0])
  end

  it "reads a compound's algorithm from its properties" do
    result = layout_json(
      "id" => "root",
      "layoutOptions" => { "elk.algorithm" => "layered" },
      "children" => [{
        "id" => "p",
        "properties" => { "elk.algorithm" => "box" },
        "children" => [
          { "id" => "c1", "width" => 30, "height" => 30 },
          { "id" => "c2", "width" => 30, "height" => 30 },
          { "id" => "c3", "width" => 30, "height" => 30 },
        ],
        "edges" => [],
      }],
      "edges" => [],
    )

    expect(result.children.first.children.map(&:y)).to eq([15.0, 15.0, 60.0])
  end

  it "reads a compound's padding from its properties" do
    result = layout_json(
      "id" => "root",
      "children" => [{
        "id" => "p",
        "properties" => {
          "elk.padding" => "[top=30,left=30,bottom=30,right=30]",
        },
        "children" => [{ "id" => "c", "width" => 80, "height" => 30 }],
        "edges" => [],
      }],
      "edges" => [],
    )
    parent = result.children.first

    expect([parent.children.first.x, parent.children.first.y])
      .to eq([30.0, 30.0])
    expect([parent.width, parent.height]).to eq([140.0, 90.0])
  end

  it "raises when a compound pins an unknown algorithm" do
    graph = {
      "id" => "root",
      "children" => [{
        "id" => "p",
        "layoutOptions" => { "elk.algorithm" => "nope" },
        "children" => [{ "id" => "c", "width" => 30, "height" => 30 }],
      }],
    }

    expect { layout_json(graph) }
      .to raise_error(Elkrb::AlgorithmNotFoundError, /nope/)
  end

  it "resolves contained edges only within their own hierarchy level" do
    result = layout_json(
      "id" => "root",
      "children" => [
        { "id" => "c1", "width" => 30, "height" => 30 },
        {
          "id" => "p",
          "children" => [
            { "id" => "c1", "width" => 30, "height" => 30 },
            { "id" => "c2", "width" => 30, "height" => 30 },
          ],
          "edges" => [{ "id" => "inside", "sources" => ["c1"],
                        "targets" => ["c2"] }],
        },
      ],
      "edges" => [],
    )
    parent = result.children.last
    section = parent.edges.first.sections.first

    expect(section.start_point.x).to eq(parent.children.first.x + 15.0)
    expect(section.end_point.x).to eq(parent.children.last.x + 15.0)
  end
end
