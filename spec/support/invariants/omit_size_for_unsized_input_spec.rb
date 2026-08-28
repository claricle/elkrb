# frozen_string_literal: true

require_relative "omit_size_for_unsized_input"

RSpec.describe "omit_size_for_unsized_input" do
  it "passes when an unsized leaf node stays unsized" do
    input_hash = { "id" => "root", "children" => [{ "id" => "a" }, { "id" => "b", "width" => 30, "height" => 30 }],
                   "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }] }
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})

    expect(result).to omit_size_for_unsized_input(input_hash)
  end

  it "exempts a node with a children key present, even empty" do
    input_hash = { "id" => "root",
                   "children" => [{ "id" => "p", "children" => [] }], "edges" => [] }
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})

    expect(result).to omit_size_for_unsized_input(input_hash)
  end

  it "fails when an unsized leaf gained a size in the actual result" do
    input_hash = { "id" => "root", "children" => [{ "id" => "a" }],
                   "edges" => [] }
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})
    result.children.first.width = 30.0
    result.children.first.height = 30.0

    expect(result).not_to omit_size_for_unsized_input(input_hash)
  end
end
