# frozen_string_literal: true

RSpec.describe "elkjs golden parity" do
  # One example per comparison case, generated from the shared table in
  # spec/support/golden_cases.rb.
  #
  # The layout call and the matcher's own execution (reading
  # golden_expected, running GoldenComparator) are NOT inside pending --
  # both happen before pending is called, so a crash in EITHER is a real
  # failure.
  GoldenCases::COMPARISON_CASES.each do |kase|
    it kase[:name] do
      input = golden_input(kase[:name])
      result = Elkrb.layout(input[:graph], input[:options])
      matcher = match_elkjs_golden(kase[:name], tier: kase[:tier])
      matched = matcher.matches?(result)
      message = matcher.failure_message unless matched

      pending kase[:pending]
      expect(matched).to be(true), message
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
    matcher = match_elkjs_golden(kase[:name], tier: kase[:tier])
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending kase[:pending]
    expect(matched).to be(true), message
  end
end
