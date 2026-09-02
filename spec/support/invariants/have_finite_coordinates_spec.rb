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
end
