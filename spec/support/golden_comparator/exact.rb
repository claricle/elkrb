# spec/support/golden_comparator/exact.rb
# frozen_string_literal: true

require_relative "shared"

# The `:exact` tier: every compared number within 1e-6, recursively over the
# whole tree. Split out of golden_comparator.rb, which had grown to 1161
# lines — this file holds only what belongs to `:exact` alone; the
# id-matching and edge-endpoint primitives it shares with `:structural` stay
# in shared.rb rather than being duplicated here.
module GoldenComparator
  module_function

  # Exact-tier geometry for anything that is not the root: strict x/y,
  # lenient width/height.
  def diff_exact_geometry(expected, actual, path)
    diff_exact_position(expected, actual, path) +
      diff_own_numeric(expected, actual, path, SIZE_FIELDS)
  end

  def diff_exact_position(expected, actual, path)
    POSITION_FIELDS.flat_map do |key|
      e, e_error = strict_numeric(expected, key, path, "expected")
      a, a_error = strict_numeric(actual, key, path, "actual")
      next [e_error, a_error].compact if e_error || a_error

      (e - a).abs > 1e-6 ? ["#{path}/#{key}: expected #{e}, got #{a}"] : []
    end
  end

  # NaN never equals anything under IEEE 754 comparison — `(NaN - 5).abs >
  # 1e-6` is false, which would silently treat a NaN actual value as a
  # match. Flagged explicitly instead of falling through the tolerance
  # check.
  def diff_own_numeric(expected, actual, path, keys)
    keys.filter_map do |key|
      e = numeric_or_zero(expected, key)
      a = numeric_or_zero(actual, key)
      unless e.finite?
        next "#{path}/#{key}: expected is non-finite (#{expected[key].inspect})"
      end
      unless a.finite?
        next "#{path}/#{key}: actual is non-finite (#{actual[key].inspect})"
      end

      "#{path}/#{key}: expected #{e}, got #{a}" if (e - a).abs > 1e-6
    end
  end

  # Root entry point — called once, with `expected`/`actual` as the root
  # graph Hashes. `:graph` is the root's own x/y/width/height, checked
  # once here; every other category is checked at every visited level by
  # `diff_owner_fields` — traversal into `children` (`diff_children_tree`)
  # is UNCONDITIONAL, independent of which fields are selected, so a
  # caller selecting only `fields: %i[sections]` still reaches a nested
  # compound's inner edges. `fields` only controls WHICH properties are
  # compared at each visited owner, never whether traversal reaches it —
  # S10's `compound_chain fields: %i[nodes graph]` and S11's later
  # sections-only promotion of the same case both depend on this.
  def diff_exact(expected, actual, fields, path = "")
    diffs = []
    if fields.include?(:graph)
      diffs.concat(diff_own_numeric(expected, actual, path,
                                    RECT_FIELDS))
      diffs.concat(diff_root_id(expected, actual))
    end
    diffs.concat(diff_owner_fields(expected, actual, fields, path))
    diffs.concat(diff_children_tree(expected, actual, fields, path))
    diffs
  end

  # `:sections`, `:labels`, `:ports` are independent selectors, not a
  # traversal gate: `:labels` alone must still reach edge-owned and
  # port-owned labels (so it descends into `edges`/`ports` on its own,
  # not only when `:sections`/`:ports` also happen to be selected), and
  # `:ports` alone must NOT drag in port labels unless `:labels` is also
  # selected — each `diff_edges`/`diff_ports` call below receives `fields`
  # and makes its own internal per-category decision.
  def diff_owner_fields(expected_owner, actual_owner, fields, path)
    diffs = []
    if fields.include?(:sections) || fields.include?(:labels)
      diffs.concat(diff_edges(expected_owner, actual_owner, fields, path))
    end
    if fields.include?(:labels)
      diffs.concat(diff_labels(expected_owner, actual_owner,
                               path))
    end
    if fields.include?(:ports) || fields.include?(:labels)
      diffs.concat(diff_ports(expected_owner, actual_owner, path, fields))
    end
    diffs
  end

  def diff_children_tree(expected, actual, fields, path)
    diff_by_id(expected["children"], actual["children"],
               "#{path}/children") do |e_node, a_node, node_path|
      diffs = if fields.include?(:nodes)
                diff_exact_geometry(e_node, a_node,
                                    node_path)
              else
                []
              end
      diffs.concat(diff_owner_fields(e_node, a_node, fields, node_path))
      diffs.concat(diff_children_tree(e_node, a_node, fields, node_path))
      diffs
    end
  end

  def diff_labels(expected_owner, actual_owner, path)
    diff_by_id(expected_owner["labels"], actual_owner["labels"],
               "#{path}/labels") do |e, a, label_path|
      diff_exact_geometry(e, a, label_path) + diff_label_text(e, a, label_path)
    end
  end

  # Geometry alone lets a layout regression that corrupts label CONTENT
  # (wrong text, truncation, a swapped label) through the exact tier
  # unnoticed as long as position/size stay put — measured: changing an
  # otherwise-identical label's text returned no differences before this.
  def diff_label_text(expected, actual, path)
    return [] if expected["text"] == actual["text"]

    ["#{path}/text: expected #{expected['text'].inspect}, got " \
     "#{actual['text'].inspect}"]
  end

  # Called whenever `:ports` OR `:labels` is selected (see
  # `diff_owner_fields`) — port geometry/side/index/offset stay behind
  # `:ports` internally so a `:labels`-only caller reaching this method
  # (to get at port-owned labels) doesn't also pull in port position deltas
  # it never asked for.
  def diff_ports(expected_owner, actual_owner, path, fields)
    diff_by_id(expected_owner["ports"], actual_owner["ports"],
               "#{path}/ports") do |e, a, port_path|
      diffs = fields.include?(:labels) ? diff_labels(e, a, port_path) : []
      next diffs unless fields.include?(:ports)

      diffs.concat(diff_port_attributes(e, a, port_path))
    end
  end

  def diff_port_attributes(expected, actual, path)
    diff_exact_geometry(expected, actual, path) +
      diff_port_side(expected, actual, path) +
      diff_port_index(expected, actual, path) +
      diff_port_offset(expected, actual, path)
  end

  def diff_port_side(expected, actual, path)
    e_side = expected["side"] || "UNDEFINED"
    a_side = actual["side"] || "UNDEFINED"
    return [] if e_side == a_side

    ["#{path}/side: expected #{e_side}, got #{a_side}"]
  end

  def diff_port_index(expected, actual, path)
    return [] if expected["index"] == actual["index"]

    ["#{path}/index: expected #{expected['index']}, got #{actual['index']}"]
  end

  def diff_port_offset(expected, actual, path)
    e_offset = (expected["offset"] || 0.0).to_f
    a_offset = (actual["offset"] || 0.0).to_f
    return [] if (e_offset - a_offset).abs <= 1e-6

    ["#{path}/offset: expected #{e_offset}, got #{a_offset}"]
  end

  def diff_edges(expected_owner, actual_owner, fields, path)
    diff_by_id(expected_owner["edges"], actual_owner["edges"],
               "#{path}/edges") do |e_edge, a_edge, edge_path|
      diffs = diff_edge_endpoints(e_edge, a_edge, edge_path)
      if fields.include?(:sections)
        diffs.concat(diff_sections(e_edge, a_edge,
                                   edge_path))
      end
      if fields.include?(:labels)
        diffs.concat(diff_labels(e_edge, a_edge,
                                 edge_path))
      end
      diffs
    end
  end

  # Sections are matched POSITIONALLY within an edge (by index), never by
  # raw id: elkjs writes "e1_s0", elkrb writes "e1_section_0" today (S11
  # renames elkrb's ids to the elkjs shape) — id-based matching (the
  # earlier `diff_by_id`-based version of this method) means no section
  # ever has a common id on both sides, so the geometry comparison below
  # would silently never run. The comparator must not depend on elkrb
  # eventually adopting elkjs's id convention. Purely geometric (points,
  # bend points) -- which shape a section connects to is
  # `diff_edge_endpoints`'s job (golden_comparator/shared.rb), not this
  # method's.
  def diff_sections(expected_edge, actual_edge, path)
    expected_sections = expected_edge["sections"] || []
    actual_sections = actual_edge["sections"] || []

    if expected_sections.size != actual_sections.size
      return ["#{path}/sections: expected #{expected_sections.size}, " \
              "got #{actual_sections.size}"]
    end

    expected_sections.each_with_index.flat_map do |e_sec, i|
      diff_section_geometry(e_sec, actual_sections[i], "#{path}/sections[#{i}]")
    end
  end

  def diff_section_geometry(expected_section, actual_section, sec_path)
    diffs = diff_point(expected_section["startPoint"],
                       actual_section["startPoint"], "#{sec_path}/startPoint")
    diffs.concat(diff_point(expected_section["endPoint"],
                            actual_section["endPoint"], "#{sec_path}/endPoint"))
    diffs.concat(diff_bend_points(expected_section["bendPoints"],
                                  actual_section["bendPoints"],
                                  "#{sec_path}/bendPoints"))
  end

  def diff_bend_points(expected_points, actual_points, path)
    expected_points ||= []
    actual_points ||= []
    if expected_points.size != actual_points.size
      return ["#{path}: expected #{expected_points.size} bend points, " \
              "got #{actual_points.size}"]
    end

    expected_points.each_with_index.flat_map do |point, i|
      diff_point(point, actual_points[i], "#{path}[#{i}]")
    end
  end

  def diff_point(expected_point, actual_point, path)
    return ["#{path}: missing"] unless expected_point && actual_point

    diff_exact_position(expected_point, actual_point, path)
  end
end
