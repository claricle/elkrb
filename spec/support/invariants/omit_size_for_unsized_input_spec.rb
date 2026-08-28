# frozen_string_literal: true

require_relative "omit_size_for_unsized_input"

RSpec.describe "omit_size_for_unsized_input" do
  it "passes when an unsized leaf node stays unsized" do
    input_hash = {
      "id" => "root",
      "children" => [{ "id" => "a" },
                     { "id" => "b", "width" => 30, "height" => 30 }],
      "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }],
    }
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})

    expect(result).to omit_size_for_unsized_input(input_hash)
  end

  # `q` is what gives this example teeth. An EMPTY compound like `p` comes
  # back from layout with width and height still nil, so it reaches
  # `check_dimensions` with nothing to flag and would pass with the
  # exemption deleted. `q` has a real child, so layout computes it a
  # 44x44 size it never declared, and the exemption is then the only
  # reason no violation is reported. `p` stays to cover the empty case.
  it "exempts a node with a children key present, even empty" do
    input_hash = { "id" => "root",
                   "children" => [{ "id" => "p", "children" => [] },
                                  { "id" => "q",
                                    "children" => [{ "id" => "c",
                                                     "width" => 20,
                                                     "height" => 20 }] }],
                   "edges" => [] }
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
