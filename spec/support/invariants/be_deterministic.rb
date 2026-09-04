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

  # Compares the MODELS, and their serialized form, and requires both to
  # agree. Comparing only `to_json` makes this matcher exactly as strong as
  # the JSON mapping: an attribute the model carries but the mapping omits is
  # invisible here, so a layout that varied in it would still be called
  # deterministic. Measured on this branch, every scalar attribute of Graph,
  # Node, Edge, Port, Label and EdgeSection does reach JSON today -- so this
  # is closing the class, not a live instance, and it stays closed when
  # someone adds an attribute and forgets the mapping.
  #
  # lutaml gives these classes VALUE equality, so `==` compares content rather
  # than identity. That is what makes the model comparison meaningful here.
  match do |block|
    first_model = block.call
    second_model = block.call
    @first = first_model.to_json
    @second = second_model.to_json

    @models_equal = first_model == second_model
    @json_equal = @first == @second
    @models_equal && @json_equal
  end

  failure_message do
    if @models_equal && !@json_equal
      "the models compared equal but serialized differently:\n" \
        "#{@first}\n---\n#{@second}"
    elsif !@models_equal && @json_equal
      # The dangerous direction: the difference exists but the JSON hides it.
      "two runs differed in the MODEL while serializing identically, so the " \
        "difference is in an attribute the JSON mapping omits:\n#{@first}"
    else
      "two runs differed:\n#{@first}\n---\n#{@second}"
    end
  end
end

INVARIANTS << :be_deterministic
