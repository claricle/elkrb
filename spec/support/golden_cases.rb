# spec/support/golden_cases.rb
# frozen_string_literal: true

# The one place that says which elkjs golden cases exist, what tier each is
# compared at, and why each is still pending. Every consumer derives from
# this table rather than keeping a copy: golden_spec.rb generates its
# examples from it, golden_helper_spec.rb drives its self-match and
# perturbation blocks from it, and its fixture-coverage example asserts the
# table names exactly the committed inputs. A case added to one consumer and
# not the others is therefore not expressible.
#
# The reasons are locals, not constants, so the table below is the only
# thing this file exposes and nothing can reach past it to a single reason.
module GoldenCases
  rc2_2_algorithm_pin =
    "RC2.2: graph-level elk.algorithm pin is never read, " \
    "LayoutEngine always defaults to layered"
  rc5_parent_sized_first =
    "RC5: hierarchical layout sizes the parent before its children"
  rc7_direction_and_layer_gap =
    "RC7: layered ignores elk.direction and uses a 60px layer gap " \
    "instead of ELK's RIGHT/20 defaults"
  rc7_direction_unread =
    "RC7: elk.direction is not read by the layered algorithm"
  rc7_branch_routing =
    "RC7: layered has no crossing minimisation or dummy-node routing " \
    "for branching graphs"
  rc7_long_edge_routing =
    "RC7: layered has no crossing minimisation or dummy-node routing " \
    "for long edges"
  rc7_cycle_breaker =
    "RC7: cycle breaker permanently reverses edges and layered lacks " \
    "crossing minimisation"
  rc7_spacing_unread =
    "RC7: elk.spacing.nodeNode and " \
    "elk.layered.spacing.nodeNodeBetweenLayers are not read"
  rc7_hyperedge_misrouted =
    "RC7: layered silently mis-routes hyperedges instead of raising " \
    "like elkjs"
  rc8_absolute_node_labels =
    "RC8: node labels are absolute, not owner-relative"
  rc8_label_placement_unread =
    "RC8: ELK node label placement keys are never read"

  # The 29 cases whose golden is a laid-out graph, compared field by field.
  # `hyperedge` is deliberately absent -- its golden is an error hash, it
  # goes through a different code path in the matcher, and it lives in
  # ERROR_CASE below. That is the whole of the 29-versus-30 asymmetry.
  COMPARISON_CASES = [
    { name: "chain2", tier: :exact, pending: rc7_direction_and_layer_gap },
    { name: "chain3", tier: :exact, pending: rc7_direction_and_layer_gap },
    { name: "fan_out", tier: :structural, pending: rc7_branch_routing },
    { name: "fan_in", tier: :structural, pending: rc7_branch_routing },
    { name: "diamond", tier: :structural, pending: rc7_branch_routing },
    { name: "cycle3", tier: :structural, pending: rc7_cycle_breaker },
    { name: "self_loop", tier: :structural,
      pending: rc7_direction_and_layer_gap },
    { name: "long_edge", tier: :structural,
      pending: rc7_long_edge_routing },
    { name: "ports_simple", tier: :structural,
      pending: rc7_direction_and_layer_gap },
    { name: "labeled_node", tier: :exact,
      pending: rc8_absolute_node_labels },
    { name: "labeled_node_placement", tier: :exact,
      pending: rc8_label_placement_unread },
    { name: "compound_chain", tier: :exact,
      pending: rc5_parent_sized_first },
    { name: "compound_nested", tier: :structural,
      pending: rc5_parent_sized_first },
    { name: "direction_down", tier: :exact,
      pending: rc7_direction_unread },
    { name: "spacing_override", tier: :exact,
      pending: rc7_spacing_unread },
    { name: "sizeless", tier: :exact, pending: rc7_direction_and_layer_gap },
    { name: "two_components", tier: :structural,
      pending: rc7_direction_and_layer_gap },
    { name: "box3", tier: :exact, pending: rc2_2_algorithm_pin },
    { name: "box_mixed", tier: :exact, pending: rc2_2_algorithm_pin },
    { name: "box_aspect", tier: :exact, pending: rc2_2_algorithm_pin },
    { name: "fixed2", tier: :exact, pending: rc2_2_algorithm_pin },
    { name: "mrtree3", tier: :exact, pending: rc2_2_algorithm_pin },
    { name: "mrtree7", tier: :structural, pending: rc2_2_algorithm_pin },
    { name: "radial_star5", tier: :structural,
      pending: rc2_2_algorithm_pin },
    { name: "rect6", tier: :structural, pending: rc2_2_algorithm_pin },
    { name: "force_tri", tier: :structural, pending: rc2_2_algorithm_pin },
    { name: "stress_path4", tier: :structural,
      pending: rc2_2_algorithm_pin },
    { name: "random3", tier: :structural, pending: rc2_2_algorithm_pin },
    { name: "spore_overlap4", tier: :structural,
      pending: rc2_2_algorithm_pin },
  ].each(&:freeze).freeze

  # The sole error-case golden: elkjs raises rather than laying the graph
  # out, so its expected file is `{"error": ...}` and matching it compares
  # messages instead of geometry.
  # `expect_error` states the condition ELKRB must report, as a pattern its
  # own message has to match. It is deliberately not derived from elkjs's
  # sentence: the two implementations word rejections differently, and a
  # substring taken from elkjs proved to be a poor proxy. It accepted the
  # OPPOSITE condition -- a message reading "simple edge accepted; endpoint
  # lookup failed" contains "simple" -- while rejecting the settled correct
  # message from card 12, "layered does not support hyperedges (edge e1)".
  ERROR_CASE = { name: "hyperedge", tier: :structural,
                 expect_error: /hyperedge/i,
                 pending: rc7_hyperedge_misrouted }.freeze

  TIER_BY_CASE = COMPARISON_CASES.to_h { |c| [c[:name], c[:tier]] }.freeze

  # nil for every case that does not state one, which is all of them but the
  # error case.
  def self.expected_error_for(case_name)
    return nil unless case_name

    (COMPARISON_CASES + [ERROR_CASE])
      .find { |c| c[:name] == case_name }&.fetch(:expect_error, nil)
  end

  ALL_NAMES =
    COMPARISON_CASES.map { |c| c[:name] }.push(ERROR_CASE[:name]).freeze
end
