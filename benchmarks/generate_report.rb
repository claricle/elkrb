#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../lib/elkrb/version"

# Generates performance comparison report in AsciiDoc format
class PerformanceReportGenerator
  def initialize
    @elkrb_results = load_json("benchmarks/results/elkrb_summary.json")
    validate_elkrb_version!
    @elkjs_results = load_json("benchmarks/results/elkjs_summary.json")
  end

  def generate
    adoc = generate_adoc_report
    FileUtils.mkdir_p("docs")
    File.write("docs/PERFORMANCE.adoc", adoc)
    puts "Performance report generated: docs/PERFORMANCE.adoc"
  end

  private

  def load_json(path)
    JSON.parse(File.read(path))
  rescue Errno::ENOENT, JSON::ParserError
    nil
  end

  def validate_elkrb_version!
    return unless @elkrb_results

    benchmark_version = @elkrb_results["elkrb_version"] || "unknown"
    return if benchmark_version == Elkrb::VERSION

    raise ArgumentError,
          "benchmark ElkRb version #{benchmark_version} does not match #{Elkrb::VERSION}"
  end

  def generate_adoc_report
    <<~ADOC
      = ElkRb Performance Benchmarks
      :toc:
      :toclevels: 2

      == Overview

      #{report_overview}

      **ElkRb Benchmark Date**: #{@elkrb_results&.dig('timestamp') || 'unknown'}

      **Environment**:

      #{environment_details}

      == Benchmark Methodology

      * Each test runs 10 iterations with a warm-up run
      * Times reported are average execution time in milliseconds
      #{comparison_methodology}

      == Test Graphs

      #{generate_graph_descriptions}

      == Performance Results

      #{generate_performance_tables}

      == Performance Analysis

      #{generate_analysis}

      == Conclusion

      #{generate_conclusion}
    ADOC
  end

  def report_overview
    return "This document compares ElkRb and elkjs benchmark results." if @elkjs_results

    "This document reports ElkRb benchmarks. No elkjs benchmark evidence was provided."
  end

  def environment_details
    details = [
      "* **ElkRb**: Ruby #{@elkrb_results&.dig('ruby_version') || 'unknown'}, ElkRb v#{@elkrb_results&.dig('elkrb_version') || 'unknown'}",
    ]
    return details.join("\n") unless @elkjs_results

    details << "* **elkjs**: Node.js #{@elkjs_results['node_version'] || 'unknown'}, elkjs v#{@elkjs_results['elkjs_version'] || 'unknown'}"
    details.join("\n")
  end

  def comparison_methodology
    if @elkjs_results
      "* Comparisons use matching graph and algorithm names from the supplied summaries"
    else
      "* No cross-implementation comparison is shown without an elkjs summary"
    end
  end

  def generate_graph_descriptions
    return "No benchmark data available." unless @elkrb_results

    graphs_info = {
      "small_simple" => "Small graph with 10 nodes and 15 edges",
      "medium_hierarchical" => "Medium hierarchical graph with 50 nodes, 75 edges, and 3 levels",
      "large_complex" => "Large complex graph with 200 nodes and 400 edges",
      "dense_network" => "Dense network with 100 nodes and 500 edges",
    }

    @elkrb_results["results"].keys.map do |graph_name|
      "* **#{format_name(graph_name)}**: #{graphs_info[graph_name] || 'Test graph'}"
    end.join("\n")
  end

  def generate_performance_tables
    return "No benchmark data available." unless @elkrb_results

    @elkrb_results["results"].map do |graph_name, algorithms|
      generate_graph_table(graph_name, algorithms)
    end.join("\n\n")
  end

  def generate_graph_table(graph_name, algorithms)
    return generate_elkrb_graph_table(graph_name, algorithms) unless @elkjs_results

    <<~TABLE
      === #{format_name(graph_name)}

      [cols="2,1,1,1,1", options="header"]
      |===
      |Algorithm |ElkRb (ms) |elkjs (ms) |Relative |Winner

      #{generate_algorithm_rows(graph_name, algorithms)}
      |===
    TABLE
  end

  def generate_elkrb_graph_table(graph_name, algorithms)
    <<~TABLE
      === #{format_name(graph_name)}

      [cols="2,1", options="header"]
      |===
      |Algorithm |ElkRb (ms)

      #{generate_elkrb_rows(algorithms)}
      |===
    TABLE
  end

  def generate_elkrb_rows(algorithms)
    rows = algorithms.filter_map do |algorithm, data|
      next if data["error"]

      "|#{format_name(algorithm)} |#{data['avg'].round(2)}"
    end

    rows.empty? ? "|No data |N/A" : rows.join("\n")
  end

  def generate_algorithm_rows(graph_name, algorithms)
    rows = algorithms.filter_map do |algo, elkrb_data|
      next if elkrb_data["error"]

      elkjs_data = @elkjs_results&.dig("results", graph_name, algo) || {}
      next if elkjs_data["error"]

      elkrb_time = elkrb_data["avg"].round(2)
      elkjs_time = elkjs_data["avg"]&.round(2)

      if elkjs_time
        relative = (elkrb_time / elkjs_time).round(2)
        winner = if relative < 0.9
                   "✅ ElkRb"
                 elsif relative > 1.1
                   "❌ elkjs"
                 else
                   "🟡 Tie"
                 end
      else
        elkjs_time = "N/A"
        relative = "N/A"
        winner = "N/A"
      end

      "|#{format_name(algo)} |#{elkrb_time} |#{elkjs_time} |#{relative}x |#{winner}"
    end

    rows.empty? ? "|No data |N/A |N/A |N/A |N/A" : rows.join("\n")
  end

  def generate_analysis
    return "No benchmark data available for analysis." unless @elkrb_results

    <<~ANALYSIS
      === Recorded averages

      These averages include successful measurements from the recorded fixtures.
      Errors and timeouts are omitted.

      #{generate_algorithm_summary}
    ANALYSIS
  end

  def generate_algorithm_summary
    return "No data available." unless @elkrb_results

    # Calculate average performance across successful graph runs
    algorithm_stats = {}

    @elkrb_results["results"].each_value do |algorithms|
      algorithms.each do |algo, data|
        next if data["error"]

        algorithm_stats[algo] ||= []
        algorithm_stats[algo] << data["avg"]
      end
    end

    summary = algorithm_stats.map do |algo, times|
      avg = (times.sum / times.size).round(2)
      "* **#{format_name(algo)}**: #{avg}ms average across successful graph runs"
    end

    summary.join("\n")
  end

  def generate_conclusion
    <<~CONCLUSION
      These measurements apply only to the recorded fixtures, versions, and
      environment. They do not establish suitability for other workloads or
      production use.

      Re-run the benchmarks in the deployment environment with representative
      graphs, and treat recorded errors or timeouts as unsupported workload and
      algorithm combinations until measured otherwise.
    CONCLUSION
  end

  def format_name(name)
    name.to_s.split("_").map(&:capitalize).join(" ")
  end
end

# Generate report when run directly
if __FILE__ == $PROGRAM_NAME
  PerformanceReportGenerator.new.generate
end
