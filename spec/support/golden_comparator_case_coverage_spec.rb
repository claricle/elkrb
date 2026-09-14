# spec/support/golden_comparator_case_coverage_spec.rb
# frozen_string_literal: true

# Split out of golden_helper_spec.rb (see golden_comparator_pinning_spec.rb
# for the split rationale). Both describe blocks here are driven by the
# same GoldenCases::TIER_BY_CASE table and are a matched pair: the first
# proves the comparator accepts a correct copy, the second proves it can
# also reject a wrong one -- keep them together.
require_relative "golden_helper"

RSpec.describe "every committed golden self-matches at its assigned tier" do
  # Driven by the same shared table golden_spec.rb generates its examples
  # from, so a case can never have an example there and no self-match here
  # (`hyperedge` is the sole error-case golden and is excluded from that
  # table — its "match" is a different code path in the matcher, exercised
  # in golden_spec.rb directly). A golden that fails this only means the
  # COMPARATOR disagrees with reality, not that elkrb is wrong about
  # anything — this caught a real bug once already (structural tier's
  # port-anchor check rejected `ports_simple`'s own real elkjs data before
  # that check was fixed to use the port's border instead of its centre).
  GoldenCases::TIER_BY_CASE.each do |name, tier|
    it "#{name} (#{tier})" do
      expected = golden_expected(name)
      diffs =
        case tier
        when :exact then GoldenComparator.diff_exact(expected, expected,
                                                     %i[nodes sections labels
                                                        ports graph])
        when :structural then GoldenComparator.diff_structural(expected,
                                                               expected)
        end

      expect(diffs).to be_empty
    end
  end
end

RSpec.describe "every committed golden's perturbed copy is caught" do
  # The self-match examples above prove the comparator accepts a CORRECT
  # copy; they are tautological about whether it can also REJECT a wrong
  # one (comparing an object with itself proves nothing about that). One
  # mutation per case, chosen to exercise the property most relevant to
  # its tier: exact tier gets a node shifted past the 1e-6 tolerance;
  # structural tier gets an edge deleted if the case has one (exercises
  # the symmetric "missing from actual" check), otherwise a node shifted
  # past `POSITION_TOLERANCE_FRACTION` of the graph's own size (exercises
  # `diff_node_geometry` on an edge-less case like `rect6`/
  # `spore_overlap4`).
  GoldenCases::TIER_BY_CASE.each do |name, tier|
    it "#{name} (#{tier})" do
      expected = golden_expected(name)
      mutated = Marshal.load(Marshal.dump(expected))

      case tier
      when :exact
        mutated["children"].first["x"] =
          numeric_or_zero(mutated["children"].first, "x") + 2.0
        diffs = GoldenComparator.diff_exact(expected, mutated,
                                            %i[nodes sections labels
                                               ports graph])
      when :structural
        if mutated["edges"]&.any?
          mutated["edges"].shift
        else
          node = mutated["children"].first
          node["x"] =
            numeric_or_zero(node,
                            "x") + (numeric_or_zero(mutated, "width") * 0.5)
        end
        diffs = GoldenComparator.diff_structural(expected, mutated)
      end

      expect(diffs).not_to be_empty
    end
  end

  def numeric_or_zero(hash, key)
    (hash[key] || 0.0).to_f
  end
end
