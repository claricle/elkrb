# frozen_string_literal: true

# Reads where a laid-out graph put its children.
module GraphPositions
  # [id, x, y] per child of a Graph.
  def child_positions(graph)
    graph.children.map { |node| [node.id, node.x, node.y] }
  end

  # Lays out a fresh Graph built from `graph_hash`, with `call_options` as the
  # layout call's options, and returns its child positions.
  def laid_out_positions(graph_hash, call_options = {})
    graph = Elkrb::Graph::Graph.from_hash(Marshal.load(Marshal.dump(graph_hash)))
    child_positions(Elkrb.layout(graph, call_options))
  end
end
