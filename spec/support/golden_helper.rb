# frozen_string_literal: true

require "json"

module GoldenHelper
  DEFAULT_DIR = File.join(__dir__, "..", "fixtures", "golden")

  def golden_input(name, dir: DEFAULT_DIR)
    data = JSON.parse(File.read(File.join(dir, "inputs", "#{name}.json")))
    { graph: data.fetch("graph"), options: data.fetch("options", {}) }
  end

  def golden_expected(name, dir: DEFAULT_DIR)
    JSON.parse(File.read(File.join(dir, "expected", "#{name}.json")))
  end
end

RSpec.configure { |c| c.include GoldenHelper }

module GoldenComparator
  module_function

  def error_hash?(value)
    value.is_a?(Hash) && (value.key?("error") || value.key?(:error))
  end

  def error_message(value)
    value["error"] || value[:error]
  end

  # Round-trips the model through its own `json do` mapping. A NaN/Infinity
  # coordinate (RC8: a zero-length section can produce one) makes `to_json`
  # raise `JSON::GeneratorError` deep inside lutaml — re-raised here with a
  # message naming the actual bug instead of a bare stdlib backtrace.
  def to_comparable(actual)
    return actual if actual.is_a?(Hash)

    JSON.parse(actual.to_json)
  rescue JSON::GeneratorError => e
    raise "actual layout result contains a non-finite coordinate " \
          "(NaN/Infinity), cannot compare: #{e.message}"
  end

  # Deep-compares two elkjs-shaped Hashes by id, numeric tolerance 1e-6,
  # a missing numeric field on either side reads as 0.0 (elkjs writes
  # width:0, elkrb may omit it). Returns an Array of JSON-pointer-style
  # diff strings, first 10 kept by the caller.
  RECT_FIELDS = %w[x y width height].freeze
  POINT_FIELDS = %w[x y].freeze

  def numeric_or_zero(hash, key)
    (hash[key] || 0.0).to_f
  end

  # NaN never equals anything under IEEE 754 comparison — `(NaN - 5).abs >
  # 1e-6` is false, which would silently treat a NaN actual value as a
  # match. Flagged explicitly instead of falling through the tolerance
  # check.
  def diff_own_numeric(expected, actual, path, keys)
    keys.filter_map do |key|
      e = numeric_or_zero(expected, key)
      a = numeric_or_zero(actual, key)
      next "#{path}/#{key}: actual is non-finite (#{actual[key].inspect})" unless a.finite?

      "#{path}/#{key}: expected #{e}, got #{a}" if (e - a).abs > 1e-6
    end
  end

  # Building an id => item Hash from an Array silently keeps only the LAST
  # item for a repeated id — a genuine duplicate would otherwise vanish
  # from comparison instead of being reported. Checked wherever this
  # slice indexes a collection by id (`diff_by_id` below and
  # `check_level_sections`'s own edge/child indexing). `nil` ids are
  # excluded: real elkjs output has id-less labels (confirmed — ELK does
  # not require a label id), and multiple id-less items on the same owner
  # are a legitimate shape, not a duplicate-id bug; `diff_by_id` still
  # only ever matches the LAST id-less item pair-for-pair (a known,
  # narrower limitation than duplicate-id detection, out of scope here).
  def duplicate_id_diffs(items, label)
    items.filter_map { |item| item["id"] }.tally.select { |_, count| count > 1 }.map do |id, count|
      "#{label} has #{count} items with id #{id.inspect}"
    end
  end

  # expected_items/actual_items: elkjs-shaped Arrays of Hashes with an "id"
  # — except labels, which real elkjs output leaves id-less (ELK does not
  # require a label id). Items with an id are matched BY id, symmetric:
  # reports every expected id missing from actual AND every actual id
  # absent from expected, then yields (expected_item, actual_item,
  # item_path) for every id present on both sides. Id-less items have no
  # key to match by, so they're compared separately, positionally, by
  # their order within the id-less subset of each side.
  def diff_by_id(expected_items, actual_items, path)
    expected_items ||= []
    actual_items ||= []
    expected_named, expected_unnamed = expected_items.partition { |item| item["id"] }
    actual_named, actual_unnamed = actual_items.partition { |item| item["id"] }

    diffs = duplicate_id_diffs(expected_named, "#{path}: expected")
    diffs.concat(duplicate_id_diffs(actual_named, "#{path}: actual"))

    expected_by_id = expected_named.to_h { |item| [item["id"], item] }
    actual_by_id = actual_named.to_h { |item| [item["id"], item] }

    diffs.concat((expected_by_id.keys - actual_by_id.keys).map { |id| "#{path}/#{id}: missing from actual" })
    diffs.concat((actual_by_id.keys - expected_by_id.keys).map { |id| "#{path}/#{id}: unexpected in actual" })

    (expected_by_id.keys & actual_by_id.keys).each do |id|
      diffs.concat(yield(expected_by_id[id], actual_by_id[id], "#{path}/#{id}"))
    end

    if expected_unnamed.size != actual_unnamed.size
      diffs << "#{path}: expected #{expected_unnamed.size} id-less item(s), got #{actual_unnamed.size}"
    else
      expected_unnamed.each_with_index do |item, i|
        diffs.concat(yield(item, actual_unnamed[i], "#{path}[#{i}]"))
      end
    end
    diffs
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
    diffs.concat(diff_own_numeric(expected, actual, path, RECT_FIELDS)) if fields.include?(:graph)
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
    diffs.concat(diff_labels(expected_owner, actual_owner, path)) if fields.include?(:labels)
    if fields.include?(:ports) || fields.include?(:labels)
      diffs.concat(diff_ports(expected_owner, actual_owner, path, fields))
    end
    diffs
  end

  def diff_children_tree(expected, actual, fields, path)
    diff_by_id(expected["children"], actual["children"], "#{path}/children") do |e_node, a_node, node_path|
      diffs = fields.include?(:nodes) ? diff_own_numeric(e_node, a_node, node_path, RECT_FIELDS) : []
      diffs.concat(diff_owner_fields(e_node, a_node, fields, node_path))
      diffs.concat(diff_children_tree(e_node, a_node, fields, node_path))
      diffs
    end
  end

  def diff_labels(expected_owner, actual_owner, path)
    diff_by_id(expected_owner["labels"], actual_owner["labels"], "#{path}/labels") do |e, a, label_path|
      diff_own_numeric(e, a, label_path, RECT_FIELDS)
    end
  end

  # Called whenever `:ports` OR `:labels` is selected (see
  # `diff_owner_fields`) — port geometry/side/index/offset stay behind
  # `:ports` internally so a `:labels`-only caller reaching this method
  # (to get at port-owned labels) doesn't also pull in port position deltas
  # it never asked for.
  def diff_ports(expected_owner, actual_owner, path, fields)
    diff_by_id(expected_owner["ports"], actual_owner["ports"], "#{path}/ports") do |e, a, port_path|
      diffs = fields.include?(:labels) ? diff_labels(e, a, port_path) : []
      next diffs unless fields.include?(:ports)

      diffs.concat(diff_own_numeric(e, a, port_path, RECT_FIELDS))
      e_side, a_side = e["side"] || "UNDEFINED", a["side"] || "UNDEFINED"
      diffs << "#{port_path}/side: expected #{e_side}, got #{a_side}" if e_side != a_side
      diffs << "#{port_path}/index: expected #{e['index']}, got #{a['index']}" if e["index"] != a["index"]
      e_offset, a_offset = (e["offset"] || 0.0).to_f, (a["offset"] || 0.0).to_f
      diffs << "#{port_path}/offset: expected #{e_offset}, got #{a_offset}" unless (e_offset - a_offset).abs <= 1e-6
      diffs
    end
  end

  def diff_edges(expected_owner, actual_owner, fields, path)
    diff_by_id(expected_owner["edges"], actual_owner["edges"], "#{path}/edges") do |e_edge, a_edge, edge_path|
      diffs = fields.include?(:sections) ? diff_sections(e_edge, a_edge, edge_path) : []
      diffs.concat(diff_labels(e_edge, a_edge, edge_path)) if fields.include?(:labels)
      diffs
    end
  end

  def diff_sections(expected_edge, actual_edge, path)
    diff_by_id(expected_edge["sections"], actual_edge["sections"], "#{path}/sections") do |e_sec, a_sec, sec_path|
      diffs = diff_point(e_sec["startPoint"], a_sec["startPoint"], "#{sec_path}/startPoint")
      diffs.concat(diff_point(e_sec["endPoint"], a_sec["endPoint"], "#{sec_path}/endPoint"))
      diffs.concat(diff_bend_points(e_sec["bendPoints"], a_sec["bendPoints"], "#{sec_path}/bendPoints"))
      if e_sec["incomingShape"] != a_sec["incomingShape"]
        diffs << "#{sec_path}/incomingShape: expected #{e_sec['incomingShape'].inspect}, got #{a_sec['incomingShape'].inspect}"
      end
      if e_sec["outgoingShape"] != a_sec["outgoingShape"]
        diffs << "#{sec_path}/outgoingShape: expected #{e_sec['outgoingShape'].inspect}, got #{a_sec['outgoingShape'].inspect}"
      end
      diffs
    end
  end

  def diff_bend_points(expected_points, actual_points, path)
    expected_points ||= []
    actual_points ||= []
    if expected_points.size != actual_points.size
      return ["#{path}: expected #{expected_points.size} bend points, got #{actual_points.size}"]
    end

    expected_points.each_with_index.flat_map { |point, i| diff_point(point, actual_points[i], "#{path}[#{i}]") }
  end

  def diff_point(expected_point, actual_point, path)
    return ["#{path}: missing"] unless expected_point && actual_point

    diff_own_numeric(expected_point, actual_point, path, POINT_FIELDS)
  end

  # Structural tier: graph size within 1px, every edge section clipped to
  # its endpoint node/port border within 1px, per-layer membership/order
  # equal (grouped by rounded x for RIGHT/LEFT direction, y for UP/DOWN).
  def diff_structural(expected, actual)
    diffs = []
    diffs.concat(diff_graph_size(expected, actual))
    diffs.concat(diff_section_borders(expected, actual))
    diffs.concat(diff_layer_membership(expected, actual))
    diffs
  end

  def diff_graph_size(expected, actual)
    %w[width height].filter_map do |key|
      e = numeric_or_zero(expected, key)
      a = numeric_or_zero(actual, key)
      next "graph/#{key}: actual is non-finite (#{actual[key].inspect})" unless a.finite?

      "graph/#{key}: expected #{e}, got #{a} (>1px)" if (e - a).abs > 1
    end
  end

  # Every edge section's start/end point lies on the border (within 1px) of
  # the rectangle belonging to its incomingShape/outgoingShape id (falls
  # back to sources[0]/targets[0] if absent). The reference rectangle is
  # built from the ACTUAL level, not expected — structural tier does not
  # require elkrb's nodes to sit where elkjs put them, only that elkrb's
  # own edges land on elkrb's own node borders. Checks the first section's
  # start and the last section's end (bend points in between are not
  # tested at structural tier), one container level at a time (root, then
  # each matched compound child), since section coordinates are only
  # comparable within their own container's frame.
  def diff_section_borders(expected, actual)
    diffs = []
    check_level_sections(expected, actual, "", diffs)
    diffs
  end

  def check_level_sections(expected_level, actual_level, path, diffs)
    # rect_index merges node ids and port ids into one flat lookup (an
    # edge endpoint can name either) — a duplicate within that COMBINED
    # namespace (two ports sharing an id, or a port id colliding with a
    # node id) would otherwise silently collapse the same way a
    # duplicate node/edge id would.
    diffs.concat(duplicate_id_diffs(reference_ids(actual_level), "#{path}/(nodes+ports): actual"))
    rects = rect_index(actual_level)
    expected_edges = expected_level["edges"] || []
    actual_edges_list = actual_level["edges"] || []
    diffs.concat(duplicate_id_diffs(expected_edges, "#{path}/edges: expected"))
    diffs.concat(duplicate_id_diffs(actual_edges_list, "#{path}/edges: actual"))

    expected_edge_ids = expected_edges.map { |e| e["id"] }
    actual_edges = actual_edges_list.to_h { |e| [e["id"], e] }
    actual_edge_ids = actual_edges.keys

    (expected_edge_ids - actual_edge_ids).each { |id| diffs << "#{path}/edges/#{id}: missing from actual" }
    (actual_edge_ids - expected_edge_ids).each { |id| diffs << "#{path}/edges/#{id}: unexpected in actual" }

    (expected_level["edges"] || []).each do |edge|
      actual_edge = actual_edges[edge["id"]]
      next unless actual_edge # already recorded above as missing

      sections = actual_edge["sections"] || []
      next diffs << "#{path}/edges/#{edge['id']}: no sections in actual" if sections.empty?

      first_section, last_section = sections.first, sections.last
      # `incomingShape`/`outgoingShape` are set by layered and its
      # relatives but not by force/stress/random/radial (confirmed
      # empirically across the committed goldens) — without one, which
      # node the point SHOULD clip to isn't just unlabelled, it isn't
      # even reliably source-then-target: `random3`'s committed golden
      # anchors both this edge's start AND end on its SOURCE node's
      # border, never the target's (verified by running
      # `diff_structural(expected, expected)` against the real golden).
      # A single fixed candidate (always source for start, always target
      # for end) would guess wrong there, so both the start and end
      # checks use the SAME either-endpoint candidate list and accept
      # either. Candidates come from the ACTUAL edge's own sources/
      # targets (never the expected edge's — elkrb's endpoints are the
      # ground truth for what its own sections should clip to);
      # `point_near_any_reference` still requires every candidate to
      # resolve to a real rectangle before applying the geometry check,
      # so a genuinely dangling reference (an id naming no real node/
      # port) is reported on its own rather than silently forgiven by a
      # valid candidate elsewhere in the list.
      start_ids = first_section["incomingShape"] ? [first_section["incomingShape"]] : endpoint_candidates(actual_edge)
      end_ids = last_section["outgoingShape"] ? [last_section["outgoingShape"]] : endpoint_candidates(actual_edge)

      diffs.concat(point_near_any_reference(first_section["startPoint"], rects, start_ids, "#{path}/edges/#{edge['id']}/start"))
      diffs.concat(point_near_any_reference(last_section["endPoint"], rects, end_ids, "#{path}/edges/#{edge['id']}/end"))
    end

    expected_children_list = expected_level["children"] || []
    actual_children_list = actual_level["children"] || []
    diffs.concat(duplicate_id_diffs(expected_children_list, "#{path}/children: expected"))
    diffs.concat(duplicate_id_diffs(actual_children_list, "#{path}/children: actual"))

    expected_children = expected_children_list.to_h { |c| [c["id"], c] }
    actual_children = actual_children_list.to_h { |c| [c["id"], c] }

    (expected_children.keys - actual_children.keys).each { |id| diffs << "#{path}/children/#{id}: missing from actual" }
    (actual_children.keys - expected_children.keys).each { |id| diffs << "#{path}/children/#{id}: unexpected in actual" }

    expected_children.each do |id, child|
      match = actual_children[id]
      check_level_sections(child, match, "#{path}/children/#{id}", diffs) if match
    end
  end

  # id => {x:, y:, width:, height:} for every direct child node and its
  # ports, in this level's own frame (nodes and ports both carry x/y
  # relative to their own parent, which is this level). Ports get a
  # rectangle exactly like nodes, not a centre point: real elkjs 0.11.0
  # output confirms this — `ports_simple`'s committed golden anchors its
  # edge at the port's right BORDER (x=48 = node.x(12) + port.x(30) +
  # port.width(6)), not at the port's centre (x=45) — verified by running
  # `diff_structural` against the golden itself with a centre-based check:
  # it rejected the golden against ITSELF. (A later slice's design intent
  # for elkrb's own port-anchor convention may still land on the centre —
  # that is a decision for that slice's implementation, not for this
  # matcher, whose job is comparing against what real elkjs actually
  # produced.)
  # Every id `rect_index` below would key its lookup by, wrapped as
  # `duplicate_id_diffs`-shaped items (each responding to `item["id"]`) so
  # a duplicate anywhere in that combined node+port namespace is caught
  # before `rect_index` silently collapses it.
  def reference_ids(level)
    (level["children"] || []).flat_map do |node|
      [{ "id" => node["id"] }] + (node["ports"] || []).map { |port| { "id" => port["id"] } }
    end
  end

  def rect_index(level)
    index = {}
    (level["children"] || []).each do |node|
      index[node["id"]] = numeric_rect(node)
      (node["ports"] || []).each do |port|
        index[port["id"]] = {
          x: numeric_or_zero(node, "x") + numeric_or_zero(port, "x"),
          y: numeric_or_zero(node, "y") + numeric_or_zero(port, "y"),
          width: numeric_or_zero(port, "width"),
          height: numeric_or_zero(port, "height"),
        }
      end
    end
    index
  end

  def numeric_rect(hash)
    {
      x: numeric_or_zero(hash, "x"), y: numeric_or_zero(hash, "y"),
      width: numeric_or_zero(hash, "width"), height: numeric_or_zero(hash, "height"),
    }
  end

  def endpoint_candidates(edge)
    [edge.dig("sources", 0), edge.dig("targets", 0)].compact.uniq
  end

  # Passes if the point is near ANY candidate's border — used when the
  # actual data doesn't say which one it should be (see the comment in
  # `check_level_sections`). Every candidate must resolve to a real
  # rectangle first: without that check, an edge naming one real endpoint
  # and one genuinely dangling id (a reference to a node/port that isn't
  # in the actual result at all) would silently pass as long as the point
  # happened to land near the real one — a dangling reference is its own
  # bug, independent of where the point ends up. Reports the first
  # candidate's diff when every candidate resolves but none match, since
  # a single concrete "expected near X" reads better than a combined
  # message over every candidate.
  def point_near_any_reference(point, index, ids, path)
    return ["#{path}: no reference for any of #{ids.inspect}"] if ids.empty?

    unresolved = ids.reject { |id| index.key?(id) }
    return ["#{path}: no reference rectangle for #{unresolved.inspect} (candidates: #{ids.inspect})"] unless unresolved.empty?

    results = ids.map { |id| point_on_border(point, index[id], path) }
    results.any?(&:empty?) ? [] : results.first
  end

  def point_on_border(point, rect, path)
    return ["#{path}: point missing x/y"] unless point && point["x"].is_a?(Numeric) && point["y"].is_a?(Numeric)

    px, py = point["x"].to_f, point["y"].to_f
    return ["#{path}: (#{px},#{py}) is non-finite"] unless px.finite? && py.finite?

    left, right = rect[:x], rect[:x] + rect[:width]
    top, bottom = rect[:y], rect[:y] + rect[:height]

    on_vertical_edge = (px - left).abs <= 1 || (px - right).abs <= 1
    on_horizontal_edge = (py - top).abs <= 1 || (py - bottom).abs <= 1
    within_x = px >= left - 1 && px <= right + 1
    within_y = py >= top - 1 && py <= bottom + 1

    on_border = (on_vertical_edge && within_y) || (on_horizontal_edge && within_x)
    on_border ? [] : ["#{path}: (#{px},#{py}) not on border of #{rect}"]
  end

  # Per-layer membership/order, layered cases only: skipped at any level
  # whose graph pins a non-layered elk.algorithm (radial/rectpacking/
  # force/stress/random/sporeOverlap in this slice's structural-tier
  # cases). Compares ORDERED layer groups, not the raw rounded coordinate
  # used to form them — two runs that agree on which nodes share a layer
  # and in what order the layers run must match even when the exact
  # coordinate differs (that precision is exact tier's job, not
  # structural's). Recurses into every matched compound child — a
  # compound's own children form their own layered sequence in their own
  # frame (`compound_nested`'s meaningful layering is two levels below its
  # root, which only ever has one child, so a root-only check would be
  # vacuous for it); this simplified recursion assumes a nested level is
  # also layered unless it pins otherwise, which is true for every case
  # this slice authors — a future slice adding a non-layered nested pin
  # revisits this.
  def diff_layer_membership(expected, actual, path = "root")
    # Same normalisation as `AlgorithmRegistry.normalize_name`
    # (algorithm_registry.rb): a fully-qualified id like
    # "org.eclipse.elk.layered" resolves to "layered", not to a literal
    # mismatch against the bare form.
    algorithm = expected.dig("layoutOptions", "elk.algorithm")&.then { |a| a.to_s.split(".").last.downcase }
    diffs =
      if algorithm && algorithm != "layered"
        []
      else
        direction = expected.dig("layoutOptions", "elk.direction") || "RIGHT"
        axis = %w[UP DOWN].include?(direction) ? :y : :x
        cross_axis = axis == :y ? :x : :y

        expected_layers = group_by_layer(expected["children"] || [], axis, cross_axis)
        actual_layers = group_by_layer(actual["children"] || [], axis, cross_axis)

        if expected_layers == actual_layers
          []
        else
          ["#{path}: layer membership/order: expected #{expected_layers.inspect}, got #{actual_layers.inspect}"]
        end
      end

    expected_children = (expected["children"] || []).to_h { |c| [c["id"], c] }
    actual_children = (actual["children"] || []).to_h { |c| [c["id"], c] }
    expected_children.each do |id, child|
      match = actual_children[id]
      diffs.concat(diff_layer_membership(child, match, "#{path}/children/#{id}")) if match
    end
    diffs
  end

  # Returns an Array of Arrays of node ids: grouped by ascending rounded
  # primary-axis position (an ordinal sequence, not a Hash keyed by the
  # rounded coordinate, so a uniform sub-pixel shift of every node still
  # compares equal), each group internally ordered by ascending
  # cross-axis position (id only breaks an exact cross-axis tie) — a
  # same-layer top/bottom swap changes this order, unlike the previous
  # alphabetical-by-id sort, which could not distinguish that from a
  # correct layout.
  def group_by_layer(nodes, axis, cross_axis)
    nodes
      .group_by { |n| numeric_or_zero(n, axis.to_s).round }
      .sort.to_h
      .values
      .map { |group| group.sort_by { |n| [numeric_or_zero(n, cross_axis.to_s), n["id"]] }.map { |n| n["id"] } }
  end

  # smoke tier: same node ids present (order-independent), every node's
  # OWN position (x/y) present and finite — matches the card's tier
  # definition literally ("same node ids, finite coordinates"); the root's
  # own x/y is exempt (see `have_finite_coordinates`'s comment: elkrb never
  # assigns the root a position, confirmed empirically, so requiring it
  # here would fail every graph); node dimensions and sections/labels/
  # ports finiteness are `have_finite_coordinates`'s job (Task 3), not this
  # tier's.
  def diff_smoke(expected, actual)
    expected_ids = collect_ids(expected)
    actual_ids = collect_ids(actual)
    diffs = []
    if expected_ids.sort != actual_ids.sort
      diffs << "node ids differ: expected #{expected_ids.sort}, got #{actual_ids.sort}"
    end
    diffs.concat(collect_non_finite_positions(actual))
    diffs
  end

  def collect_ids(level)
    ids = (level["children"] || []).map { |n| n["id"] }
    ids + (level["children"] || []).flat_map { |n| collect_ids(n) }
  end

  def collect_non_finite_positions(level, path = "")
    (level["children"] || []).flat_map do |child|
      node_path = "#{path}/#{child['id']}"
      diffs = %w[x y].filter_map do |key|
        value = child[key]
        "#{node_path}/#{key}=#{value.inspect}" unless value.is_a?(Numeric) && value.finite?
      end
      diffs + collect_non_finite_positions(child, node_path)
    end
  end
end

RSpec::Matchers.define :match_elkjs_golden do |name, tier:, fields: %i[nodes sections labels ports graph], dir: GoldenHelper::DEFAULT_DIR|
  match do |actual|
    expected = golden_expected(name, dir: dir)
    comparable_actual = GoldenComparator.error_hash?(actual) ? actual : GoldenComparator.to_comparable(actual)

    @diffs =
      if GoldenComparator.error_hash?(expected) || GoldenComparator.error_hash?(comparable_actual)
        error_diffs(expected, comparable_actual)
      else
        case tier
        when :exact then GoldenComparator.diff_exact(expected, comparable_actual, fields)
        when :structural then GoldenComparator.diff_structural(expected, comparable_actual)
        when :smoke then GoldenComparator.diff_smoke(expected, comparable_actual)
        else raise ArgumentError, "unknown tier: #{tier.inspect}"
        end
      end

    @diffs.empty?
  end

  define_method(:error_diffs) do |expected, actual|
    expected_error = GoldenComparator.error_hash?(expected)
    actual_error = GoldenComparator.error_hash?(actual)
    return [] if expected_error && actual_error

    if expected_error
      ["expected an elkjs-style error, got a successful layout"]
    else
      ["unexpected error: #{GoldenComparator.error_message(actual)}"]
    end
  end

  failure_message do |_actual|
    "#{name} (tier: #{tier}) — first #{[@diffs.size, 10].min} of #{@diffs.size} differences:\n" +
      @diffs.first(10).join("\n")
  end
end
