# frozen_string_literal: true

require "json"

module GoldenHelper
  DEFAULT_DIR = File.join(__dir__, "..", "fixtures", "golden")
  DEFAULT_FIELDS = %i[nodes sections labels ports graph].freeze

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

  # Both construction sites for an error hash in this diff (golden_spec.rb's
  # rescue clauses) use a String "error" key -- `JSON.parse` (how
  # `golden_expected` reads the other side) never produces Symbol keys
  # either, since nothing here passes `symbolize_names: true`. One
  # convention, not defended against a Symbol-keyed hash nothing produces.
  def error_hash?(value)
    value.is_a?(Hash) && value.key?("error")
  end

  def error_message(value)
    value["error"]
  end

  # elkjs's message is Java-flavored ("...IllegalArgumentException: Passed
  # edge is not 'simple'.") and elkrb's own eventual message (once it
  # raises `Elkrb::UnsupportedConfigurationException`, per Decision 10)
  # will be worded differently in Ruby — comparing the full sentence would
  # never match. The condition elkjs names is the single-quoted term in
  # its message ('simple' here); requiring the actual message to name
  # that same term (case-insensitively) checks WHICH rejection happened
  # without demanding identical wording, so "an error happened" isn't
  # treated as proof of "the RIGHT error happened". No quoted term in the
  # expected message falls back to requiring an exact match.
  def same_error_condition?(expected_message, actual_message)
    quoted = expected_message[/'([^']+)'/, 1]
    return expected_message == actual_message unless quoted

    actual_message.downcase.include?(quoted.downcase)
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

  # Deep-compares two elkjs-shaped Hashes by id, numeric tolerance 1e-6.
  # Returns an Array of JSON-pointer-style diff strings, first 10 kept by
  # the caller.
  #
  # "Missing reads as 0.0" applies to SIZE only. That rule exists for one
  # real quirk — elkjs writes `width: 0` where elkrb omits the key — and
  # applying it to a POSITION as well made "never placed" compare equal to
  # "placed at the origin": deleting the (0,0) from `labeled_node`'s label
  # left the exact-tier diff empty. Positions go through `strict_numeric`
  # instead, which demands a finite Numeric on both sides — the same
  # helper structural tier already uses for the same reason.
  #
  # RECT_FIELDS survives for ONE caller: the root graph's own geometry.
  # elkrb never assigns the root a position (confirmed — a real result's
  # root carries width/height and no x/y at all), so the root is the one
  # place a missing position is a convention rather than a bug.
  RECT_FIELDS = %w[x y width height].freeze
  POSITION_FIELDS = %w[x y].freeze
  SIZE_FIELDS = %w[width height].freeze

  def numeric_or_zero(hash, key)
    (hash[key] || 0.0).to_f
  end

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
    items.filter_map do |item|
      item["id"]
    end.tally.select { |_, count| count > 1 }.map do |id, count|
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
  def diff_by_id(expected_items, actual_items, path, &)
    expected_named, expected_unnamed = partition_by_id(expected_items)
    actual_named, actual_unnamed = partition_by_id(actual_items)

    diff_named_items(expected_named, actual_named, path, &) +
      diff_unnamed_items(expected_unnamed, actual_unnamed, path, &)
  end

  def partition_by_id(items)
    (items || []).partition { |item| item["id"] }
  end

  def index_by_id(items)
    items.to_h { |item| [item["id"], item] }
  end

  def diff_named_items(expected_named, actual_named, path, &)
    diffs = duplicate_id_diffs(expected_named, "#{path}: expected")
    diffs.concat(duplicate_id_diffs(actual_named, "#{path}: actual"))

    expected_by_id = index_by_id(expected_named)
    actual_by_id = index_by_id(actual_named)
    diffs.concat(diff_id_sets(expected_by_id.keys, actual_by_id.keys, path))
    diffs.concat(diff_matched_items(expected_by_id, actual_by_id, path, &))
  end

  def diff_id_sets(expected_ids, actual_ids, path)
    (expected_ids - actual_ids).map do |id|
      "#{path}/#{id}: missing from actual"
    end + (actual_ids - expected_ids).map do |id|
      "#{path}/#{id}: unexpected in actual"
    end
  end

  def diff_matched_items(expected_by_id, actual_by_id, path)
    (expected_by_id.keys & actual_by_id.keys).flat_map do |id|
      yield(expected_by_id[id], actual_by_id[id], "#{path}/#{id}")
    end
  end

  def diff_unnamed_items(expected_unnamed, actual_unnamed, path)
    unless expected_unnamed.size == actual_unnamed.size
      return ["#{path}: expected #{expected_unnamed.size} id-less item(s), " \
              "got #{actual_unnamed.size}"]
    end

    expected_unnamed.each_with_index.flat_map do |item, i|
      yield(item, actual_unnamed[i], "#{path}[#{i}]")
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
      diff_exact_geometry(e, a, label_path)
    end
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

  SHAPE_KEYS = %w[incomingShape outgoingShape].freeze

  # sources+targets as one set, not sources-for-incoming and
  # targets-for-outgoing: ELK reverses a section's own shapes for cycle
  # breaking without touching the edge's sources/targets, and side-by-side
  # matching would read that legitimate output as a rewiring. Every
  # committed golden that emits a shape names exactly its own
  # sources[0]/targets[0] (checked across all 30), so the union is the
  # loosest rule that still rejects an unrelated node.
  def edge_endpoint_ids(edge)
    Array(edge["sources"]) + Array(edge["targets"])
  end

  # Which nodes/ports an edge connects -- the coarse sources/targets
  # array, and, where elkjs annotates it, each section's own
  # incomingShape/outgoingShape -- is one structural fact, checked
  # identically by BOTH tiers through this one helper so they can't
  # diverge on it. This used to live only in the structural path
  # (`check_level_sections`): exact tier is supposed to be the STRICTER
  # of the two, so a rewired edge silently passing `diff_exact` while
  # structural caught it had that backwards.
  #
  # `incomingShape`/`outgoingShape` are only set by layered and its
  # relatives (confirmed empirically -- force/stress/random/radial
  # goldens carry neither on any section). A section the golden leaves
  # unannotated is therefore compared against the edge's own endpoints
  # rather than skipped, and that is not belt-and-braces:
  # `check_level_sections` uses the ACTUAL section's own shape as the
  # rectangle its point must clip to, so an unchecked value is both
  # accepted AND believed. On a case where elkjs writes no shape at all
  # (force_tri), an `a -> b` edge could name unrelated node `c` on both
  # ends, route to c's border, and produce no differences at either tier.
  # A shape naming something that is not one of this edge's own endpoints
  # is a bug regardless of what the golden says.
  def diff_edge_endpoints(expected_edge, actual_edge, path)
    diff_endpoint_lists(expected_edge, actual_edge, path) +
      diff_section_shapes(expected_edge, actual_edge, path)
  end

  def diff_endpoint_lists(expected_edge, actual_edge, path)
    if expected_edge["sources"] == actual_edge["sources"] &&
        expected_edge["targets"] == actual_edge["targets"]
      return []
    end

    ["#{path}: endpoints changed from " \
     "#{expected_edge['sources']}->#{expected_edge['targets']} to " \
     "#{actual_edge['sources']}->#{actual_edge['targets']}"]
  end

  def diff_section_shapes(expected_edge, actual_edge, path)
    expected_sections = expected_edge["sections"] || []
    endpoint_ids = edge_endpoint_ids(actual_edge)

    (actual_edge["sections"] || []).each_with_index.flat_map do |a_sec, i|
      e_sec = expected_sections[i]
      SHAPE_KEYS.flat_map do |shape_key|
        shape_diff(a_sec[shape_key], e_sec && e_sec[shape_key], endpoint_ids,
                   "#{path}/sections[#{i}]/#{shape_key}")
      end
    end
  end

  def shape_diff(actual_shape, expected_shape, endpoint_ids, sec_path)
    if actual_shape && !endpoint_ids.include?(actual_shape)
      ["#{sec_path}: #{actual_shape.inspect} is not an endpoint of this " \
       "edge (#{endpoint_ids.inspect})"]
    elsif expected_shape && expected_shape != actual_shape
      ["#{sec_path}: expected #{expected_shape.inspect}, " \
       "got #{actual_shape.inspect}"]
    else
      []
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
  # `diff_edge_endpoints`'s job, not this method's.
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

  # Structural tier: graph size within 1px, every matched node's OWN
  # size/position (`diff_node_geometry`), every edge section clipped to
  # its endpoint node/port border within 1px, per-layer membership/order
  # equal (grouped by rounded x for RIGHT/LEFT direction, y for UP/DOWN).
  def diff_structural(expected, actual)
    diffs = []
    diffs.concat(diff_graph_size(expected, actual))
    diffs.concat(diff_node_geometry(expected, actual, ""))
    diffs.concat(diff_section_borders(expected, actual))
    diffs.concat(diff_layer_membership(expected, actual))
    diffs
  end

  def diff_graph_size(expected, actual)
    %w[width height].filter_map do |key|
      e = numeric_or_zero(expected, key)
      a = numeric_or_zero(actual, key)
      unless e.finite?
        next "graph/#{key}: expected is non-finite (#{expected[key].inspect})"
      end
      unless a.finite?
        next "graph/#{key}: actual is non-finite (#{actual[key].inspect})"
      end

      "graph/#{key}: expected #{e}, got #{a} (>1px)" if (e - a).abs > 1
    end
  end

  # Every OTHER structural check (id sets, section borders, layer
  # membership) can pass while every node is stacked on the origin,
  # permuted with its siblings, or a compound is sized nothing like its
  # declared size — none of them look at a node's OWN width/height/
  # position against the golden's. This is the check that does:
  #
  # - width/height within 1px, UNCONDITIONALLY (not gated by algorithm or
  #   direction) — a compound's declared size is not "loose", it is the
  #   one thing structural tier exists to prove for hierarchy (RC5).
  # - position, compared as a FRACTION of the containing level's own
  #   bounding box (each side normalised against ITS OWN width/height),
  #   not raw coordinates — different algorithms use different absolute
  #   coordinate conventions even for a correct layout (RIGHT vs DOWN,
  #   padding choices), so raw-coordinate comparison would be stricter
  #   than structural tier is meant to be. POSITION_TOLERANCE_FRACTION
  #   (0.15 — a node more than 15% of the graph's own span away from
  #   where it belongs) is coarse on purpose: it must not demand
  #   byte-identical placement, only catch a node stacked at the origin,
  #   swapped with a sibling, or otherwise clearly out of place. Being a
  #   DEADBAND rather than an absolute distance, it has known blind spots:
  #   a uniform small translation of every node (confirmed on `rect6`,
  #   +20px slips through, +30px is caught) or a swap between two
  #   siblings that already sat within 15% of each other both read as "no
  #   diff". Both are inherent to comparing normalised fractions rather
  #   than raw coordinates, and acceptable here (exact tier is where
  #   byte-identical placement is enforced) — but this is NOT a general
  #   "layout is right" proof, and a later slice tightening this
  #   tolerance should know that going in.
  #
  # Matched by `diff_by_id`, the same canonical by-id pairing every other
  # owner-child comparison in this file uses — which also means a node
  # present on only one side is reported here (structural tier had no
  # other check that would catch a node vanishing or appearing outright).
  # Recurses into every matched child, treating that child as the new
  # bounding box for ITS OWN children — the same per-level frame
  # `check_level_sections` and `rect_index` already use elsewhere in this
  # file.
  POSITION_TOLERANCE_FRACTION = 0.15

  # Unlike `numeric_or_zero` ("missing reads as 0.0" — real for elkjs's
  # own width:0 quirk, and now confined to size fields), a node missing
  # its OWN position/size entirely is exactly the class of bug this
  # check exists to catch: elkrb emitting no geometry at all. Coercing
  # that to 0.0 would let such a node compare equal to a golden node
  # that legitimately sits at the origin. Used by both tiers —
  # structural's dimension/position checks below, and exact tier's
  # `diff_exact_position`.
  # Returns [value, error] — value is nil whenever error is present, so a
  # caller can short-circuit on the error instead of computing with nil.
  def strict_numeric(hash, key, path, side)
    value = hash[key]
    unless value.is_a?(Numeric)
      return [nil,
              "#{path}/#{key}: #{side} is missing or not " \
              "numeric (#{value.inspect})"]
    end

    value = value.to_f
    unless value.finite?
      return [nil,
              "#{path}/#{key}: #{side} is non-finite (#{value})"]
    end

    [value, nil]
  end

  def diff_node_geometry(expected_level, actual_level, path)
    expected_box = box_of(expected_level)
    actual_box = box_of(actual_level)

    diff_by_id(expected_level["children"], actual_level["children"],
               path) do |e_node, a_node, node_path|
      diffs = SIZE_FIELDS.flat_map do |key|
        diff_strict_dimension(e_node, a_node, node_path, key)
      end
      diffs.concat(diff_normalised_position(expected_box.merge(node: e_node),
                                            actual_box.merge(node: a_node),
                                            node_path))
      diffs.concat(diff_node_geometry(e_node, a_node, node_path))
    end
  end

  def box_of(level)
    { width: numeric_or_zero(level, "width"),
      height: numeric_or_zero(level, "height") }
  end

  def diff_strict_dimension(e_node, a_node, path, key)
    e, e_error = strict_numeric(e_node, key, path, "expected")
    a, a_error = strict_numeric(a_node, key, path, "actual")
    return [e_error, a_error].compact if e_error || a_error

    (e - a).abs > 1 ? ["#{path}/#{key}: expected #{e}, got #{a} (>1px)"] : []
  end

  # Each side arrives as `{node:, width:, height:}` -- the node plus the
  # dimensions of the level that contains it, which is the box its
  # position is normalised against.
  def diff_normalised_position(expected, actual, path)
    diff_strict_axis_position({ node: expected[:node], box: expected[:width] },
                              { node: actual[:node], box: actual[:width] },
                              path, "x", "width") +
      diff_strict_axis_position({ node: expected[:node],
                                  box: expected[:height] },
                                { node: actual[:node], box: actual[:height] },
                                path, "y", "height")
  end

  # The box-dimension guard lives HERE, per axis, after `strict_numeric` --
  # not as one combined guard in the caller covering both axes. A
  # degenerate box on one axis (e.g. a zero-height container) is a reason
  # to skip THAT axis's fraction, not a reason to also skip strict
  # validation of the OTHER axis's x/y, or to skip validating x/y at all.
  def diff_strict_axis_position(expected, actual, path, key, box_label)
    e, e_error = strict_numeric(expected[:node], key, path, "expected")
    a, a_error = strict_numeric(actual[:node], key, path, "actual")
    return [e_error, a_error].compact if e_error || a_error
    return [] if expected[:box] <= 0 || actual[:box] <= 0

    normalised_position_diffs(e / expected[:box], a / actual[:box], path, key,
                              box_label)
  end

  def normalised_position_diffs(e_fraction, a_fraction, path, key, box_label)
    return [] unless (e_fraction - a_fraction).abs > POSITION_TOLERANCE_FRACTION

    ["#{path}/#{key}: normalised position " \
     "expected #{e_fraction.round(3)}, got #{a_fraction.round(3)} " \
     "(off by more than #{POSITION_TOLERANCE_FRACTION} " \
     "of the graph's own #{box_label})"]
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
    check_level_sections(expected, actual, "")
  end

  def check_level_sections(expected_level, actual_level, path)
    # rect_index merges node ids and port ids into one flat lookup (an
    # edge endpoint can name either) — a duplicate within that COMBINED
    # namespace (two ports sharing an id, or a port id colliding with a
    # node id) would otherwise silently collapse the same way a
    # duplicate node/edge id would.
    diffs = duplicate_id_diffs(reference_ids(actual_level),
                               "#{path}/(nodes+ports): actual")
    diffs.concat(check_level_edges(expected_level, actual_level, path))
    diffs.concat(check_level_children(expected_level, actual_level, path))
  end

  def check_level_edges(expected_level, actual_level, path)
    rects = rect_index(actual_level)
    expected_edges = expected_level["edges"] || []
    actual_edges_list = actual_level["edges"] || []
    diffs = duplicate_id_diffs(expected_edges, "#{path}/edges: expected")
    diffs.concat(duplicate_id_diffs(actual_edges_list, "#{path}/edges: actual"))

    actual_edges = index_by_id(actual_edges_list)
    diffs.concat(diff_edge_membership(expected_edges, actual_edges.keys, path))
    diffs.concat(check_matched_edges(expected_edges, actual_edges, rects, path))
  end

  # Deliberately Array-based, not `diff_by_id`: `expected_edges.map` keeps
  # duplicate ids, so an id repeated on the expected side is reported once
  # per occurrence. Indexing it into a Hash first would collapse those and
  # silently report the duplicate a single time.
  def diff_edge_membership(expected_edges, actual_edge_ids, path)
    expected_edge_ids = expected_edges.map { |e| e["id"] }
    (expected_edge_ids - actual_edge_ids).map do |id|
      "#{path}/edges/#{id}: missing from actual"
    end + (actual_edge_ids - expected_edge_ids).map do |id|
      "#{path}/edges/#{id}: unexpected in actual"
    end
  end

  # Iterates the expected Array, not its id set, for the same reason
  # `diff_edge_membership` does: a duplicated expected id runs the
  # per-edge body once per occurrence.
  def check_matched_edges(expected_edges, actual_edges, rects, path)
    expected_edges.flat_map do |edge|
      actual_edge = actual_edges[edge["id"]]
      next [] unless actual_edge # already recorded above as missing

      check_edge_sections(edge, actual_edge, rects,
                          "#{path}/edges/#{edge['id']}")
    end
  end

  def check_edge_sections(edge, actual_edge, rects, edge_path)
    # Checked BEFORE using `actual_edge`'s own sources/targets as the
    # geometry reference below: without this, an edge silently rewired
    # to different endpoints (elkrb connecting the wrong nodes) would
    # still pass, because the border check only asks "does the section
    # land on ACTUAL's own (rewired) endpoint's border" — trivially
    # true, since that endpoint IS what routed it. `diff_edge_endpoints`
    # is the same helper exact tier's `diff_edges` calls, so the two
    # tiers can't diverge on what counts as a rewired edge.
    diffs = diff_edge_endpoints(edge, actual_edge, edge_path)

    sections = actual_edge["sections"] || []
    return diffs << "#{edge_path}: no sections in actual" if sections.empty?

    diffs.concat(check_section_border(sections.first,
                                      %w[startPoint incomingShape],
                                      actual_edge, rects, "#{edge_path}/start"))
    diffs.concat(check_section_border(sections.last,
                                      %w[endPoint outgoingShape],
                                      actual_edge, rects, "#{edge_path}/end"))
  end

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
  # valid candidate elsewhere in the list. Taking the ACTUAL section's
  # own shape as the reference is only safe because
  # `diff_edge_endpoints` above has already rejected a shape naming
  # anything other than this edge's own endpoints — otherwise the
  # point would be measured against whatever rectangle elkrb chose to
  # name, which is no check at all.
  def check_section_border(section, keys, actual_edge, rects, point_path)
    point_key, shape_key = keys
    shape_id = section[shape_key]
    ids = shape_id ? [shape_id] : endpoint_candidates(actual_edge)
    point_near_any_reference(section[point_key], rects, ids, point_path)
  end

  def check_level_children(expected_level, actual_level, path)
    expected_children_list = expected_level["children"] || []
    actual_children_list = actual_level["children"] || []
    diffs = duplicate_id_diffs(expected_children_list,
                               "#{path}/children: expected")
    diffs.concat(duplicate_id_diffs(actual_children_list,
                                    "#{path}/children: actual"))

    expected_children = index_by_id(expected_children_list)
    actual_children = index_by_id(actual_children_list)
    diffs.concat(diff_id_sets(expected_children.keys, actual_children.keys,
                              "#{path}/children"))
    diffs.concat(recurse_matched_children(expected_children, actual_children,
                                          path))
  end

  def recurse_matched_children(expected_children, actual_children, path)
    expected_children.flat_map do |id, child|
      match = actual_children[id]
      next [] unless match

      check_level_sections(child, match, "#{path}/children/#{id}")
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
      [{ "id" => node["id"] }] + (node["ports"] || []).map do |port|
        { "id" => port["id"] }
      end
    end
  end

  def rect_index(level)
    (level["children"] || []).each_with_object({}) do |node, index|
      index[node["id"]] = numeric_rect(node)
      (node["ports"] || []).each do |port|
        index[port["id"]] = port_rect(node, port)
      end
    end
  end

  def port_rect(node, port)
    {
      x: numeric_or_zero(node, "x") + numeric_or_zero(port, "x"),
      y: numeric_or_zero(node, "y") + numeric_or_zero(port, "y"),
      width: numeric_or_zero(port, "width"),
      height: numeric_or_zero(port, "height"),
    }
  end

  def numeric_rect(hash)
    {
      x: numeric_or_zero(hash, "x"), y: numeric_or_zero(hash, "y"),
      width: numeric_or_zero(hash, "width"),
      height: numeric_or_zero(hash, "height")
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
    unless unresolved.empty?
      return ["#{path}: no reference rectangle for #{unresolved.inspect} " \
              "(candidates: #{ids.inspect})"]
    end

    nearest_border_diffs(point, index, ids, path)
  end

  def nearest_border_diffs(point, index, ids, path)
    results = ids.map { |id| point_on_border(point, index[id], path) }
    results.any?(&:empty?) ? [] : results.first
  end

  def point_on_border(point, rect, path)
    return ["#{path}: point missing x/y"] unless numeric_point?(point)

    point_x = point["x"].to_f
    point_y = point["y"].to_f
    unless point_x.finite? && point_y.finite?
      return ["#{path}: (#{point_x},#{point_y}) is non-finite"]
    end
    return [] if on_border?(point_x, point_y, rect)

    ["#{path}: (#{point_x},#{point_y}) not on border of #{rect}"]
  end

  def numeric_point?(point)
    point && point["x"].is_a?(Numeric) && point["y"].is_a?(Numeric)
  end

  def on_border?(point_x, point_y, rect)
    left = rect[:x]
    top = rect[:y]
    right = left + rect[:width]
    bottom = top + rect[:height]

    (near_either?(point_x, left, right) &&
      point_y.between?(top - 1, bottom + 1)) ||
      (near_either?(point_y, top, bottom) &&
        point_x.between?(left - 1, right + 1))
  end

  def near_either?(value, low, high)
    (value - low).abs <= 1 || (value - high).abs <= 1
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
    diffs = diff_layer_grouping(expected, actual, path)
    diffs.concat(diff_layer_children(expected, actual, path))
  end

  # Same normalisation as `AlgorithmRegistry.normalize_name`
  # (algorithm_registry.rb): a fully-qualified id like
  # "org.eclipse.elk.layered" resolves to "layered", not to a literal
  # mismatch against the bare form. A level that pins nothing is treated
  # as layered.
  def layered?(level)
    algorithm = level.dig("layoutOptions", "elk.algorithm")&.then do |a|
      a.to_s.split(".").last.downcase
    end
    algorithm.nil? || algorithm == "layered"
  end

  def layer_axes(level)
    direction = level.dig("layoutOptions", "elk.direction") || "RIGHT"
    axis = %w[UP DOWN].include?(direction) ? :y : :x
    [axis, axis == :y ? :x : :y]
  end

  # Only the LAYER message is skipped for a non-layered level. The child
  # recursion in `diff_layer_children` is not, and must not be folded in
  # here as an early return -- a non-layered root still has to reach a
  # mismatching compound child.
  def diff_layer_grouping(expected, actual, path)
    return [] unless layered?(expected)

    axis, cross_axis = layer_axes(expected)
    expected_layers = group_by_layer(expected["children"] || [], axis,
                                     cross_axis)
    actual_layers = group_by_layer(actual["children"] || [], axis, cross_axis)
    return [] if expected_layers == actual_layers

    ["#{path}: layer membership/order: " \
     "expected #{expected_layers.inspect}, got #{actual_layers.inspect}"]
  end

  def diff_layer_children(expected, actual, path)
    actual_children = index_by_id(actual["children"] || [])
    index_by_id(expected["children"] || []).flat_map do |id, child|
      match = actual_children[id]
      next [] unless match

      diff_layer_membership(child, match, "#{path}/children/#{id}")
    end
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
      .map { |group| layer_ids(group, cross_axis) }
  end

  def layer_ids(group, cross_axis)
    group.sort_by { |n| [numeric_or_zero(n, cross_axis.to_s), n["id"]] }
      .map { |n| n["id"] }
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
      diffs << "node ids differ: expected #{expected_ids.sort}, " \
               "got #{actual_ids.sort}"
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
      diffs = POSITION_FIELDS.filter_map do |key|
        value = child[key]
        unless value.is_a?(Numeric) && value.finite?
          "#{node_path}/#{key}=#{value.inspect}"
        end
      end
      diffs + collect_non_finite_positions(child, node_path)
    end
  end
end

RSpec::Matchers.define :match_elkjs_golden do |
  name,
  tier:,
  fields: GoldenHelper::DEFAULT_FIELDS,
  dir: GoldenHelper::DEFAULT_DIR|
  match do |actual|
    expected = golden_expected(name, dir: dir)
    comparable_actual =
      if GoldenComparator.error_hash?(actual)
        actual
      else
        GoldenComparator.to_comparable(actual)
      end

    @diffs =
      if GoldenComparator.error_hash?(expected) ||
          GoldenComparator.error_hash?(comparable_actual)
        error_diffs(expected, comparable_actual)
      else
        case tier
        when :exact
          GoldenComparator.diff_exact(expected, comparable_actual, fields)
        when :structural
          GoldenComparator.diff_structural(expected, comparable_actual)
        when :smoke
          GoldenComparator.diff_smoke(expected, comparable_actual)
        else
          raise ArgumentError, "unknown tier: #{tier.inspect}"
        end
      end

    @diffs.empty?
  end

  define_method(:error_diffs) do |expected, actual|
    expected_error = GoldenComparator.error_hash?(expected)
    actual_error = GoldenComparator.error_hash?(actual)

    if expected_error && actual_error
      expected_message = GoldenComparator.error_message(expected)
      actual_message = GoldenComparator.error_message(actual)
      return [] if GoldenComparator.same_error_condition?(expected_message,
                                                          actual_message)

      return ["expected an error naming the same condition as " \
              "#{expected_message.inspect}, got #{actual_message.inspect}"]
    end

    if expected_error
      ["expected an elkjs-style error, got a successful layout"]
    else
      ["unexpected error: #{GoldenComparator.error_message(actual)}"]
    end
  end

  failure_message do |_actual|
    shown = [@diffs.size, 10].min
    "#{name} (tier: #{tier}) — first #{shown} of #{@diffs.size} " \
    "differences:\n" + @diffs.first(10).join("\n")
  end
end
