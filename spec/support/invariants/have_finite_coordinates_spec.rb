# frozen_string_literal: true

require_relative "have_finite_coordinates"

RSpec.describe "have_finite_coordinates" do
  it "passes a graph laid out from ordinary input" do
    graph = Elkrb::Graph::Graph.from_hash(
      { "id" => "root", "children" => [{ "id" => "a", "width" => 30, "height" => 30 }] },
    )
    result = Elkrb.layout(graph, {})

    expect(result).to have_finite_coordinates
  end

  it "fails when a node's position is NaN" do
    graph = Elkrb::Graph::Graph.new(id: "root")
    graph.children = [Elkrb::Graph::Node.new(id: "a", x: Float::NAN, y: 0.0, width: 30.0, height: 30.0)]

    expect(graph).not_to have_finite_coordinates
  end
end
