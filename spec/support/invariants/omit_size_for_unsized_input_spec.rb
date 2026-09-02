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
  # Three rules had no example at all: the recursion into nested children,
  # the label check, and the port check. Removing any of them left the file
  # green, so each could have vanished unnoticed.
  it "finds an unsized NESTED node that gained a size" do
    input = { "id" => "root",
              "children" => [{ "id" => "p", "width" => 50, "height" => 50,
                               "children" => [{ "id" => "deep" }] }],
              "edges" => [] }
    deep = Elkrb::Graph::Node.new(id: "deep", width: 9.0, height: 9.0)
    parent = Elkrb::Graph::Node.new(id: "p", width: 50.0, height: 50.0)
    parent.children = [deep]
    graph = Elkrb::Graph::Graph.new(id: "root")
    graph.children = [parent]
    graph.edges = []

    expect(graph).not_to omit_size_for_unsized_input(input)
  end

  it "finds an unsized LABEL that gained a size" do
    input = { "id" => "root",
              "children" => [{ "id" => "a", "width" => 5, "height" => 5,
                               "labels" => [{ "id" => "l" }] }],
              "edges" => [] }
    node = Elkrb::Graph::Node.new(id: "a", width: 5.0, height: 5.0)
    node.labels = [Elkrb::Graph::Label.new(id: "l", width: 7.0, height: 7.0)]
    graph = Elkrb::Graph::Graph.new(id: "root")
    graph.children = [node]
    graph.edges = []

    expect(graph).not_to omit_size_for_unsized_input(input)
  end

  it "finds an unsized PORT that gained a size" do
    input = { "id" => "root",
              "children" => [{ "id" => "a", "width" => 5, "height" => 5,
                               "ports" => [{ "id" => "p" }] }],
              "edges" => [] }
    node = Elkrb::Graph::Node.new(id: "a", width: 5.0, height: 5.0)
    node.ports = [Elkrb::Graph::Port.new(id: "p", width: 3.0, height: 3.0)]
    graph = Elkrb::Graph::Graph.new(id: "root")
    graph.children = [node]
    graph.edges = []

    expect(graph).not_to omit_size_for_unsized_input(input)
  end
end
