#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../../lib/elkrb"

# Runner for cross-validation tests
class ValidationRunner
  def initialize
    @elkjs_tests = load_tests("elkjs")
    @java_elk_tests = load_tests("java_elk")
    @results = {
      elkjs: { passed: 0, failed: 0, errors: [] },
      java_elk: { passed: 0, failed: 0, errors: [] },
    }
  end

  def run_all
    puts "Running Cross-Validation Tests"
    puts "=" * 70

    run_elkjs_tests
    run_java_elk_tests

    generate_report
  end

  private

  def load_tests(source)
    path = "spec/cross_validation/fixtures/#{source}/imported_tests.json"
    return [] unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def run_elkjs_tests
    return if @elkjs_tests.empty?

    puts "\nRunning elkjs tests (#{@elkjs_tests.length} cases)..."

    @elkjs_tests.each do |test_case|
      run_test_case(test_case, :elkjs)
    end
  end

  def run_java_elk_tests
    return if @java_elk_tests.empty?

    puts "\nRunning Java ELK tests (#{@java_elk_tests.length} cases)..."

    @java_elk_tests.each do |test_case|
      run_test_case(test_case, :java_elk)
    end
  end

  def run_test_case(test_case, source)
    test_id = test_case["id"]
    algorithm = test_case["algorithm"]
    graph = test_case["graph"]

    begin
      # Add timeout to prevent infinite loops
      result = nil
      thread = Thread.new do
        result = Elkrb.layout(graph, algorithm: algorithm)
      end

      # Wait maximum 5 seconds for layout
      unless thread.join(5)
        thread.kill
        raise "Layout timeout (>5s) - possible infinite loop"
      end

      # Validate result structure
      validate_result(result, test_id)

      @results[source][:passed] += 1
      print "."
    rescue SystemStackError => e
      @results[source][:failed] += 1
      @results[source][:errors] << {
        test_id: test_id,
        error: "Stack overflow (likely cycle in graph): #{e.message}",
        backtrace: [],
      }
      print "F"
    rescue StandardError => e
      @results[source][:failed] += 1
      @results[source][:errors] << {
        test_id: test_id,
        error: e.message,
        backtrace: e.backtrace.first(5),
      }
      print "F"
    end
  end

  def validate_result(result, _test_id)
    # Result is a Graph object, not a hash
    raise "Result is nil" if result.nil?
    raise "Result is not a Graph" unless result.is_a?(Elkrb::Graph::Graph)

    # Validate children exist
    raise "No children in result" if result.children.nil? || result.children.empty?

    # Validate positions assigned
    result.children.each do |node|
      raise "Node #{node.id} missing x position" if node.x.nil?
      raise "Node #{node.id} missing y position" if node.y.nil?
    end

    # Validate graph bounds
    raise "Graph missing width" if result.width.nil?
    raise "Graph missing height" if result.height.nil?
  end

  def generate_report
    puts "\n\n#{'=' * 70}"
    puts "Cross-Validation Results"
    puts "=" * 70

    # elkjs results
    puts "\nElkjs Tests:"
    puts "  Passed: #{@results[:elkjs][:passed]}"
    puts "  Failed: #{@results[:elkjs][:failed]}"
    puts "  Total:  #{@elkjs_tests.length}"
    puts "  Pass Rate: #{pass_rate(:elkjs)}%"

    if @results[:elkjs][:failed] > 0
      puts "\n  Failures:"
      @results[:elkjs][:errors].each do |error|
        puts "    - #{error[:test_id]}: #{error[:error]}"
      end
    end

    # Java ELK results
    puts "\nJava ELK Tests:"
    puts "  Passed: #{@results[:java_elk][:passed]}"
    puts "  Failed: #{@results[:java_elk][:failed]}"
    puts "  Total:  #{@java_elk_tests.length}"
    puts "  Pass Rate: #{pass_rate(:java_elk)}%"

    if @results[:java_elk][:failed] > 0
      puts "\n  Failures:"
      @results[:java_elk][:errors].each do |error|
        puts "    - #{error[:test_id]}: #{error[:error]}"
      end
    end

    # Overall
    total_tests = @elkjs_tests.length + @java_elk_tests.length
    total_passed = @results[:elkjs][:passed] + @results[:java_elk][:passed]
    total_failed = @results[:elkjs][:failed] + @results[:java_elk][:failed]

    puts "\nOverall:"
    puts "  Passed: #{total_passed}/#{total_tests}"
    puts "  Failed: #{total_failed}/#{total_tests}"
    puts "  Pass Rate: #{overall_pass_rate(total_passed, total_tests)}%"

    # Save report
    save_report(total_tests, total_passed, total_failed)
  end

  def pass_rate(source)
    total = @results[source][:passed] + @results[source][:failed]
    return 0 if total == 0

    (@results[source][:passed].to_f / total * 100).round(2)
  end

  def overall_pass_rate(passed, total)
    return 0 if total == 0

    (passed.to_f / total * 100).round(2)
  end

  def save_report(total_tests, total_passed, total_failed)
    report = {
      timestamp: Time.now.utc.iso8601,
      summary: {
        total_tests: total_tests,
        total_passed: total_passed,
        total_failed: total_failed,
        pass_rate: overall_pass_rate(total_passed, total_tests),
      },
      elkjs: @results[:elkjs],
      java_elk: @results[:java_elk],
    }

    FileUtils.mkdir_p("spec/cross_validation")
    File.write(
      "spec/cross_validation/validation_report.json",
      JSON.pretty_generate(report),
    )

    puts "\nReport saved to: spec/cross_validation/validation_report.json"
  end
end

# Run if executed directly
ValidationRunner.new.run_all if __FILE__ == $PROGRAM_NAME
