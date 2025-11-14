#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"

# Generator for validation report in AsciiDoc format
class ValidationReportGenerator
  def generate
    report_data = load_report
    adoc = generate_adoc(report_data)

    FileUtils.mkdir_p("docs")
    File.write("docs/VALIDATION_REPORT.adoc", adoc)
    puts "Validation report generated: docs/VALIDATION_REPORT.adoc"
  end

  private

  def load_report
    path = "spec/cross_validation/validation_report.json"
    unless File.exist?(path)
      puts "Error: validation_report.json not found"
      puts "Please run validation first: rake validate:run"
      exit 1
    end

    JSON.parse(File.read(path))
  end

  def generate_adoc(data)
    <<~ADOC
      = ElkRb Cross-Validation Report
      :toc:
      :toclevels: 2

      == Overview

      This report documents the results of cross-validation testing between ElkRb
      and reference implementations (elkjs and Java ELK).

      **Validation Date**: #{format_timestamp(data['timestamp'])}

      == Summary

      [cols="2,1", options="header"]
      |===
      |Metric |Value

      |Total Tests |#{data['summary']['total_tests']}
      |Passed |#{data['summary']['total_passed']}
      |Failed |#{data['summary']['total_failed']}
      |Pass Rate |#{data['summary']['pass_rate']}%
      |===

      == elkjs Compatibility

      #{generate_source_section(data['elkjs'], 'elkjs')}

      == Java ELK Compatibility

      #{generate_source_section(data['java_elk'], 'Java ELK')}

      == Test Categories

      #{generate_categories_section(data)}

      == Conclusion

      #{generate_conclusion(data)}

      == Next Steps

      #{generate_next_steps(data)}
    ADOC
  end

  def format_timestamp(timestamp)
    require "time"
    Time.parse(timestamp).strftime("%Y-%m-%d %H:%M:%S UTC")
  rescue StandardError
    timestamp
  end

  def generate_source_section(source_data, name)
    total = source_data["passed"] + source_data["failed"]
    return "No #{name} tests were run." if total.zero?

    pass_rate = ((source_data["passed"].to_f / total) * 100).round(2)

    <<~SECTION
      **Tests Run**: #{total}

      **Results**:

      * Passed: #{source_data['passed']}
      * Failed: #{source_data['failed']}
      * Pass Rate: #{pass_rate}%

      #{generate_failures_section(source_data['errors'])}
    SECTION
  end

  def generate_failures_section(errors)
    return "All tests passed! ✅" if errors.empty?

    failures = errors.map do |error|
      "* `#{error['test_id']}`: #{error['error']}"
    end.join("\n")

    <<~FAILURES
      **Failures**:

      #{failures}
    FAILURES
  end

  def generate_categories_section(data)
    # Extract unique categories from both test suites
    categories = {}

    [data["elkjs"], data["java_elk"]].each do |source|
      next unless source && source["errors"]

      source["errors"].each do |error|
        test_id = error["test_id"]
        # Extract category from test_id (format: source_category_name)
        parts = test_id.split("_")
        category = parts[1] if parts.length > 1
        categories[category] ||= { passed: 0, failed: 0 }
        categories[category][:failed] += 1
      end
    end

    if categories.empty?
      "All test categories passed successfully."
    else
      rows = categories.map do |category, stats|
        "|#{category} |#{stats[:passed]} |#{stats[:failed]}"
      end.join("\n")

      <<~CATEGORIES
        [cols="2,1,1", options="header"]
        |===
        |Category |Passed |Failed

        #{rows}
        |===
      CATEGORIES
    end
  end

  def generate_conclusion(data)
    pass_rate = data["summary"]["pass_rate"]

    if pass_rate == 100
      "ElkRb has achieved **100% compatibility** with reference implementations! ✅"
    elsif pass_rate >= 95
      "ElkRb has achieved **#{pass_rate}% compatibility** with reference " \
        "implementations. Minor issues to be addressed."
    elsif pass_rate >= 80
      "ElkRb has achieved **#{pass_rate}% compatibility** with reference " \
        "implementations. Good progress with some remaining issues."
    else
      "ElkRb compatibility at **#{pass_rate}%**. Additional work needed to " \
        "reach full compatibility."
    end
  end

  def generate_next_steps(data)
    pass_rate = data["summary"]["pass_rate"]
    total_failed = data["summary"]["total_failed"]

    if pass_rate == 100
      <<~STEPS
        * Continue maintaining compatibility through regular validation runs
        * Add more complex test cases to ensure edge cases are covered
        * Consider performance benchmarking against reference implementations
      STEPS
    elsif total_failed > 0
      <<~STEPS
        * Address #{total_failed} failing test case#{'s' if total_failed > 1}
        * Review error messages and stack traces in validation_report.json
        * Prioritize fixes based on test category and impact
        * Re-run validation after fixes: `rake validate:all`
      STEPS
    else
      <<~STEPS
        * Import additional test cases from elkjs and Java ELK
        * Expand test coverage for edge cases
        * Continue development of remaining features
      STEPS
    end
  end
end

# Run if executed directly
ValidationReportGenerator.new.generate if __FILE__ == $PROGRAM_NAME
