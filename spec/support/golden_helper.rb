# spec/support/golden_helper.rb
# frozen_string_literal: true

require_relative "golden_comparator"

module GoldenHelper
  DEFAULT_DIR = File.join(__dir__, "..", "fixtures", "golden")
  DEFAULT_FIELDS = %i[nodes sections labels ports graph].freeze

  def golden_input(name, dir: DEFAULT_DIR)
    data = JSON.parse(File.read(File.join(dir, "inputs", "#{name}.json")))
    { graph: data.fetch("graph"), options: data.fetch("options", {}) }
  end

  def golden_expected(name, dir: DEFAULT_DIR)
    JSON.parse(File.read(File.join(dir, "expected", "#{name}.json")))
  end
end

RSpec.configure { |c| c.include GoldenHelper }

RSpec::Matchers.define :match_elkjs_golden do |
  name,
  tier:,
  fields: GoldenHelper::DEFAULT_FIELDS,
  dir: GoldenHelper::DEFAULT_DIR|
  match do |actual|
    expected = golden_expected(name, dir: dir)
    comparable_actual =
      if GoldenComparator.error_hash?(actual)
        actual
      else
        GoldenComparator.to_comparable(actual)
      end

    @diffs =
      if GoldenComparator.error_hash?(expected) ||
          GoldenComparator.error_hash?(comparable_actual)
        error_diffs(expected, comparable_actual, name)
      else
        case tier
        when :exact
          GoldenComparator.diff_exact(expected, comparable_actual, fields)
        when :structural
          GoldenComparator.diff_structural(expected, comparable_actual)
        when :smoke
          GoldenComparator.diff_smoke(expected, comparable_actual)
        else
          raise ArgumentError, "unknown tier: #{tier.inspect}"
        end
      end

    @diffs.empty?
  end

  define_method(:error_diffs) do |expected, actual, case_name = nil|
    expected_error = GoldenComparator.error_hash?(expected)
    actual_error = GoldenComparator.error_hash?(actual)

    if expected_error && actual_error
      expected_message = GoldenComparator.error_message(expected)
      actual_message = GoldenComparator.error_message(actual)
      # The case's OWN statement of what elkrb must report, when it has one.
      expected_pattern = GoldenCases.expected_error_for(case_name)
      if GoldenComparator.same_error_condition?(expected_message,
                                                actual_message,
                                                expected: expected_pattern)
        return []
      end

      return ["expected an error naming the same condition as " \
              "#{expected_message.inspect}, got #{actual_message.inspect}"]
    end

    if expected_error
      ["expected an elkjs-style error, got a successful layout"]
    else
      ["unexpected error: #{GoldenComparator.error_message(actual)}"]
    end
  end

  failure_message do |_actual|
    shown = [@diffs.size, 10].min
    "#{name} (tier: #{tier}) — first #{shown} of #{@diffs.size} " \
    "differences:\n" + @diffs.first(10).join("\n")
  end
end
