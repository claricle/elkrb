# frozen_string_literal: true

RSpec.describe "elkjs golden parity" do
  # Shared by both example bodies below: runs the matcher, then reports via
  # `pending`/`expect` exactly like a normal example would if this were
  # inlined. `result` is passed in rather than computed here because the two
  # callers build it differently (a plain layout call vs. one that rescues
  # into an error hash).
  #
  # The layout call and the matcher's own execution (reading
  # golden_expected, running GoldenComparator) are NOT inside pending --
  # both happen before pending is called, so a crash in EITHER is a real
  # failure.
  def assert_golden_case(kase, result)
    matcher = match_elkjs_golden(kase[:name], **matcher_kwargs(kase))
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    # Guard the call, not just the argument: RSpec's `pending(nil)` still
    # marks the example pending, so a case whose `pending:` reason has been
    # cleared to nil (the way this table is meant to "activate" a fixed
    # case) would report a passing assertion as FIXED instead of passing.
    pending kase[:pending] if kase[:pending]
    expect(matched).to be(true), message
  end

  describe "#assert_golden_case's pending guard" do
    # Verified by hand (RSpec 3.13.6): `pending(nil)` still marks the
    # example pending, so a PASSING assertion under it reports FIXED
    # instead of passing. The table in golden_cases.rb is meant to
    # "activate" a case by clearing its `pending:` reason to nil once the
    # underlying bug is fixed -- that workflow only works if
    # `assert_golden_case` skips calling `pending` at all in that case,
    # rather than calling `pending(nil)`.
    it "does not call pending when kase[:pending] is nil" do
      matcher = double("matcher", matches?: true, failure_message: nil)
      allow(self).to receive(:match_elkjs_golden).and_return(matcher)
      expect(self).not_to receive(:pending)

      assert_golden_case({ name: "probe", tier: :exact, pending: nil }, {})
    end

    it "calls pending with the reason when kase[:pending] is set" do
      matcher = double("matcher", matches?: true, failure_message: nil)
      allow(self).to receive(:match_elkjs_golden).and_return(matcher)
      expect(self).to receive(:pending).with("still broken")

      assert_golden_case(
        { name: "probe", tier: :exact, pending: "still broken" }, {}
      )
    end
  end

  # One example per comparison case, generated from the shared table in
  # spec/support/golden_cases.rb.
  GoldenCases::COMPARISON_CASES.each do |kase|
    it kase[:name] do
      input = golden_input(kase[:name])
      result = Elkrb.layout(input[:graph], input[:options])
      assert_golden_case(kase, result)
    end
  end

  # Not in the loop above: this is the sole error case, so its body differs
  # -- elkrb is expected to raise rather than lay the graph out, and the
  # rescue turns that into the error hash the golden holds.
  it GoldenCases::ERROR_CASE[:name] do
    kase = GoldenCases::ERROR_CASE
    input = golden_input(kase[:name])
    result =
      begin
        Elkrb.layout(input[:graph], input[:options])
      rescue Elkrb::UnsupportedConfigurationException => e
        { "error" => e.message }
      end
    assert_golden_case(kase, result)
  end
end
