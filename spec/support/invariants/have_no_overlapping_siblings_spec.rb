# frozen_string_literal: true

require_relative "have_no_overlapping_siblings"

RSpec.describe "have_no_overlapping_siblings" do
  it "passes when sibling rectangles do not overlap" do
    graph = Elkrb::Graph::Graph.new(id: "root")
    graph.children = [
      Elkrb::Graph::Node.new(id: "a", x: 0.0, y: 0.0, width: 10.0,
                             height: 10.0),
      Elkrb::Graph::Node.new(id: "b", x: 20.0, y: 0.0, width: 10.0,
                             height: 10.0),
    ]

    expect(graph).to have_no_overlapping_siblings
  end

  it "fails when sibling rectangles overlap" do
    graph = Elkrb::Graph::Graph.new(id: "root")
    graph.children = [
      Elkrb::Graph::Node.new(id: "a", x: 0.0, y: 0.0, width: 10.0,
                             height: 10.0),
      Elkrb::Graph::Node.new(id: "b", x: 5.0, y: 5.0, width: 10.0,
                             height: 10.0),
    ]

    expect(graph).not_to have_no_overlapping_siblings
  end
  # The recursion had no example: removing `siblings.each { check_level }`
  # left both existing ones green, so overlaps below the root went unseen.
  it "finds an overlap between grandchildren, not just top-level siblings" do
    parent = Elkrb::Graph::Node.new(id: "p", x: 0.0, y: 0.0, width: 100.0,
                                    height: 100.0)
    parent.children = [
      Elkrb::Graph::Node.new(id: "a", x: 0.0, y: 0.0, width: 30.0,
                             height: 30.0),
      Elkrb::Graph::Node.new(id: "b", x: 10.0, y: 10.0, width: 30.0,
                             height: 30.0),
    ]
    graph = Elkrb::Graph::Graph.new(id: "root", width: 100.0, height: 100.0)
    graph.children = [parent]

    expect(graph).not_to have_no_overlapping_siblings
  end
end
