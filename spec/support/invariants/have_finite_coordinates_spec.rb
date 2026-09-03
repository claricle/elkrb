# frozen_string_literal: true

require_relative "have_finite_coordinates"

RSpec.describe "have_finite_coordinates" do
  it "passes a graph laid out from ordinary input" do
    graph = Elkrb::Graph::Graph.from_hash(
      { "id" => "root",
        "children" => [{ "id" => "a", "width" => 30, "height" => 30 }] },
    )
    result = Elkrb.layout(graph, {})

    expect(result).to have_finite_coordinates
  end

  it "fails when a node's position is NaN" do
    graph = Elkrb::Graph::Graph.new(id: "root")
    graph.children = [Elkrb::Graph::Node.new(id: "a", x: Float::NAN, y: 0.0,
                                             width: 30.0, height: 30.0)]

    expect(graph).not_to have_finite_coordinates
  end
  # Both of these passed the matcher and then crashed serialization with
  # JSON::GeneratorError, which is the tell that the value was reachable and
  # simply unchecked.
  it "rejects a root carrying a non-finite position" do
    graph = Elkrb::Graph::Graph.new
    graph.children = []
    graph.edges = []
    graph.x = Float::NAN

    expect(graph).not_to have_finite_coordinates
  end

  it "rejects a port carrying a non-finite offset" do
    port = Elkrb::Graph::Port.new(id: "p", x: 0.0, y: 0.0)
    port.offset = Float::INFINITY
    node = Elkrb::Graph::Node.new(id: "a", x: 0.0, y: 0.0,
                                  width: 1.0, height: 1.0)
    node.ports = [port]
    graph = Elkrb::Graph::Graph.new
    graph.children = [node]
    graph.edges = []

    expect(graph).not_to have_finite_coordinates
  end

  # Everything below pins ONE rule each. Every one of these was measured to
  # survive deletion before it was written: the matcher could lose the rule
  # and the whole suite stayed green.

  def bad_node(width: 1.0, height: 1.0)
    Elkrb::Graph::Node.new(id: "a", x: 0.0, y: 0.0,
                           width: width, height: height)
  end

  def graph_with(node)
    graph = Elkrb::Graph::Graph.new
    graph.children = [node]
    graph.edges = []
    graph
  end

  it "rejects a root carrying a non-finite dimension" do
    graph = Elkrb::Graph::Graph.new
    graph.children = []
    graph.edges = []
    graph.width = Float::NAN

    expect(graph).not_to have_finite_coordinates
  end

  it "rejects a node carrying a non-finite dimension" do
    expect(graph_with(bad_node(width: Float::NAN)))
      .not_to have_finite_coordinates
  end

  # Finite is not enough. A negative width is finite, serializes cleanly, and
  # describes a rectangle whose right edge is left of its left edge.
  it "rejects a negative dimension even though it is finite" do
    expect(graph_with(bad_node(width: -5.0)))
      .not_to have_finite_coordinates
  end

  it "rejects a node label carrying a non-finite position" do
    node = bad_node
    node.labels = [Elkrb::Graph::Label.new(id: "l", x: Float::NAN, y: 0.0)]

    expect(graph_with(node)).not_to have_finite_coordinates
  end

  it "rejects a node label carrying a non-finite dimension" do
    node = bad_node
    node.labels = [Elkrb::Graph::Label.new(id: "l", x: 0.0, y: 0.0,
                                           width: Float::INFINITY)]

    expect(graph_with(node)).not_to have_finite_coordinates
  end

  it "rejects a port carrying a non-finite position" do
    node = bad_node
    node.ports = [Elkrb::Graph::Port.new(id: "p", x: Float::NAN, y: 0.0)]

    expect(graph_with(node)).not_to have_finite_coordinates
  end

  it "rejects a port carrying a non-finite dimension" do
    node = bad_node
    node.ports = [Elkrb::Graph::Port.new(id: "p", x: 0.0, y: 0.0,
                                         height: Float::NAN)]

    expect(graph_with(node)).not_to have_finite_coordinates
  end

  # A port's own labels are a third level down and were reached by nothing.
  it "rejects a label on a port carrying a non-finite position" do
    port = Elkrb::Graph::Port.new(id: "p", x: 0.0, y: 0.0)
    port.labels = [Elkrb::Graph::Label.new(id: "pl", x: Float::NAN, y: 0.0)]
    node = bad_node
    node.ports = [port]

    expect(graph_with(node)).not_to have_finite_coordinates
  end

  def graph_with_section(section)
    edge = Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["a"])
    edge.sections = [section]
    graph = Elkrb::Graph::Graph.new
    graph.children = [bad_node]
    graph.edges = [edge]
    graph
  end

  def point(pos_x, pos_y)
    Elkrb::Geometry::Point.new(x: pos_x, y: pos_y)
  end

  def section(start_point: point(0.0, 0.0), end_point: point(1.0, 1.0),
              bend_points: nil)
    Elkrb::Graph::EdgeSection.new(id: "s", start_point: start_point,
                                  end_point: end_point,
                                  bend_points: bend_points)
  end

  # A section that exists with no start or end is malformed, not an omission:
  # `sections` being absent entirely is the legitimate shape, and that never
  # reaches this check.
  it "rejects a section whose start point is missing" do
    expect(graph_with_section(section(start_point: nil)))
      .not_to have_finite_coordinates
  end

  it "rejects a section whose start point is non-finite" do
    expect(graph_with_section(section(start_point: point(Float::NAN, 0.0))))
      .not_to have_finite_coordinates
  end

  it "rejects a section whose end point is non-finite" do
    expect(graph_with_section(section(end_point: point(0.0, Float::NAN))))
      .not_to have_finite_coordinates
  end

  it "rejects a section carrying a non-finite bend point" do
    expect(graph_with_section(section(bend_points: [point(Float::NAN, 0.0)])))
      .not_to have_finite_coordinates
  end

  it "rejects an edge label carrying a non-finite position" do
    edge = Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["a"])
    edge.sections = []
    edge.labels = [Elkrb::Graph::Label.new(id: "el", x: Float::NAN, y: 0.0)]
    graph = Elkrb::Graph::Graph.new
    graph.children = [bad_node]
    graph.edges = [edge]

    expect(graph).not_to have_finite_coordinates
  end
end
