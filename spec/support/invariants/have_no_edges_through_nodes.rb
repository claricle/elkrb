# frozen_string_literal: true

require_relative "../invariants"

RSpec::Matchers.define :have_no_edges_through_nodes do
  match do |graph|
    @violations = []
    check_level(graph, graph.id || "root")
    @violations.empty?
  end

  failure_message { @violations.join("\n") }

  define_method(:check_level) do |owner, path|
    if layered?(owner)
      index = Elkrb::Layout::NodeIndex.build(owner)
      index.edges.each { |edge| check_edge(edge, owner, index, path) }
    end
    (owner.children || []).select(&:hierarchical?).each do |child|
      check_level(child, "#{path}/#{child.id}")
    end
  end

  define_method(:layered?) do |owner|
    Elkrb::Options::Resolver.new.get("elk.algorithm", owner) == "layered"
  end

  define_method(:check_edge) do |edge, owner, index, path|
    candidates = non_endpoint_nodes(edge, owner, index)
    edge.sections.to_a.each_with_index do |section, section_index|
      check_section(section, candidates,
                    "#{path}/edges/#{edge.id}/sections[#{section_index}]")
    end
  end

  define_method(:non_endpoint_nodes) do |edge, owner, index|
    endpoint_ids = endpoint_owner_ids(edge, index)
    (owner.children || []).select do |node|
      InvariantGeometry.area?(node) && !endpoint_ids.include?(node.id)
    end
  end

  define_method(:endpoint_owner_ids) do |edge, index|
    [edge.sources&.first, edge.targets&.first].filter_map do |id|
      index.owner(id)&.id
    end
  end

  define_method(:check_section) do |section, nodes, path|
    points = [section.start_point, *section.bend_points.to_a,
              section.end_point].compact
    points.each_cons(2) do |from, to|
      nodes.each do |node|
        next unless segment_enters_node?(from, to, node)

        @violations << "#{path} passes through node #{node.id}"
      end
    end
  end

  define_method(:segment_enters_node?) do |from, to, node|
    left, top, right, bottom = interior_bounds(node)
    x_interval = coordinate_interval(from.x, to.x, left, right)
    y_interval = coordinate_interval(from.y, to.y, top, bottom)
    intervals_overlap?(x_interval, y_interval)
  end

  define_method(:interior_bounds) do |node|
    x, y, width, height = InvariantGeometry.box(node)
    epsilon = 1e-9
    [x + epsilon, y + epsilon, x + width - epsilon, y + height - epsilon]
  end

  define_method(:coordinate_interval) do |from, to, lower, upper|
    delta = to - from
    return [0.0, 1.0] if delta.zero? && from.between?(lower, upper)
    return if delta.zero?

    first, last = [(lower - from) / delta, (upper - from) / delta].minmax
    [[first, 0.0].max, [last, 1.0].min]
  end

  define_method(:intervals_overlap?) do |first, second|
    return false unless first && second

    [first[0], second[0]].max <= [first[1], second[1]].min
  end
end

INVARIANTS << :have_no_edges_through_nodes
