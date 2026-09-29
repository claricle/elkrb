# spec/support/golden_comparator/shared.rb
# frozen_string_literal: true

require "json"

# Split out of golden_comparator.rb (which had grown to 1161 lines) into the
# tier-based files under this directory. This file holds what genuinely
# cannot live in a single tier: the error-hash convention, the numeric/id
# primitives every tier uses, and the one edge-endpoint check exact and
# structural share by design (see `diff_edge_endpoints` below). Splitting
# those OUT into exact.rb/structural.rb would not delete complexity, only
# relocate it and duplicate the "why" comments that already explain the
# sharing -- so they stay here instead.
module GoldenComparator
  module_function

  # Both construction sites for an error hash in this diff -- the rescue
  # clause in golden_spec.rb's `hyperedge` example, and
  # elkjs_golden/generate.js:101 writing `{ error: ... }` into the golden
  # file -- use a String "error" key. `JSON.parse` (how `golden_expected`
  # reads the other side) never produces Symbol keys either, since nothing
  # here passes `symbolize_names: true`. One convention, not defended
  # against a Symbol-keyed hash nothing produces.
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
  def same_error_condition?(expected_message, actual_message, expected: nil)
    # An explicit per-case pattern when the case carries one. Deriving the
    # condition from elkjs's own wording is a proxy, and a bad one: it asks
    # only whether a term APPEARS, so "simple edge accepted" passes as proof
    # that the edge was rejected for not being simple, and the settled elkrb
    # message "layered does not support hyperedges (edge e1)" fails for not
    # containing a word elkjs happened to use.
    return actual_message.match?(expected) if expected

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

  # The root's own id. Every other id in the harness is matched inside a
  # `children`/`edges` collection, and the root sits in neither -- so
  # renaming "root" to anything else produced no exact, structural or
  # smoke difference at all, and it is a reachable rename. Called by both
  # `diff_exact` (exact.rb) and `diff_structural` (structural.rb), so it
  # lives here rather than in either tier file.
  def diff_root_id(expected, actual)
    return [] if expected["id"] == actual["id"]

    ["graph/id: expected #{expected['id'].inspect}, " \
     "got #{actual['id'].inspect}"]
  end

  # Unlike `numeric_or_zero` ("missing reads as 0.0" — real for elkjs's
  # own width:0 quirk, and now confined to size fields), a node missing
  # its OWN position/size entirely is exactly the class of bug this
  # check exists to catch: elkrb emitting no geometry at all. Coercing
  # that to 0.0 would let such a node compare equal to a golden node
  # that legitimately sits at the origin. Used by both tiers —
  # structural's dimension/position checks (golden_comparator/structural.rb),
  # and exact tier's `diff_exact_position` (golden_comparator/exact.rb).
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

  # Building an id => item Hash from an Array silently keeps only the LAST
  # item for a repeated id — a genuine duplicate would otherwise vanish
  # from comparison instead of being reported. Checked wherever this
  # slice indexes a collection by id (`diff_by_id` below and
  # `check_level_sections`'s own edge/child indexing). `nil` ids are
  # excluded: real elkjs output has id-less labels (confirmed — ELK does
  # not require a label id), and multiple id-less items on the same owner
  # are a legitimate shape, not a duplicate-id bug. `diff_by_id` compares
  # every id-less item, positionally within the id-less subset of each
  # side — see `diff_unnamed_items`.
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
  # (`check_level_sections`, golden_comparator/structural.rb): exact tier
  # is supposed to be the STRICTER of the two, so a rewired edge silently
  # passing `diff_exact` while structural caught it had that backwards.
  # That is also why this method lives here, in the shared file, rather
  # than beside either tier: `diff_edges` (exact.rb) and
  # `check_edge_sections` (structural.rb) both call it, and the two tiers
  # must not be able to drift apart on what counts as a rewired edge.
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
      section_shape_diff(a_sec, expected_sections[i], endpoint_ids,
                         "#{path}/sections[#{i}]")
    end
  end

  # Two checks, and neither pins WHICH key a shape sits under.
  #
  # `edge_endpoint_ids` above unions sources and targets precisely because
  # ELK reverses a section's own shapes for cycle breaking without
  # rewiring the edge. A key-by-key `expected == actual` comparison here
  # said the opposite: swapping a valid a/b annotation to b/a produced two
  # differences in both tiers, which is the legitimate reversal that
  # comment says must be accepted. One rule, stated twice, disagreeing.
  #
  # Comparing the pair as a sorted SET keeps everything the equality gave
  # us -- the same nodes must be named, and a shape that vanishes or
  # appears is still a difference -- while allowing the one thing ELK is
  # documented to do. The membership check below is per key so its message
  # can still say which annotation named a stranger.
  def section_shape_diff(a_sec, e_sec, endpoint_ids, sec_path)
    diffs = SHAPE_KEYS.filter_map do |key|
      shape = a_sec[key]
      next if shape.nil? || endpoint_ids.include?(shape)

      "#{sec_path}/#{key}: #{shape.inspect} is not an endpoint of this " \
        "edge (#{endpoint_ids.inspect})"
    end

    expected = shape_set(e_sec)
    return diffs if expected.empty? || expected == shape_set(a_sec)

    diffs + ["#{sec_path}: expected shapes #{expected.inspect}, got " \
             "#{shape_set(a_sec).inspect} (which key each sits under is " \
             "not pinned -- cycle breaking may reverse them)"]
  end

  def shape_set(section)
    return [] if section.nil?

    SHAPE_KEYS.filter_map { |key| section[key] }.sort
  end
end
