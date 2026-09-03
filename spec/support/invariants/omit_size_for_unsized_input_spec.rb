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
  # The exemption has to be LOAD-BEARING, so the actual node must gain a
  # size. A real layout does not do that -- measured, a `"children": []` node
  # comes back with width and height still nil, so the earlier version of
  # this example passed whether the exemption existed or not. The result is
  # built by hand instead.
  it "exempts a declared compound that gained a computed size" do
    input_hash = { "id" => "root",
                   "children" => [{ "id" => "p", "children" => [] }],
                   "edges" => [] }
    compound = Elkrb::Graph::Node.new(id: "p", width: 40.0, height: 40.0)
    compound.children = []
    result = Elkrb::Graph::Graph.new(id: "root")
    result.children = [compound]
    result.edges = []

    expect(result).to omit_size_for_unsized_input(input_hash)
  end

  it "still flags a node with no children key that gained a size" do
    input_hash = { "id" => "root", "children" => [{ "id" => "p" }],
                   "edges" => [] }
    leaf = Elkrb::Graph::Node.new(id: "p", width: 40.0, height: 40.0)
    result = Elkrb::Graph::Graph.new(id: "root")
    result.children = [leaf]
    result.edges = []

    expect(result).not_to omit_size_for_unsized_input(input_hash)
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

  # The four below pin rules the matcher had but nothing exercised: a
  # port's labels, an edge's labels, and both halves of the id-less label
  # path. Each was measured to survive deletion with the whole suite green.
  #
  # Layout does not assign a size to a label it was not given, so as with
  # the compound exemption above, the actual result is built by hand. That
  # is the only way to make the rule load-bearing.

  def sized_label(id: nil)
    Elkrb::Graph::Label.new(id: id, width: 40.0, height: 12.0)
  end

  it "flags an unsized label on a port that gained a size" do
    input_hash = {
      "id" => "root",
      "children" => [{ "id" => "a", "width" => 10, "height" => 10,
                       "ports" => [{ "id" => "p",
                                     "labels" => [{ "id" => "pl" }] }] }],
      "edges" => [],
    }
    port = Elkrb::Graph::Port.new(id: "p")
    port.labels = [sized_label(id: "pl")]
    node = Elkrb::Graph::Node.new(id: "a", width: 10.0, height: 10.0)
    node.ports = [port]
    result = Elkrb::Graph::Graph.new(id: "root")
    result.children = [node]
    result.edges = []

    expect(result).not_to omit_size_for_unsized_input(input_hash)
  end

  it "flags an unsized label on an edge that gained a size" do
    input_hash = {
      "id" => "root",
      "children" => [{ "id" => "a", "width" => 10, "height" => 10 }],
      "edges" => [{ "id" => "e", "sources" => ["a"], "targets" => ["a"],
                    "labels" => [{ "id" => "el" }] }],
    }
    edge = Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["a"])
    edge.labels = [sized_label(id: "el")]
    result = Elkrb::Graph::Graph.new(id: "root")
    result.children = [Elkrb::Graph::Node.new(id: "a", width: 10.0,
                                              height: 10.0)]
    result.edges = [edge]

    expect(result).not_to omit_size_for_unsized_input(input_hash)
  end

  # An id-less label cannot be matched by id, so it is matched by position
  # within the id-less subset. Nothing covered that subset at all.
  it "flags an unsized id-less label that gained a size" do
    input_hash = {
      "id" => "root",
      "children" => [{ "id" => "a", "width" => 10, "height" => 10,
                       "labels" => [{ "text" => "hi" }] }],
      "edges" => [],
    }
    node = Elkrb::Graph::Node.new(id: "a", width: 10.0, height: 10.0)
    node.labels = [sized_label]
    result = Elkrb::Graph::Graph.new(id: "root")
    result.children = [node]
    result.edges = []

    expect(result).not_to omit_size_for_unsized_input(input_hash)
  end

  # Positional matching is only sound when both sides have the same number
  # of id-less labels. With the count check gone, a result that dropped one
  # gets compared against the wrong label and reports nothing.
  it "flags a differing number of id-less labels" do
    input_hash = {
      "id" => "root",
      "children" => [{ "id" => "a", "width" => 10, "height" => 10,
                       "labels" => [{ "text" => "one" },
                                    { "text" => "two" }] }],
      "edges" => [],
    }
    node = Elkrb::Graph::Node.new(id: "a", width: 10.0, height: 10.0)
    node.labels = [Elkrb::Graph::Label.new(text: "one")]
    result = Elkrb::Graph::Graph.new(id: "root")
    result.children = [node]
    result.edges = []

    expect(result).not_to omit_size_for_unsized_input(input_hash)
  end
end
