#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "timeout"
require_relative "../../lib/elkrb"

# Runs every corpus case through Elkrb.layout and records pass/error/timeout.
#
# The corpus is every spec/fixtures/*.json (bare graph, default algorithm
# "layered"), every spec/fixtures/corpus/*.json (wrapper {"algorithm":,
# "graph":}; the non-JSON fixtures in that directory, bom.elkt and
# garbage.txt, are deliberately excluded here -- they exist for the CLI's
# extension-sniffing specs, not for layout), and every entry of each
# spec/cross_validation/fixtures/*/imported_tests.json file. This is the
# single enumeration every later slice's execution-diff gate diffs
# against, so `.cases` is the one place that logic lives.
class CorpusRunner
  ROOT = File.expand_path("../..", __dir__)
  TIMEOUT_SECONDS = 30

  # A fixed seed reseeded before every case. force/random call unseeded
  # Kernel#rand, so without this, two dumps of identical, unchanged code
  # would disagree on those cases, breaking every later slice's
  # execution-diff comparison. Reseeding right before each case (not once
  # per run) keeps one case's random-number consumption from shifting a
  # later case's output. elk.randomSeed support is S14's job; this only
  # makes this runner's own dumps reproducible in the meantime. The value
  # itself is arbitrary -- any fixed integer works equally well.
  DETERMINISTIC_SEED = 20_260_819

  # Case ids are fixture basenames, so dumping into one of the corpus's own
  # source directories would overwrite the tracked inputs with layout
  # output.
  SOURCE_DIRS = [
    File.join(ROOT, "spec/fixtures"),
    File.join(ROOT, "spec/cross_validation/fixtures"),
  ].freeze

  Case = Struct.new(:id, :algorithm, :graph, keyword_init: true)

  class << self
    def cases
      all_cases = top_level_fixture_cases + corpus_fixture_cases + imported_cases
      duplicates = all_cases.map(&:id).tally.select { |_, count| count > 1 }.keys
      raise ArgumentError, "duplicate corpus case ids: #{duplicates.join(', ')}" unless duplicates.empty?

      all_cases
    end

    def run(outdir, timeout: TIMEOUT_SECONDS)
      refuse_source_directory!(outdir)
      FileUtils.mkdir_p(outdir)
      summary = { "total" => 0, "ok" => 0, "error" => 0, "timeout" => 0, "cases" => [] }

      cases.each do |kase|
        status, payload = run_case(kase, timeout)
        summary["total"] += 1
        summary[status] += 1
        summary["cases"] << { "id" => kase.id, "algorithm" => kase.algorithm, "status" => status }
        File.write(File.join(outdir, "#{kase.id}.json"), JSON.pretty_generate(payload))
      end

      File.write(File.join(outdir, "summary.json"), JSON.pretty_generate(summary))
      summary
    end

    private

    def refuse_source_directory!(outdir)
      expanded = File.expand_path(outdir)
      return unless SOURCE_DIRS.any? { |dir| expanded == dir || expanded.start_with?("#{dir}/") }

      raise ArgumentError, "refusing to dump into a corpus source directory: #{outdir}"
    end

    def run_case(kase, timeout)
      Kernel.srand(DETERMINISTIC_SEED)
      result = Timeout.timeout(timeout) { Elkrb.layout(kase.graph, algorithm: kase.algorithm) }
      ["ok", canonicalize(JSON.parse(result.to_json))]
    rescue Timeout::Error
      ["timeout", { "error" => "Timeout" }]
    rescue StandardError, SystemStackError => e
      ["error", { "error" => "#{e.class}: #{e.message}" }]
    end

    def canonicalize(value)
      case value
      when Hash
        value.transform_values { |v| canonicalize(v) }.sort.to_h
      when Array
        value.map { |v| canonicalize(v) }
      when Float
        value.round(6)
      else
        value
      end
    end

    def top_level_fixture_cases
      Dir[File.join(ROOT, "spec/fixtures/*.json")].sort.map do |path|
        Case.new(id: File.basename(path, ".json"), algorithm: "layered", graph: JSON.parse(File.read(path)))
      end
    end

    def corpus_fixture_cases
      Dir[File.join(ROOT, "spec/fixtures/corpus/*.json")].sort.map do |path|
        wrapper = JSON.parse(File.read(path))
        Case.new(
          id: File.basename(path, ".json"),
          algorithm: wrapper.fetch("algorithm", "layered"),
          graph: wrapper.fetch("graph")
        )
      end
    end

    def imported_cases
      Dir[File.join(ROOT, "spec/cross_validation/fixtures/*/imported_tests.json")].sort.flat_map do |path|
        JSON.parse(File.read(path)).map do |entry|
          Case.new(
            id: entry.fetch("id"),
            algorithm: entry.fetch("algorithm", "layered"),
            graph: entry.fetch("graph")
          )
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  outdir = ARGV[0] or abort "usage: corpus_runner.rb <outdir>"
  summary = CorpusRunner.run(outdir)
  puts "corpus: #{summary['ok']} ok, #{summary['error']} error, " \
       "#{summary['timeout']} timeout (#{summary['total']} total)"
  exit 1 if summary["error"].positive? || summary["timeout"].positive?
end
