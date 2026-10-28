# frozen_string_literal: true

# Builds layered placement inputs from plain ids so a spec states the
# layers, the heights and the edges and nothing else.
module BkPlacement
  Layered = Elkrb::Layout::Algorithms::Layered

  # @param layers [Array<Array<String>>] node ids per layer, top to bottom;
  #   an id starting with "d" is a dummy of the edge named by `dummies`
  # @param heights [Hash{String=>Numeric}] node heights (default 10)
  # @param edges [Array<Array(String, String)>] source and target ids
  # @param dummies [Hash{String=>Array(Integer, Integer)}] dummy id to
  #   [index of the long edge in `edges`, layer index]
  # @return [Array(Layered::BkNodePlacer, Layered::PortOrder)]
  def bk_placer(spacing: 10.0, **layout)
    items, port_order = bk_inputs(**layout)
    placer = Layered::BkNodePlacer.new(
      items, port_order,
      spacing: ->(_first, _second) { spacing },
      size_of: ->(item) { item.respond_to?(:dummy?) ? 1.0 : item.height },
      port_size_of: ->(_port) { 0 }
    )
    [placer, port_order]
  end

  def bk_inputs(layers:, edges:, heights: {}, dummies: {})
    nodes = layers.flatten.reject { |id| dummies.key?(id) }.to_h do |id|
      [id, bk_node(id, heights.fetch(id, 10))]
    end
    graph = bk_graph(nodes, edges)
    items = bk_layers(layers, nodes, dummies, graph)
    [items, Layered::PortOrder.new(items, Elkrb::Layout::NodeIndex.build(graph))]
  end

  def bk_node(id, height)
    Elkrb::Graph::Node.new(id: id, width: 10, height: height)
  end

  def bk_graph(nodes, edges)
    Elkrb::Graph::Graph.new(
      id: "root", children: nodes.values,
      edges: edges.each_with_index.map do |(source, target), index|
        Elkrb::Graph::Edge.new(
          id: "e#{index}", sources: [source], targets: [target],
        )
      end
    )
  end

  def bk_layers(layers, nodes, dummies, graph)
    layers.map do |layer|
      layer.map do |id|
        next nodes.fetch(id) unless dummies.key?(id)

        order, layer_index = dummies.fetch(id)
        Layered::DummySlot.new(
          edge: graph.edges[order], layer_index: layer_index, edge_order: order,
        )
      end
    end
  end
end

RSpec.configure { |config| config.include BkPlacement }
