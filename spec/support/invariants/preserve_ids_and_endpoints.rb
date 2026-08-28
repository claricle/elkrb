# spec/support/invariants/preserve_ids_and_endpoints.rb
# frozen_string_literal: true

require_relative "../invariants"

RSpec::Matchers.define :preserve_ids_and_endpoints do |input_hash|
  match do |graph|
    @violations = []
    check_level(input_hash, graph)
    @violations.empty?
  end

  failure_message { @violations.join("\n") }

  # Walks the input hash and the actual graph IN PARALLEL, matching a
  # level's children/edges by id WITHIN that level only — never a single
  # flat id-keyed index built from `Graph#all_nodes`/`#all_edges`, for two
  # confirmed reasons: (1) `Graph#all_edges` (lib/elkrb/graph/graph.rb)
  # only reaches the root's own edges plus each direct child's own edges —
  # `Node` has no `all_edges` of its own, so a genuinely preserved edge two
  # or more levels deep would read as "missing"; (2) `NodeIndex.build`'s
  # own contract (S7 card) is that node/port ids are unique only WITHIN a
  # hierarchy level — "distinct levels may reuse ids" — so a global flat
  # index conflates two different same-named nodes at different levels,
  # letting a genuinely vanished nested node silently pass as long as a
  # same-id node survives elsewhere in the tree. This walk also avoids
  # `Graph#all_nodes` at the root: that implementation calls bare
  # `@children.each`, so it crashes (`NoMethodError`) whenever the ROOT's
  # own `children` deserialized to `nil` (e.g. the `no_children_key`
  # corpus shape) — `Node#all_nodes` guards this correctly one level down
  # (`return nodes unless @children`), the bug is specific to `Graph`'s
  # own implementation. The `|| []` on both collections below is nil-safe
  # at every level regardless.
  define_method(:check_level) do |input_level, actual_owner|
    actual_children = actual_owner.children || []
    actual_edges = actual_owner.edges || []
    check_duplicates(actual_owner.id, actual_children, actual_edges)
    check_children(input_level["children"] || [], actual_children)
    check_edges(input_level["edges"] || [], actual_edges)
  end

  define_method(:check_duplicates) do |owner_id, actual_children, actual_edges|
    @violations.concat(duplicate_id_violations(actual_children, "node",
                                               owner_id))
    @violations.concat(duplicate_id_violations(actual_edges, "edge",
                                               owner_id))
  end

  define_method(:check_children) do |input_children, actual_children|
    actual_by_id = actual_children.to_h { |n| [n.id, n] }
    input_children.each do |input_child|
      actual_child = actual_by_id[input_child["id"]]
      unless actual_child
        @violations << "missing node #{input_child['id']}"
        next
      end
      check_level(input_child, actual_child)
    end
  end

  define_method(:check_edges) do |input_edges, actual_edges|
    actual_by_id = actual_edges.to_h { |e| [e.id, e] }
    input_edges.each do |input_edge|
      actual_edge = actual_by_id[input_edge["id"]]
      unless actual_edge
        @violations << "missing edge #{input_edge['id']}"
        next
      end

      check_endpoints(input_edge, actual_edge)
    end
  end

  define_method(:check_endpoints) do |input_edge, actual_edge|
    input_endpoints = [input_edge["sources"], input_edge["targets"]]
    return if [actual_edge.sources, actual_edge.targets] == input_endpoints

    @violations << "#{input_edge['id']}: endpoints changed from " \
                   "#{input_edge['sources']}->#{input_edge['targets']} to " \
                   "#{actual_edge.sources}->#{actual_edge.targets}"
  end

  # `to_h` on an id-keyed collection keeps only the LAST entry for a
  # repeated id, so a result that duplicated a node or an edge passed as
  # long as its final copy still matched the input — a graph with two `a`
  # nodes and two `e1` edges was indistinguishable from a correct one.
  # Reported before either collection is indexed. The owner's id goes in
  # the message because ids are unique only within a level
  # (`NodeIndex.build`'s contract), so "duplicate a" alone would not say
  # which level it happened at.
  define_method(:duplicate_id_violations) do |items, kind, owner_id|
    items.map(&:id).tally.select { |_, count| count > 1 }.map do |id, count|
      "#{owner_id}: #{count} #{kind}s with id #{id.inspect}"
    end
  end
end

INVARIANTS << :preserve_ids_and_endpoints
