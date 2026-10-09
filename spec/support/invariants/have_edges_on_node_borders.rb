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
    return unless border_checked_edge?(edge, owner)

    source, target = endpoint_entries(edge, index, owner)
    [edge, source, target] if source && target
  end

  define_method(:border_checked_edge?) do |edge, owner|
    edge.sections&.any? && !port_edge?(edge, owner)
  end

  define_method(:endpoint_entries) do |edge, index, owner|
    deep_index = Elkrb::Layout::NodeIndex.build_deep(owner)
    [edge.sources&.first, edge.targets&.first].map do |id|
      endpoint_entry(index, deep_index, id)
    end
  end

  define_method(:endpoint_entry) do |index, deep_index, id|
    node = index.node(id)
    return [node, Elkrb::Geometry::Point.new] if node

    matches = deep_index[id]
    matches.first if matches&.one?
  end

  define_method(:port_edge?) do |edge, owner|
    ((edge.sources || []) + (edge.targets || [])).any? do |id|
      endpoint_kind(owner, id) == :port
    end
  end

  define_method(:check_edge_sections) do |context, path|
    edge, source, target = context
    edge.sections.each_with_index do |section, index|
      section_path = "#{path}/edges/#{edge.id}/sections[#{index}]"
      check_border(section.start_point, source, "#{section_path}/start")
      check_border(section.end_point, target, "#{section_path}/end")
    end
  end

  # Mirror NodeIndex's level-scoped resolution order: an id owned directly
  # by this level wins over any same-named descendant.
  define_method(:endpoint_kind) do |owner, id|
    children = owner.children || []
    owned_endpoint_kind(children, id) || descendant_endpoint_kind(children, id)
  end

  define_method(:owned_endpoint_kind) do |nodes, id|
    nodes.each do |node|
      kind = object_endpoint_kind(node, id)
      return kind if kind
    end
    nil
  end

  define_method(:object_endpoint_kind) do |node, id|
    return :node if node.id == id

    :port if (node.ports || []).any? { |port| port.id == id }
  end

  define_method(:descendant_endpoint_kind) do |nodes, id|
    nodes.each do |node|
      (node.children || []).each do |child|
        kind = object_endpoint_kind(child, id) ||
          descendant_endpoint_kind([child], id)
        return kind if kind
      end
    end
    nil
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
