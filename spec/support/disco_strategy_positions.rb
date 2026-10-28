# frozen_string_literal: true

# Lays out four equal, unconnected 50x30 nodes with disco under the given
# componentCompaction.strategy and returns each node's [x, y].
module DiscoStrategyPositions
  def disco_positions_for(strategy)
    graph = Elkrb::Graph::Graph.new(
      layout_options: { "disco.componentCompaction.strategy" => strategy },
      children: Array.new(4) do |i|
        Elkrb::Graph::Node.new(id: "n#{i}", width: 50, height: 30)
      end,
      edges: [],
    )
    Elkrb::Layout::Algorithms::Disco.new.layout(graph)
    graph.children.map { |n| [n.x, n.y] }
  end
end
