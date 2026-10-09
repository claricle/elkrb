# frozen_string_literal: true

# Runs CrossingMinimizer over layers given as plain ids and reports the port
# order it left behind.
module MinimizerPorts
  # @param ids [Array<String>] node ids in input order
  # @param edges [Array<Array(String, String)>] source and target ids
  # @param layers [Array<Array<String>>] node ids per layer, in start order
  # @param options [Hash] layout options
  # @return [Array(Array<Array<String>>, Elkrb::Layout::Algorithms::Layered::PortOrder)]
  #   the layers after minimizing, and the port order
  def minimized_ports(ids:, edges:, layers:, options: {})
    nodes = ids.to_h { |id| [id, Elkrb::Graph::Node.new(id: id)] }
    graph = minimizer_graph(nodes, edges)
    minimizer = build_minimizer(graph, layers.map do |layer|
      layer.map { |id| nodes.fetch(id) }
    end, options)
    [minimizer.minimize.map { |layer| layer.map(&:id) }, minimizer.port_order]
  end

  def build_minimizer(graph, layers, options)
    Elkrb::Layout::Algorithms::Layered::CrossingMinimizer.new(
      graph, layers, Elkrb::Layout::NodeIndex.build(graph),
      Elkrb::Options::Resolver.new(options)
    )
  end

  def minimizer_graph(nodes, edges)
    Elkrb::Graph::Graph.new(
      id: "root",
      children: nodes.values,
      edges: edges.map do |source, target|
        Elkrb::Graph::Edge.new(
          id: "#{source}-#{target}", sources: [source], targets: [target],
        )
      end,
    )
  end

  # Where the edges on one side of a node lead, top to bottom.
  def port_targets(order, id, side)
    order.visual(id, side).map { |port| port.others.map(&:item_id) }
  end
end

RSpec.configure { |config| config.include MinimizerPorts }
