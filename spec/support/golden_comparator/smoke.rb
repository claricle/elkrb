# spec/support/golden_comparator/smoke.rb
# frozen_string_literal: true

require_relative "shared"

# The `:smoke` tier: same node ids present, every node's own coordinates
# finite. The smallest of the three tier files, and fully self-contained —
# it does not call into shared.rb's id-matching or edge-endpoint helpers.
module GoldenComparator
  module_function

  # smoke tier: same node ids present (order-independent), every node's
  # OWN position (x/y) present and finite — matches the card's tier
  # definition literally ("same node ids, finite coordinates"); the root's
  # own x/y is exempt (see `have_finite_coordinates`'s comment: elkrb never
  # assigns the root a position, confirmed empirically, so requiring it
  # here would fail every graph); node dimensions and sections/labels/
  # ports finiteness are `have_finite_coordinates`'s job (Task 3), not this
  # tier's.
  def diff_smoke(expected, actual)
    expected_ids = graph_ids(expected)
    actual_ids = graph_ids(actual)
    diffs = []
    if expected_ids.sort != actual_ids.sort
      diffs << "node ids differ: expected #{expected_ids.sort}, " \
               "got #{actual_ids.sort}"
    end
    diffs.concat(collect_non_finite_positions(actual))
    diffs
  end

  # The root's OWN id, then every descendant's. `collect_ids` starts at
  # `children`, so the root's id reached neither list and renaming ONLY
  # the root left the two sorted id lists identical -- measured on
  # force_tri, which the smoke tier then matched. "Same node ids present"
  # is a claim about every node, and the root is one. What the root is
  # exempt from is carrying a POSITION, which is a separate check.
  def graph_ids(level)
    [level["id"]].compact + collect_ids(level)
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
