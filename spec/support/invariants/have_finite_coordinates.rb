# spec/support/invariants/have_finite_coordinates.rb
# frozen_string_literal: true

require_relative "../invariants"

RSpec::Matchers.define :have_finite_coordinates do
  match do |graph|
    @offenders = []
    # root has no position of its own (see below), only a possible size
    check_dimensions(graph, "root")
    walk(graph, "root")
    @offenders.empty?
  end

  failure_message { "non-finite/missing coordinates: #{@offenders.join(', ')}" }

  # Position (x/y) is required on every NODE a layout pass has touched —
  # nil there is a bug, never a legitimate omission. The root graph is the
  # exception: it defines its own coordinate frame rather than being
  # positioned within a parent, and elkrb never assigns it an x/y today
  # (confirmed empirically: `Elkrb.layout({"id"=>"root","children"=>[…]})
  # .x` is `nil` even for an ordinary successful layout) — requiring root
  # position here would fail every single graph, not flag a real bug.
  # Dimension (width/height) may legitimately be nil per Decision 5 (an
  # unsized leaf keeps no size, and — per this same empirical check — a
  # graph with no children at all has nil width/height too); if present,
  # it must be finite and non-negative.
  define_method(:check_position) do |owner, path|
    %i[x y].each do |attr|
      value = owner.public_send(attr)
      @offenders << "#{path}.#{attr}=#{value.inspect}" unless value&.finite?
    end
  end

  define_method(:check_dimensions) do |owner, path|
    %i[width height].each do |attr|
      value = owner.public_send(attr)
      next if value.nil?

      in_range = value.finite? && value >= 0
      @offenders << "#{path}.#{attr}=#{value.inspect}" unless in_range
    end
  end

  define_method(:check_labels) do |owner, path|
    (owner.labels || []).each do |label|
      label_path = "#{path}/labels/#{label.id}"
      check_position(label, label_path)
      check_dimensions(label, label_path)
    end
  end

  define_method(:check_ports) do |node, path|
    (node.ports || []).each do |port|
      port_path = "#{path}/ports/#{port.id}"
      check_position(port, port_path)
      check_dimensions(port, port_path)
      check_labels(port, port_path)
    end
  end

  # A section's start/end point is required whenever the section itself
  # exists (a section with no start/end is malformed data, not a
  # legitimate omission — unlike the section being absent entirely, which
  # `route_edges` not running for a cross-hierarchy edge already produces
  # correctly as an empty `sections` array, never reached by this check).
  define_method(:check_point) do |point, path|
    if point.nil?
      @offenders << "#{path}=nil"
      return
    end

    finite = point.x&.finite? && point.y&.finite?
    @offenders << "#{path}=#{point.inspect}" unless finite
  end

  define_method(:check_section_points) do |section, edge_path|
    check_point(section.start_point, "#{edge_path}/start_point")
    check_point(section.end_point, "#{edge_path}/end_point")
    (section.bend_points || []).each_with_index do |point, i|
      check_point(point, "#{edge_path}/bend_points[#{i}]")
    end
  end

  define_method(:check_sections) do |owner, path|
    (owner.edges || []).each do |edge|
      edge_path = "#{path}/edges/#{edge.id}"
      (edge.sections || []).each do |section|
        check_section_points(section, edge_path)
      end
      check_labels(edge, edge_path)
    end
  end

  define_method(:walk) do |owner, path|
    check_labels(owner, path) if owner.respond_to?(:labels)
    check_ports(owner, path) if owner.respond_to?(:ports)
    check_sections(owner, path)

    (owner.children || []).each do |node|
      node_path = "#{path}/#{node.id}"
      check_position(node, node_path)
      check_dimensions(node, node_path)
      walk(node, node_path)
    end
  end
end

INVARIANTS << :have_finite_coordinates
