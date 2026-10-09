# spec/support/golden_cases.rb
# frozen_string_literal: true

# The one place that says which elkjs golden cases exist, what tier each is
# compared at, and why each is still pending. Every consumer derives from
# this table rather than keeping a copy: golden_spec.rb generates its
# examples from it, golden_comparator_case_coverage_spec.rb drives its
# self-match and perturbation blocks from it, and
# golden_fixture_manifest_spec.rb's fixture-coverage example asserts the
# table names exactly the committed inputs. A case added to one consumer and
# not the others is therefore not expressible.
#
# The reasons are locals, not constants, so the table below is the only
# thing this file exposes and nothing can reach past it to a single reason.
module GoldenCases
  # The 29 cases whose golden is a laid-out graph, compared field by field.
  # `hyperedge` is deliberately absent -- its golden is an error hash, it
  # goes through a different code path in the matcher, and it lives in
  # ERROR_CASE below. That is the whole of the 29-versus-30 asymmetry.
  COMPARISON_CASES = [
    { name: "chain2", tier: :exact, fields: %i[nodes graph], pending: nil },
    { name: "chain3", tier: :exact,
      fields: %i[nodes graph sections], pending: nil },
    { name: "fan_out", tier: :structural, pending: nil },
    { name: "fan_in", tier: :structural, pending: nil },
    { name: "diamond", tier: :structural, pending: nil },
    { name: "cycle3", tier: :structural,
      fields: %i[nodes sections], pending: nil },
    { name: "self_loop", tier: :structural, fields: %i[nodes sections],
      pending: nil },
    { name: "long_edge", tier: :structural, fields: %i[nodes sections],
      pending: nil },
    { name: "ports_simple", tier: :structural,
      fields: %i[nodes sections], pending: nil },
    { name: "labeled_node", tier: :exact, fields: %i[labels], pending: nil },
    { name: "labeled_node_placement", tier: :exact, fields: %i[labels],
      pending: nil },
    { name: "compound_chain", tier: :exact,
      fields: %i[nodes graph sections], pending: nil },
    { name: "compound_nested", tier: :structural, fields: %i[nodes graph],
      pending: nil },
    { name: "direction_down", tier: :exact, fields: %i[nodes graph],
      pending: nil },
    { name: "spacing_override", tier: :exact, fields: %i[nodes],
      pending: nil },
    { name: "sizeless", tier: :exact, pending: nil },
    { name: "two_components", tier: :structural, pending: nil },
    { name: "box3", tier: :exact, pending: nil },
    { name: "box_mixed", tier: :exact, pending: nil },
    { name: "box_aspect", tier: :exact, pending: nil },
    { name: "fixed2", tier: :exact, pending: nil },
    { name: "mrtree3", tier: :exact, pending: nil },
    { name: "mrtree7", tier: :structural, pending: nil },
    { name: "radial_star5", tier: :structural, pending: nil },
    { name: "rect6", tier: :structural, pending: nil },
    { name: "force_tri", tier: :structural, fields: %i[nodes sections],
      pending: nil },
    { name: "stress_path4", tier: :structural, pending: nil },
    { name: "random3", tier: :structural, pending: nil },
    { name: "spore_overlap4", tier: :structural, pending: nil },
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
                 # Names the REJECTION, not just the subject. `/hyperedge/i`
                 # alone was still satisfied by "hyperedge accepted; endpoint
                 # lookup failed" -- the exact inversion this pattern exists
                 # to catch. Matching the settled wording from card 12,
                 # "layered does not support hyperedges (edge e1)", is
                 # deliberately narrow: a reworded message SHOULD fail here
                 # and be updated on purpose.
                 expect_error: /does not support hyperedge/i,
                 pending: nil }.freeze

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
