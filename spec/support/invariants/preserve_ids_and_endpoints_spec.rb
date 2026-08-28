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
    result.edges.first.sources, result.edges.first.targets =
      result.edges.first.targets, result.edges.first.sources

    expect(result).not_to preserve_ids_and_endpoints(input_hash)
  end
end

RSpec.describe "preserve_ids_and_endpoints duplicate detection" do
  # Indexing children/edges by id keeps only the last entry per id, so a
  # result that duplicated `a` and `e1` passed as long as the final copy
  # still matched the input.
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

  let(:result) { Elkrb.layout(Elkrb::Graph::Graph.from_hash(input_hash), {}) }

  it "fails when a node id appears twice in the result" do
    result.children << result.children.first

    expect(result).not_to preserve_ids_and_endpoints(input_hash)
  end

  it "fails when an edge id appears twice in the result" do
    result.edges << result.edges.first

    expect(result).not_to preserve_ids_and_endpoints(input_hash)
  end

  it "fails when a duplicate is nested inside a compound child" do
    nested_input = {
      "id" => "root",
      "children" => [
        { "id" => "p",
          "children" => [{ "id" => "c1", "width" => 30, "height" => 30 }] },
      ],
    }
    nested = Elkrb.layout(Elkrb::Graph::Graph.from_hash(nested_input), {})
    compound = nested.children.first
    compound.children << compound.children.first

    expect(nested).not_to preserve_ids_and_endpoints(nested_input)
  end
end
