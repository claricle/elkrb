# spec/support/invariants/omit_size_for_unsized_input.rb
# frozen_string_literal: true

require_relative "../invariants"

RSpec::Matchers.define :omit_size_for_unsized_input do |input_hash|
  match do |graph|
    @violations = []
    check_level(input_hash, graph)
    @violations.empty?
  end

  failure_message { @violations.join("\n") }

  # Same parallel-tree-walk reasoning as `preserve_ids_and_endpoints`: a
  # single flat `graph.all_nodes.to_h { |n| [n.id, n] }` index (the
  # original design here) crashes when the ROOT's own `children`
  # deserialized to `nil` (`Graph#all_nodes` calls bare `@children.each`
  # with no guard, unlike `Node#all_nodes` one level down) and silently
  # conflates same-id nodes at different hierarchy levels (ids are only
  # unique within a level, per `NodeIndex.build`'s contract) — walking
  # both trees together avoids both.
  define_method(:check_level) do |input_level, actual_owner|
    check_child_levels(input_level["children"] || [], actual_owner.children)
    check_edge_labels(input_level["edges"] || [], actual_owner.edges)
  end

  define_method(:index_by_id) do |items|
    (items || []).to_h { |item| [item.id, item] }
  end

  define_method(:check_child_levels) do |input_children, actual_children|
    actual_by_id = index_by_id(actual_children)
    input_children.each do |input_child|
      actual_child = actual_by_id[input_child["id"]]
      unless actual_child
        @violations << "#{input_child['id']}: missing from actual result"
        next
      end

      check_dimensions(input_child, actual_child)
      check_labels(input_child["labels"], actual_child.labels,
                   input_child["id"])
      check_ports(input_child, actual_child)
      check_level(input_child, actual_child)
    end
  end

  define_method(:check_edge_labels) do |input_edges, actual_edges|
    actual_by_id = index_by_id(actual_edges)
    input_edges.each do |input_edge|
      actual_edge = actual_by_id[input_edge["id"]]
      # a missing edge is preserve_ids_and_endpoints's violation, not this
      # matcher's
      next unless actual_edge

      check_labels(input_edge["labels"], actual_edge.labels, input_edge["id"])
    end
  end

  define_method(:check_ports) do |input_node, actual_node|
    actual_ports_by_id = index_by_id(actual_node.ports)
    (input_node["ports"] || []).each do |input_port|
      actual_port = actual_ports_by_id[input_port["id"]]
      unless actual_port
        @violations << "#{input_port['id']}: missing from actual result"
        next
      end

      check_dimensions(input_port, actual_port)
      check_labels(input_port["labels"], actual_port.labels, input_port["id"])
    end
  end

  # A "children" KEY present (even `[]`) marks a declared compound —
  # exempt per Decision 5, a compound always gets a computed size. `[]` is
  # truthy in Ruby, so a plain truthiness check on `input_node["children"]`
  # already treats an empty array as present the same way `key?` does —
  # the one case they actually differ on is an explicit `"children": null`
  # in the input, which `key?` treats as a declared (if degenerate)
  # compound and a truthiness check would not. `key?` is used here for
  # that literal, if rare, distinction, not because truthiness mishandles
  # `[]` (it doesn't). Ports have no such exemption (a port never has
  # `children`), so this same check applies to them unconditionally.
  define_method(:check_dimensions) do |input_owner, actual_owner|
    return if input_owner.key?("children")
    # was sized
    return if input_owner.key?("width") || input_owner.key?("height")

    if actual_owner.width || actual_owner.height
      @violations << "#{input_owner['id']} gained a size " \
                     "(#{actual_owner.width}x#{actual_owner.height})"
    end
  end

  # Shared by node-owned, port-owned, and edge-owned labels — a label
  # carries no compound exemption of its own. Named (has an "id") and
  # id-less labels are matched separately: named by id, id-less
  # positionally WITHIN THE ID-LESS SUBSET of each side — not by their
  # index in the combined array, which would misalign as soon as a named
  # and an id-less label sit on the same owner (an earlier version of
  # this method did exactly that).
  define_method(:check_labels) do |input_labels, actual_labels, owner_id|
    input_named, input_unnamed = (input_labels || []).partition { |l| l["id"] }
    actual_named, actual_unnamed = (actual_labels || []).partition(&:id)
    check_named_labels(input_named, index_by_id(actual_named), owner_id)
    check_unnamed_labels(input_unnamed, actual_unnamed, owner_id)
  end

  define_method(:check_named_labels) do |input_named, actual_by_id, owner_id|
    input_named.each do |input_label|
      path = "#{owner_id}/labels/#{input_label['id']}"
      actual_label = actual_by_id[input_label["id"]]
      unless actual_label
        @violations << "#{path}: missing from actual result"
        next
      end
      check_label_size(input_label, actual_label, path)
    end
  end

  define_method(:check_unnamed_labels) do |input_labels, actual_labels,
                                           owner_id|
    unless input_labels.size == actual_labels.size
      @violations << "#{owner_id}: expected #{input_labels.size} " \
                     "id-less label(s), got #{actual_labels.size}"
      return
    end

    input_labels.each_with_index do |input_label, i|
      check_label_size(input_label, actual_labels[i],
                       "#{owner_id}/labels[#{i}]")
    end
  end

  define_method(:check_label_size) do |input_label, actual_label, path|
    return if input_label.key?("width") || input_label.key?("height")

    if actual_label.width || actual_label.height
      @violations << "#{path} gained a size " \
                     "(#{actual_label.width}x#{actual_label.height})"
    end
  end
end

INVARIANTS << :omit_size_for_unsized_input
