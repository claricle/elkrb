# frozen_string_literal: true

require_relative "contain_children_within_bounds"

RSpec.describe "contain_children_within_bounds" do
  it "passes when every child fits inside its parent" do
    # x/y/width/height at every level, including the root's own, since the
    # matcher checks containment at every level it visits (root's own
    # children against the root's bounds, then recurses) — an unsized
    # root would otherwise itself report `p` as escaping.
    parent = Elkrb::Graph::Node.new(id: "p", x: 0.0, y: 0.0, width: 100.0,
                                    height: 100.0)
    parent.children = [Elkrb::Graph::Node.new(id: "c", x: 10.0, y: 10.0,
                                              width: 30.0, height: 30.0)]
    graph = Elkrb::Graph::Graph.new(id: "root", width: 100.0, height: 100.0)
    graph.children = [parent]

    expect(graph).to contain_children_within_bounds
  end

  # ONE case per boundary. The single case this replaces put the child at
  # (10,10) sized 30x30 in a 20x20 parent, which escapes right AND bottom at
  # once -- so deleting either predicate on its own left the spec green.
  {
    "left" => { x: -5.0, y: 5.0 },
    "top" => { x: 5.0, y: -5.0 },
    "right" => { x: 18.0, y: 5.0 },
    "bottom" => { x: 5.0, y: 18.0 },
  }.each do |edge, position|
    it "fails when a child escapes past its parent's #{edge} edge" do
      parent = Elkrb::Graph::Node.new(id: "p", x: 0.0, y: 0.0, width: 20.0,
                                      height: 20.0)
      parent.children = [
        Elkrb::Graph::Node.new(id: "c", x: position[:x], y: position[:y],
                               width: 5.0, height: 5.0),
      ]
      graph = Elkrb::Graph::Graph.new(id: "root", width: 20.0, height: 20.0)
      graph.children = [parent]

      expect(graph).not_to contain_children_within_bounds
    end
  end
end
