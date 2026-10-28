# frozen_string_literal: true

# Graphs and geometry checks for the polyomino specs.
module PolyominoFixtures
  # nodes: [[id, width, height, x, y], ...]; edges: [[source, target], ...].
  # Components keep the positions given (disco.componentAlgorithm=fixed), so
  # edge geometry is known to the packer exactly as it was written.
  def disco_graph(nodes, edges: [], options: {})
    Elkrb::Graph::Graph.new(
      layout_options: { "disco.componentAlgorithm" => "fixed" }.merge(options),
      children: nodes.map do |id, width, height, x, y|
        Elkrb::Graph::Node.new(id: id, width: width, height: height,
                               x: x || 0.0, y: y || 0.0)
      end,
      edges: edges.each_with_index.map do |(source, target), i|
        Elkrb::Graph::Edge.new(id: "e#{i}", sources: [source],
                               targets: [target])
      end,
    )
  end

  # { id => [x, y] } measured from the top-left of the nodes' bounding box,
  # which is how elk positions compare: padding is not part of the packing.
  def relative_positions(graph)
    min_x = graph.children.map(&:x).min
    min_y = graph.children.map(&:y).min
    graph.children.to_h { |n| [n.id, [n.x - min_x, n.y - min_y]] }
  end

  # Pairs of nodes that overlap and belong to different components. Nodes of
  # one component keep the arrangement they came with, overlapping or not.
  def overlapping_across_components(graph)
    component = component_numbers(graph)
    graph.children.combination(2).select do |first, second|
      component[first.id] != component[second.id] &&
        boxes_overlap?(first, second)
    end.map { |pair| pair.map(&:id) }
  end

  # { node id => number of its component }, components joined by edges.
  def component_numbers(graph)
    groups = graph.children.map { |node| [node.id] }
    graph.edges.each do |edge|
      groups = joined(groups, [edge.sources.first, edge.targets.first])
    end
    numbered(groups)
  end

  def numbered(groups)
    groups.each_with_index.flat_map { |ids, i| ids.map { |id| [id, i] } }.to_h
  end

  def joined(groups, ends)
    touching, rest = groups.partition { |group| group.intersect?(ends) }
    rest + [touching.flatten]
  end

  def boxes_overlap?(first, second)
    spans_overlap?(first.x, first.width, second.x, second.width) &&
      spans_overlap?(first.y, first.height, second.y, second.height)
  end

  def spans_overlap?(start, size, other_start, other_size)
    start < other_start + other_size && other_start < start + size
  end

  def layout_disco(graph)
    Elkrb::Layout::Algorithms::Disco.new.layout(graph)
    graph
  end
end
