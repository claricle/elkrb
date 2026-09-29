# spec/support/golden_comparator/structural.rb
# frozen_string_literal: true

require_relative "shared"

# The `:structural` tier: graph size within 1px, every matched node's OWN
# size/position, every edge section clipped to its endpoint node/port
# border within 1px, per-layer membership/order equal. Split out of
# golden_comparator.rb, which had grown to 1161 lines — this is the largest
# of the tier files (structural tier does the most work of the three), but
# every method here is structural-tier-only; what it shares with `:exact`
# stays in shared.rb rather than being duplicated.
module GoldenComparator
  module_function

  # The two rect indexes a section check needs at once: `actual` is what a
  # point is measured against, `expected` is what says which endpoint the
  # golden anchored that point to.
  Rects = Struct.new(:actual, :expected)

  # One end of one edge: the ACTUAL point being checked, the shape it
  # names if it names one, and the GOLDEN's own point for that end.
  Anchor = Struct.new(:point, :shape, :golden)

  # start and end read identically from opposite ends of the section
  # list, so they are one table rather than two near-identical call
  # sites that can drift apart.
  EDGE_ENDS = [["start", :first, "startPoint", "incomingShape"],
               ["end", :last, "endPoint", "outgoingShape"]].freeze

  # The two directions a section can name a routing-ref neighbour through.
  # Shared by `dangling_ref_diffs` and `ref_joints` so both read the exact
  # same pair of keys.
  ROUTING_REF_KEYS = %w[outgoingSections incomingSections].freeze

  # The fields structural tier can independently select. `:labels` and
  # `:ports` are accepted (`STRUCTURAL_FIELDS` matches `GoldenHelper::
  # DEFAULT_FIELDS`'s membership so the default call below stays
  # behaviour-identical to before `fields` existed here) but are always a
  # no-op: structural tier has never checked either independently of
  # `:nodes`/`:sections`, so selecting only one of them narrows nothing.
  STRUCTURAL_FIELDS = %i[nodes sections labels ports graph].freeze

  # Structural tier: graph size within 1px (`:graph`), every matched
  # node's OWN size/position and per-layer membership/order (`:nodes` --
  # layer membership is fundamentally about node arrangement, the same
  # ground `diff_node_geometry` covers), every edge section clipped to its
  # endpoint node/port border within 1px (`:sections`). `fields` defaults
  # to every category, so an existing 2-arg call site runs every check
  # exactly as it did before `fields` was a parameter here at all.
  def diff_structural(expected, actual, fields = STRUCTURAL_FIELDS)
    diffs = []
    if fields.include?(:graph)
      diffs.concat(diff_root_id(expected, actual))
      diffs.concat(diff_graph_size(expected, actual))
    end
    if fields.include?(:nodes)
      diffs.concat(diff_node_geometry(expected, actual, ""))
      diffs.concat(diff_layer_membership(expected, actual))
    end
    if fields.include?(:sections)
      diffs.concat(diff_section_borders(expected,
                                        actual))
    end
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

  # 0.15 — a node more than 15% of the graph's own span away from where
  # it belongs. Coarse on purpose: it must not demand byte-identical
  # placement, only catch a node stacked at the origin, swapped with a
  # sibling, or otherwise clearly out of place. Being a DEADBAND rather
  # than an absolute distance, it has known blind spots: a uniform small
  # translation of every node (confirmed on `rect6`, +20px slips through,
  # +30px is caught) or a swap between two siblings that already sat
  # within 15% of each other both read as "no diff". Both are inherent to
  # comparing normalised fractions rather than raw coordinates, and
  # acceptable here (exact tier is where byte-identical placement is
  # enforced) — but this is NOT a general "layout is right" proof, and a
  # later slice tightening this tolerance should know that going in.
  POSITION_TOLERANCE_FRACTION = 0.15

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
  #   than structural tier is meant to be. The tolerance on that
  #   fraction is POSITION_TOLERANCE_FRACTION above.
  #
  # Matched by `diff_by_id` (golden_comparator/shared.rb), the same
  # canonical by-id pairing every owner-child comparison in this
  # comparator uses — which also means a node present on only one side is
  # reported here (structural tier had no other check that would catch a
  # node vanishing or appearing outright). Recurses into every matched
  # child, treating that child as the new bounding box for ITS OWN
  # children — the same per-level frame `check_level_sections` and
  # `rect_index` already use elsewhere in this file.
  def diff_node_geometry(expected_level, actual_level, path)
    expected_size = size_of(expected_level)
    actual_size = size_of(actual_level)

    diff_by_id(expected_level["children"], actual_level["children"],
               path) do |e_node, a_node, node_path|
      diffs = SIZE_FIELDS.flat_map do |key|
        diff_strict_dimension(e_node, a_node, node_path, key)
      end
      diffs.concat(diff_normalised_position(expected_size.merge(node: e_node),
                                            actual_size.merge(node: a_node),
                                            node_path))
      diffs.concat(diff_node_geometry(e_node, a_node, node_path))
    end
  end

  def size_of(level)
    { width: numeric_or_zero(level, "width"),
      height: numeric_or_zero(level, "height") }
  end

  def diff_strict_dimension(e_node, a_node, path, key)
    e, e_error = lenient_dimension(e_node, key, path, "expected")
    a, a_error = lenient_dimension(a_node, key, path, "actual")
    return [e_error, a_error].compact if e_error || a_error

    (e - a).abs > 1 ? ["#{path}/#{key}: expected #{e}, got #{a} (>1px)"] : []
  end

  # An ABSENT width/height reads as 0.0 here, exactly as the exact tier's
  # `diff_own_numeric` reads it through `numeric_or_zero`. `strict_numeric`
  # demanded the key, which made structural reject the very output the rest
  # of the suite requires: `spec/support/invariants/
  # omit_size_for_unsized_input.rb` says an unsized input node must NOT gain
  # a size, so elkrb OMITS those dimensions -- and deleting the zero
  # width/height from sizeless.json's golden passed exact and failed
  # structural, measured. Only absence is forgiven. A dimension that is
  # PRESENT still has to be a finite number, which is what keeps a NaN or a
  # string from slipping through as zero.
  #
  # `key?`, not `hash[key].nil?`. An explicit JSON `null` is PRESENT, and
  # reading it as absent let `{"width": null}` match a golden's `0` --
  # measured. Omission is the only thing forgiven, and elkrb really does
  # omit: laying out an unsized node gives a child whose keys are
  # ["id", "x", "y"], with no width entry at all, so nothing in the suite
  # needs a null to be tolerated.
  def lenient_dimension(hash, key, path, side)
    return [0.0, nil] unless hash.key?(key)

    strict_numeric(hash, key, path, side)
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
    rects = Rects.new(rect_index(actual_level), rect_index(expected_level))
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
    # (golden_comparator/shared.rb) is the same helper exact tier's
    # `diff_edges` calls, so the two tiers can't diverge on what counts
    # as a rewired edge.
    diffs = diff_edge_endpoints(edge, actual_edge, edge_path)

    sections = actual_edge["sections"] || []
    return diffs << "#{edge_path}: no sections in actual" if sections.empty?

    diffs.concat(check_edge_ends(edge, actual_edge, rects, edge_path))
    diffs.concat(check_section_continuity(sections, edge_path))
  end

  # `check_edge_ends` only anchors the FIRST section's start and the LAST
  # section's end to a node/port border -- a multi-section edge's INTERNAL
  # joints (one section's `endPoint` to the NEXT section's `startPoint`)
  # are never otherwise checked, so a layout bug that disconnected two
  # sections while leaving both outer anchors intact would pass silently.
  # Same 1px tolerance as `diff_strict_dimension` (this tier's own
  # coarseness), not `exact.rb`'s `diff_point` (1e-6, exact-tier strict and
  # wrong for structural).
  def check_section_continuity(sections, edge_path)
    diffs = if any_routing_refs?(sections)
              dangling_ref_diffs(sections, edge_path)
            else
              []
            end
    return diffs if sections.size < 2

    diffs + continuity_joints(sections).flat_map do |from_i, to_i|
      diff_strict_joint(sections[from_i]["endPoint"],
                        sections[to_i]["startPoint"],
                        "#{edge_path}/sections[#{from_i}->#{to_i}]")
    end
  end

  # `ref_joints` resolves every id in `outgoingSections`/`incomingSections`
  # THROUGH an id => index Hash, and a plain `filter_map { index[id] }`
  # silently drops any id the Hash does not carry -- exactly the shape a
  # dangling routing ref takes, so it vanished from both the joints list
  # AND any diagnostic, rather than being reported. This is the check that
  # keeps it from vanishing without a trace.
  def dangling_ref_diffs(sections, edge_path)
    index = sections.each_with_index.to_h { |sec, i| [sec["id"], i] }
    sections.each_with_index.flat_map do |sec, idx|
      ROUTING_REF_KEYS.flat_map do |ref_key|
        dangling_refs(sec, ref_key, index, edge_path, idx)
      end
    end
  end

  def dangling_refs(sec, ref_key, index, edge_path, idx)
    (sec[ref_key] || []).reject { |id| index.key?(id) }.map do |id|
      "#{edge_path}/sections[#{idx}]/#{ref_key}: references unknown " \
        "section id #{id.inspect}"
    end
  end

  # Plain array adjacency (`sections[i]` feeds `sections[i + 1]`) assumes
  # every edge routes as ONE linear chain -- untrue the moment a section
  # splits into two branches or two branches rejoin into one, where
  # `sections[i + 1]` can be a sibling branch that never connects to
  # `sections[i]` at all. Comparing a valid split/rejoin graph against
  # itself under plain adjacency produced a false continuity break between
  # two such siblings -- measured, including for the LEAF end of a branch
  # (it carries no `outgoingSections` of its own, so falling back to
  # adjacency section-by-section rather than edge-by-edge still wired it
  # to its array neighbour). Once ANY section on this edge carries a
  # routing ref, the WHOLE edge is treated as ref-described and joints
  # come from EITHER direction's refs (`outgoingSections` or
  # `incomingSections` -- see `ref_joints`'s own comment); plain adjacency
  # is the fallback only when NO section anywhere on the edge carries
  # either ref, which is
  # exactly the single unbranched chain elkrb emits today (and is
  # order-for-order identical to the old behaviour there).
  def continuity_joints(sections)
    return adjacency_joints(sections) unless any_routing_refs?(sections)

    ref_joints(sections)
  end

  # The ref-described half of `continuity_joints` -- see its own comment
  # above for why this only runs once ANY section on the edge carries a
  # routing ref. Reads BOTH `outgoingSections` and `incomingSections`:
  # `any_routing_refs?` treats either direction as ref-described, so a
  # section naming only its PREDECESSOR must still produce a joint --
  # reading `outgoingSections` alone silently drops that edge's
  # continuity check entirely. `.uniq` collapses a joint named from both
  # directions (the common real-elkjs shape) back to one.
  def ref_joints(sections)
    index = sections.each_with_index.to_h { |sec, i| [sec["id"], i] }
    outgoing = direction_joints(sections, index, "outgoingSections") do |i, j|
      [i, j]
    end
    incoming = direction_joints(sections, index, "incomingSections") do |i, j|
      [j, i]
    end
    (outgoing + incoming).uniq
  end

  # One direction's half of `ref_joints`: every id `sections[i]` names
  # under `ref_key`, resolved through `index` and dropped when it names no
  # section on this edge (a dangling ref -- `dangling_ref_diffs`'s
  # violation to report, not this method's to silently include or crash
  # on). The block decides the joint's [from, to] order, since outgoing
  # and incoming name the same neighbour in opposite roles.
  def direction_joints(sections, index, ref_key)
    sections.each_index.flat_map do |i|
      (sections[i][ref_key] || [])
        .filter_map { |id| index[id] }.map { |j| yield(i, j) }
    end
  end

  def any_routing_refs?(sections)
    sections.any? do |sec|
      !(sec["outgoingSections"] || []).empty? ||
        !(sec["incomingSections"] || []).empty?
    end
  end

  def adjacency_joints(sections)
    (0...(sections.size - 1)).map { |i| [i, i + 1] }
  end

  def diff_strict_joint(end_point, start_point, path)
    return ["#{path}: missing"] unless end_point && start_point

    %w[x y].flat_map do |key|
      diff_joint_axis(end_point, start_point, path, key)
    end
  end

  def diff_joint_axis(end_point, start_point, path, key)
    e, e_error = strict_numeric(end_point, key, path, "endPoint")
    a, a_error = strict_numeric(start_point, key, path, "startPoint")
    return [e_error, a_error].compact if e_error || a_error
    return [] if (e - a).abs <= 1

    ["#{path}/#{key}: endPoint #{e}, next startPoint #{a} (>1px)"]
  end

  # Where `incomingShape`/`outgoingShape` are populated is stated once, in
  # `diff_edge_endpoints`'s own comment (golden_comparator/shared.rb).
  # Without one, which node the point SHOULD clip to isn't just
  # unlabelled, it isn't even reliably source-then-target: `random3`'s
  # committed golden anchors both this edge's start AND end on its SOURCE
  # node's border, never the target's (verified by running
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
  # `diff_edge_endpoints` has already rejected a shape naming
  # anything other than this edge's own endpoints — otherwise the
  # point would be measured against whatever rectangle elkrb chose to
  # name, which is no check at all.
  def check_edge_ends(edge, actual_edge, rects, edge_path)
    anchors = edge_anchors(edge, actual_edge)
    ids = anchors.map do |_name, anchor|
      anchored_candidates(actual_edge, rects, anchor.golden)
    end
    shape_orientation_diffs(anchors, ids, edge_path) +
      anchors.zip(ids).flat_map do |(name, anchor), candidates|
        point_near_any_reference(anchor.point, rects.actual,
                                 anchor.shape ? [anchor.shape] : candidates,
                                 "#{edge_path}/#{name}")
      end
  end

  def edge_anchors(edge, actual_edge)
    actual_sections = actual_edge["sections"]
    golden_sections = edge["sections"] || []
    EDGE_ENDS.map do |name, pick, point_key, shape_key|
      section = actual_sections.public_send(pick)
      golden = golden_sections.public_send(pick)&.fetch(point_key, nil)
      [name, Anchor.new(section[point_key], section[shape_key], golden)]
    end
  end

  # An annotation names the rectangle the point is then measured against,
  # and the ACTUAL result used to be trusted with that unchallenged. That
  # is a way back into the collapsed-section hole: adding
  # `outgoingShape: "a"` to force_tri's collapsed section made the end
  # point measure against the SOURCE and pass -- measured.
  # `diff_section_shapes` (golden_comparator/shared.rb) cannot catch it,
  # because it only rejects a shape naming a NON-endpoint and the source
  # IS one, and because an unannotated golden lets any annotation appear.
  #
  # Checked as a PAIR in either orientation, never end by end.
  # `diff_section_shapes`'s own comment documents ELK reversing a
  # section's own shapes for cycle breaking without rewiring the edge, and
  # an end-by-end version of THIS method rejected exactly that: swapping
  # the start/end points together with their shapes produced two
  # differences -- measured. One rule, stated in shared.rb, disagreed with
  # by an earlier version of this method -- that mismatch is the defect
  # this pair of files now guards against.
  #
  # A reversal needs BOTH ends annotated. Allowing it with one end unnamed
  # let the collapsed section back in by naming only its outgoing shape,
  # since the unnamed end then matched anything.
  def shape_orientation_diffs(anchors, ids, edge_path)
    shapes = anchors.map { |_name, anchor| anchor.shape }
    return [] if shapes_anchored?(shapes, ids)

    ["#{edge_path}: section shapes #{shapes.inspect} are not where the " \
     "golden anchors this edge (#{ids.inspect})"]
  end

  def shapes_anchored?(shapes, ids)
    return true if shapes.compact.empty?
    return true if shapes_fit?(shapes, ids)

    shapes.none?(&:nil?) && shapes_fit?(shapes, ids.reverse)
  end

  def shapes_fit?(shapes, ids)
    shapes.zip(ids).all? do |shape, candidates|
      shape.nil? || candidates.include?(shape)
    end
  end

  # Narrows the either-endpoint list to the endpoints the GOLDEN's own
  # point is already sitting on.
  #
  # The full list used to be handed straight through, and "near EITHER
  # endpoint" is satisfied by a section that never leaves its source:
  # setting force_tri's endPoint equal to its startPoint passed the
  # structural tier with the edge reaching nothing -- measured. Rejecting
  # a degenerate section outright is NOT the fix, because radial_star5's
  # four committed goldens are legitimately degenerate (startPoint ==
  # endPoint on every one, measured), so such a rule would reject real
  # elkjs output. What the golden decides here is only WHICH node a point
  # belongs to; how far the point may drift is still the border check's
  # call, so this adds no tolerance of its own.
  #
  # Falls back to the full candidate list whenever the golden's point is
  # on neither endpoint, so this can never be stricter than the golden
  # itself supports.
  def anchored_candidates(actual_edge, rects, golden)
    candidates = endpoint_candidates(actual_edge)
    return candidates unless numeric_point?(golden)

    anchored = candidates.select do |id|
      rect = rects.expected[id]
      rect && point_on_border(golden, rect, "").empty?
    end
    anchored.empty? ? candidates : anchored
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
  def diff_layer_membership(expected, actual, path = "root", inherited = nil)
    direction = expected.dig("layoutOptions", "elk.direction") || inherited
    diffs = diff_layer_grouping(expected, actual, path, direction)
    diffs.concat(diff_layer_children(expected, actual, path, direction))
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

  # Direction is INHERITED. ELK applies a root's direction to every nested
  # level that does not pin its own, and real elkjs output for a DOWN root
  # omits a local direction on the child. Reading only the level's own
  # options defaulted such a child to RIGHT, so it was grouped on x: two
  # collapsed y-layers with a rerouted section still compared equal.
  def layer_axes(level, inherited = nil)
    direction = level.dig("layoutOptions", "elk.direction") || inherited ||
      "RIGHT"
    axis = %w[UP DOWN].include?(direction) ? :y : :x
    [axis, axis == :y ? :x : :y]
  end

  # Only the LAYER message is skipped for a non-layered level. The child
  # recursion in `diff_layer_children` is not, and must not be folded in
  # here as an early return -- a non-layered root still has to reach a
  # mismatching compound child.
  def diff_layer_grouping(expected, actual, path, inherited = nil)
    return [] unless layered?(expected)

    axis, cross_axis = layer_axes(expected, inherited)
    expected_layers = group_by_layer(expected["children"] || [], axis,
                                     cross_axis)
    actual_layers = group_by_layer(actual["children"] || [], axis, cross_axis)
    return [] if expected_layers == actual_layers

    ["#{path}: layer membership/order: " \
     "expected #{expected_layers.inspect}, got #{actual_layers.inspect}"]
  end

  def diff_layer_children(expected, actual, path, inherited = nil)
    actual_children = index_by_id(actual["children"] || [])
    index_by_id(expected["children"] || []).flat_map do |id, child|
      match = actual_children[id]
      next [] unless match

      diff_layer_membership(child, match, "#{path}/children/#{id}", inherited)
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
end
