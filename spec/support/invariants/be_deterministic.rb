# spec/support/invariants/be_deterministic.rb
# frozen_string_literal: true

require_relative "../invariants"

RSpec::Matchers.define :be_deterministic do
  # Required for RSpec to accept block-expectation syntax
  # (`expect { ... }.to be_deterministic`) at all — without it, RSpec
  # raises "not designed to support block expectations" before `match`
  # ever runs. The caller's block must build fresh input for each call
  # (re-parse a JSON string, `Marshal.load(Marshal.dump(hash))`, etc.) —
  # this matcher runs it twice and only compares the output.
  supports_block_expectations

  match do |block|
    first = block.call.to_json
    second = block.call.to_json
    @first, @second = first, second
    first == second
  end

  failure_message { "two runs differed:\n#{@first}\n---\n#{@second}" }
end

INVARIANTS << :be_deterministic
