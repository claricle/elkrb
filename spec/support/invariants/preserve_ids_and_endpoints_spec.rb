# frozen_string_literal: true

require_relative "preserve_ids_and_endpoints"

RSpec.describe "preserve_ids_and_endpoints" do
  let(:input_hash) do
    {
      "id" => "root",
      "children" => [
        { "id" => "a", "width" => 30, "height" => 30 },
        { "id" => "b", "width" => 30, "height" => 30 },
      ],
      "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }],
    }
  end

  it "passes when every node and edge survives layout with unchanged endpoints" do
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})

    expect(result).to preserve_ids_and_endpoints(input_hash)
  end

  it "fails when an edge's endpoints changed" do
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})
    result.edges.first.sources, result.edges.first.targets = result.edges.first.targets, result.edges.first.sources

    expect(result).not_to preserve_ids_and_endpoints(input_hash)
  end
end
