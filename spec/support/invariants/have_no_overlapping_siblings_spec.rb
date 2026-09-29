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

  # Zero AREA, not just zero width: a node with a real width and no
  # height is a segment, and a segment has no interior either. Both rows
  # sit strictly inside the sibling, so every one of the four coordinate
  # comparisons holds and only the area test can reject them.
  {
    "an unsized node (nil width and height)" => { width: nil, height: nil },
    "an explicitly 0x0 node" => { width: 0.0, height: 0.0 },
    "a zero-height node with a real width" => { width: 6.0, height: 0.0 },
  }.each do |label, size|
    it "passes #{label} sitting inside a sized sibling" do
      graph = Elkrb::Graph::Graph.new(id: "root")
      graph.children = [
        Elkrb::Graph::Node.new(id: "box", x: 0.0, y: 0.0, width: 10.0,
                               height: 10.0),
        Elkrb::Graph::Node.new(id: "point", x: 2.0, y: 5.0, **size),
      ]

      expect(graph).to have_no_overlapping_siblings
    end
  end

  # Overlap needs BOTH axes. Without the Y half of the predicate these two --
  # same column, stacked with a gap -- get reported as overlapping, which is
  # what a bounding-box test degrading to a one-axis test looks like.
  it "passes siblings that share an x range but are separated in y" do
    graph = Elkrb::Graph::Graph.new
    graph.children = [
      Elkrb::Graph::Node.new(id: "a", x: 0.0, y: 0.0,
                             width: 30.0, height: 10.0),
      Elkrb::Graph::Node.new(id: "b", x: 0.0, y: 50.0,
                             width: 30.0, height: 10.0),
    ]
    graph.edges = []

    expect(graph).to have_no_overlapping_siblings
  end
end
