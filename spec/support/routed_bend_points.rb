# frozen_string_literal: true

# Routes the one edge of a two-node graph and reports where it bends.
module RoutedBendPoints
  # [x, y] per bend point of the routed edge. `layout_options` go on the
  # graph; `style` is passed to route_edges (nil lets the router read it).
  def routed_bend_points(router, layout_options, style = nil)
    graph = Elkrb::Graph::Graph.new(
      id: "g1",
      layout_options: layout_options,
      children: [
        Elkrb::Graph::Node.new(id: "n1", x: 0.0, y: 0.0,
                               width: 50.0, height: 50.0),
        Elkrb::Graph::Node.new(id: "n2", x: 200.0, y: 120.0,
                               width: 50.0, height: 50.0),
      ],
      edges: [
        Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"], targets: ["n2"]),
      ],
    )
    router.route_edges(graph, nil, style)
    graph.edges.first.sections.first.bend_points.to_a.map { |b| [b.x, b.y] }
  end
end
