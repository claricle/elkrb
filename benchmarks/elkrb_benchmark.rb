#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "elkrb"
require "json"
require "benchmark"
require "optparse"

# ElkRb Performance Benchmark
class ElkrbBenchmark
  ALGORITHMS = %w[
    layered force stress box random fixed
    mrtree radial rectpacking disco
    sporeOverlap sporeCompaction
    topdownpacking libavoid vertiflex
  ].freeze

  # @param max_ms [Numeric, nil] when set, #run reports every measured
  #   average above this many milliseconds
  def initialize(max_ms: nil)
    @graphs = load_graphs
    @results = {}
    @max_ms = max_ms
  end

  # @return [Array<String>] one line per graph and algorithm whose average
  #   exceeded the budget; empty without a budget
  def run
    puts "ElkRb Performance Benchmark"
    puts "=" * 60
    puts "Ruby Version: #{RUBY_VERSION}"
    puts "ElkRb Version: #{Elkrb::VERSION}"
    puts

    @graphs.each do |name, data|
      puts "Graph: #{name} - #{data['description']}"
      benchmark_graph(name, data["graph"])
      puts
    end

    save_results
    generate_report
    over_budget
  end

  private

  def load_graphs
    JSON.parse(File.read("benchmarks/fixtures/graphs.json"))
  end

  def benchmark_graph(name, graph_data)
    @results[name] = {}

    ALGORITHMS.each do |algorithm|
      times = []
      memory_before = get_memory_usage

      # Warm-up run with timeout
      result = run_with_timeout(5) do
        Elkrb.layout(graph_data, algorithm: algorithm)
      end

      if result.nil?
        puts "  #{algorithm.ljust(20)}: TIMEOUT (> 5s)"
        @results[name][algorithm] = { error: "Timeout" }
        next
      end

      # Benchmark runs (10 iterations)
      10.times do
        time = Benchmark.realtime do
          Elkrb.layout(graph_data, algorithm: algorithm)
        end
        times << time
      end

      memory_after = get_memory_usage
      memory_delta = memory_after - memory_before

      avg_time = times.sum / times.size
      min_time = times.min
      max_time = times.max

      @results[name][algorithm] = {
        avg: avg_time * 1000, # Convert to ms
        min: min_time * 1000,
        max: max_time * 1000,
        memory: memory_delta,
      }

      puts "  #{algorithm.ljust(20)}: #{format_time(avg_time * 1000)}"
    rescue StandardError, SystemStackError => e
      error_msg = e.is_a?(SystemStackError) ? "Stack overflow (graph has cycles)" : e.message
      puts "  #{algorithm.ljust(20)}: ERROR - #{error_msg}"
      @results[name][algorithm] = { error: error_msg }
    end
  end

  def run_with_timeout(seconds, &)
    require "timeout"
    Timeout.timeout(seconds, &)
  rescue Timeout::Error
    nil
  end

  def get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i
  end

  def format_time(ms)
    if ms < 1
      "#{(ms * 1000).round(2)}µs"
    elsif ms < 1000
      "#{ms.round(2)}ms"
    else
      "#{(ms / 1000).round(2)}s"
    end
  end

  def over_budget
    return [] unless @max_ms

    @results.flat_map do |graph, by_algorithm|
      by_algorithm.filter_map do |algorithm, result|
        avg = result[:avg]
        next unless avg && avg > @max_ms

        "#{graph} / #{algorithm}: #{avg.round(2)}ms > #{@max_ms}ms"
      end
    end
  end

  def save_results
    File.write(
      "benchmarks/results/elkrb_results.json",
      JSON.pretty_generate(@results),
    )
  end

  def generate_report
    summary = {
      timestamp: Time.now.iso8601,
      ruby_version: RUBY_VERSION,
      elkrb_version: Elkrb::VERSION,
      results: @results,
    }

    File.write(
      "benchmarks/results/elkrb_summary.json",
      JSON.pretty_generate(summary),
    )

    puts "=" * 60
    puts "Results saved to:"
    puts "  - benchmarks/results/elkrb_results.json"
    puts "  - benchmarks/results/elkrb_summary.json"
  end
end

# Run benchmark when executed directly
if __FILE__ == $PROGRAM_NAME
  max_ms = nil
  OptionParser.new do |opts|
    opts.banner = "Usage: elkrb_benchmark.rb [--assert-max-ms MS]"
    opts.on("--assert-max-ms MS", Float, "Exit 1 when any average exceeds MS") do |value|
      max_ms = value
    end
  end.parse!

  failures = ElkrbBenchmark.new(max_ms: max_ms).run
  unless failures.empty?
    warn "Over budget:", *failures.map { |line| "  #{line}" }
    exit 1
  end
end
