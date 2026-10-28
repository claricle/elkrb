# frozen_string_literal: true

require "spec_helper"

RSpec.describe "cross-level edge routing" do
  include CrossLevelEdgeHelpers

  let(:fixture_path) do
    File.expand_path("../../fixtures/c4_include_children.json", __dir__)
  end
  let(:fixture) { JSON.parse(File.read(fixture_path)) }

  it "routes a root relationship between nested members in the root frame" do
    result = nil
    warnings = capture_elkrb_warnings do
      result = layout_cross_level_graph(fixture)
    end

    section = result.edges.first.sections.first
    source = absolute_rectangle(result, "boundary_1", "member_1")
    target = absolute_rectangle(result, "boundary_2", "member_2")

    expect(result.edges.first.sections.length).to eq(1)
    expect(section).to have_attributes(
      id: "relationship_s0",
      incoming_shape: "member_1",
      outgoing_shape: "member_2",
    )
    expect(result.edges.first.container).to eq("root")
    expect(point_on_border?(section.start_point, source)).to be(true)
    expect(point_on_border?(section.end_point, target)).to be(true)
    expect(warnings.scan("elk.hierarchyHandling is partially honoured").size)
      .to eq(1)
  end

  it "does not move nodes when INCLUDE_CHILDREN adds the section" do
    included = layout_cross_level_graph(fixture)
    without_key = Marshal.load(Marshal.dump(fixture))
    without_key.fetch("layoutOptions").delete("elk.hierarchyHandling")

    expect(nested_coordinates(included))
      .to eq(nested_coordinates(layout_cross_level_graph(without_key)))
  end

  it "keeps a nested port endpoint at its absolute port origin" do
    graph = Marshal.load(Marshal.dump(fixture))
    source = graph.fetch("children").fetch(0).fetch("children").fetch(0)
    source["ports"] = [
      { "id" => "member_1_port", "x" => 30, "y" => 15,
        "width" => 0, "height" => 0 },
    ]
    graph.fetch("edges").fetch(0)["sources"] = ["member_1_port"]

    result = layout_cross_level_graph(graph)
    boundary = child_by_id(result, "boundary_1")
    member = child_by_id(boundary, "member_1")
    port = member.ports.first
    expected = [boundary.x + member.x + port.x,
                boundary.y + member.y + port.y]

    section = result.edges.first.sections.first
    expect([section.start_point.x, section.start_point.y]).to eq(expected)
  end

  it "uses the shared routing-style bend rules" do
    sections = %w[ORTHOGONAL POLYLINE SPLINES].to_h do |style|
      graph = Marshal.load(Marshal.dump(fixture))
      target_children = graph.fetch("children").fetch(1).fetch("children")
      target = target_children.shift
      target_children.push(
        { "id" => "spacer_1", "width" => 30, "height" => 30 },
        { "id" => "spacer_2", "width" => 30, "height" => 30 },
        target,
      )
      graph.fetch("edges").fetch(0)["layoutOptions"] = {
        "elk.edgeRouting" => style,
      }
      [style, layout_cross_level_graph(graph).edges.first.sections.first]
    end

    expect(sections.fetch("POLYLINE").bend_points).to be_empty
    expect(sections.fetch("SPLINES").bend_points.length).to eq(2)
    expect(sections.fetch("ORTHOGONAL").bend_points.length).to eq(2)
  end

  it "leaves an unresolved cross-level endpoint unrouted" do
    graph = Marshal.load(Marshal.dump(fixture))
    graph.fetch("edges").fetch(0)["targets"] = ["missing"]

    expect(layout_cross_level_graph(graph).edges.first.sections).to be_nil
  end

  it "keeps a recursively routed edge in its owning compound frame" do
    nested = Marshal.load(Marshal.dump(fixture))
    compound = {
      "id" => "compound",
      "layoutOptions" => nested.fetch("layoutOptions"),
      "children" => nested.fetch("children"),
      "edges" => nested.fetch("edges"),
    }
    graph = { "id" => "root", "children" => [compound], "edges" => [] }

    result = layout_cross_level_graph(graph)
    owner = result.children.first
    edge = owner.edges.first
    section = edge.sections.first
    source = absolute_rectangle(owner, "boundary_1", "member_1")
    target = absolute_rectangle(owner, "boundary_2", "member_2")

    expect(edge.sections.length).to eq(1)
    expect(edge.container).to eq("compound")
    expect(point_on_border?(section.start_point, source)).to be(true)
    expect(point_on_border?(section.end_point, target)).to be(true)
  end

  [nil, "SEPARATE_CHILDREN"].each do |value|
    label = value || "an absent hierarchy option"

    it "leaves the cross-level edge unrouted with #{label}" do
      graph = Marshal.load(Marshal.dump(fixture))
      if value
        graph.fetch("layoutOptions")["elk.hierarchyHandling"] = value
      else
        graph.fetch("layoutOptions").delete("elk.hierarchyHandling")
      end

      expect(layout_cross_level_graph(graph).edges.first.sections).to be_nil
    end
  end

  it "rejects an endpoint id that is ambiguous across levels" do
    graph = Marshal.load(Marshal.dump(fixture))
    duplicate = { "id" => "member_1", "width" => 30, "height" => 30 }
    graph.fetch("children").fetch(1).fetch("children") << duplicate

    expect { layout_cross_level_graph(graph) }
      .to raise_error(Elkrb::ValidationError,
                      /ambiguous id across levels: member_1/)
  end

  it "rejects an ambiguous id before classifying a raw-id self-loop" do
    graph = Marshal.load(Marshal.dump(fixture))
    duplicate = { "id" => "member_1", "width" => 30, "height" => 30 }
    graph.fetch("children").fetch(1).fetch("children") << duplicate
    graph.fetch("edges").fetch(0)["targets"] = ["member_1"]

    expect { layout_cross_level_graph(graph) }
      .to raise_error(Elkrb::ValidationError,
                      /ambiguous id across levels: member_1/)
  end
end
