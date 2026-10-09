# frozen_string_literal: true

require_relative "../invariants"

RSpec::Matchers.define :have_edges_on_node_borders do
  match do |graph|
    @violations = []
    check_level(graph, graph.id || "root")
    @violations.empty?
  end

  failure_message { @violations.join("\n") }

  define_method(:check_level) do |owner, path|
    index = Elkrb::Layout::NodeIndex.build(owner)
    check_edges(index, owner, path)

    (owner.children || []).select(&:hierarchical?).each do |child|
      check_level(child, "#{path}/#{child.id}")
    end
  end

  define_method(:check_edges) do |index, owner, path|
    contexts = index.edges.filter_map do |edge|
      edge_context(edge, index, owner)
    end
    contexts.each { |context| check_edge_sections(context, path) }
  end

  define_method(:edge_context) do |edge, index, owner|
    return unless border_checked_edge?(edge)

    source, target = endpoint_entries(edge, index, owner)
    [edge, source, target] if source && target
  end

  define_method(:border_checked_edge?) do |edge|
    edge.sections&.any?
  end

  define_method(:endpoint_entries) do |edge, index, owner|
    deep_index = Elkrb::Layout::NodeIndex.build_deep(owner)
    [edge.sources&.first, edge.targets&.first].map do |id|
      endpoint_entry(index, deep_index, id)
    end
  end

  define_method(:endpoint_entry) do |index, deep_index, id|
    node = index.node(id)
    if node
      return endpoint_box(node, Elkrb::Geometry::Point.new, id)
    end

    matches = deep_index[id]
    return unless matches&.one?

    endpoint_box(*matches.first, id)
  end

  define_method(:endpoint_box) do |node, offset, id|
    port = node.ports&.find { |candidate| candidate.id == id }
    return [node, offset] unless port

    node_offset = Elkrb::Geometry::Point.new(
      x: offset.x + (node.x || 0.0),
      y: offset.y + (node.y || 0.0),
    )
    [port, node_offset]
  end

  define_method(:check_edge_sections) do |context, path|
    edge, source, target = context
    edge.sections.each_with_index do |section, index|
      section_path = "#{path}/edges/#{edge.id}/sections[#{index}]"
      check_border(section.start_point, source, "#{section_path}/start")
      check_border(section.end_point, target, "#{section_path}/end")
    end
  end

  define_method(:check_border) do |point, endpoint, path|
    return @violations << "#{path} is missing" unless point

    node, offset = endpoint
    return if on_border?(point, node, offset)

    @violations << "#{path} (#{point.x}, #{point.y}) is not on " \
                   "#{node.id}'s border"
  end

  define_method(:on_border?) do |point, node, offset|
    left, top, right, bottom = border_box(node, offset)
    on_vertical_border?(point, left, right, top, bottom) ||
      on_horizontal_border?(point, top, bottom, left, right)
  end

  define_method(:border_box) do |node, offset|
    x, y, width, height = InvariantGeometry.box(node)
    [x + offset.x, y + offset.y,
     x + offset.x + width, y + offset.y + height]
  end

  define_method(:on_vertical_border?) do |point, left, right, top, bottom|
    epsilon = 1e-9
    boundary?(point.x, left, right, epsilon) &&
      within?(point.y, top, bottom, epsilon)
  end

  define_method(:on_horizontal_border?) do |point, top, bottom, left, right|
    epsilon = 1e-9
    boundary?(point.y, top, bottom, epsilon) &&
      within?(point.x, left, right, epsilon)
  end

  define_method(:within?) do |coordinate, lower, upper, epsilon|
    coordinate.between?(lower - epsilon, upper + epsilon)
  end

  define_method(:boundary?) do |coordinate, lower, upper, epsilon|
    (coordinate - lower).abs <= epsilon ||
      (coordinate - upper).abs <= epsilon
  end
end

INVARIANTS << :have_edges_on_node_borders
