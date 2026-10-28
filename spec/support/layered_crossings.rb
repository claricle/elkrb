# frozen_string_literal: true

module LayeredCrossings
  module_function

  def count(graph)
    owners = endpoint_owners(graph.children || [])
    segments = (graph.edges || []).filter_map do |edge|
      segment_for(edge, owners)
    end

    segments.combination(2).count { |first, second| crossing?(first, second) }
  end

  def endpoint_owners(nodes)
    nodes.each_with_object({}) do |node, owners|
      owners[node.id] = node
      (node.ports || []).each { |port| owners[port.id] = node }
    end
  end

  def segment_for(edge, owners)
    source = endpoint_node(edge.sources, owners)
    target = endpoint_node(edge.targets, owners)
    return unless source && target && source.x != target.x

    source.x < target.x ? [source, target] : [target, source]
  end

  def endpoint_node(endpoints, owners)
    owners[(endpoints || []).first]
  end

  def crossing?(first, second)
    return false unless same_layer_pair?(first, second)

    cross_delta(first, second, 0) * cross_delta(first, second, 1) < 0
  end

  def same_layer_pair?(first, second)
    first.map(&:x) == second.map(&:x)
  end

  def cross_delta(first, second, endpoint)
    center_y(first[endpoint]) - center_y(second[endpoint])
  end

  def center_y(node)
    node.y + (node.height / 2.0)
  end
end
