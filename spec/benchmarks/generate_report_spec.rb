# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../benchmarks/generate_report"

RSpec.describe PerformanceReportGenerator do
  let(:workspace) { Dir.mktmpdir("elkrb-benchmark-report") }
  let(:benchmark_version) { Elkrb::VERSION }
  let(:elkjs_summary) { nil }
  let(:summary) do
    {
      "timestamp" => "2026-10-10T00:00:00Z",
      "ruby_version" => RUBY_VERSION,
      "elkrb_version" => benchmark_version,
      "results" => {
        "small_simple" => {
          "box" => { "avg" => 1.0, "min" => 0.9, "max" => 1.1 },
        },
      },
    }
  end

  around do |example|
    Dir.chdir(workspace) do
      FileUtils.mkdir_p("benchmarks/results")
      File.write(
        "benchmarks/results/elkrb_summary.json",
        JSON.pretty_generate(summary),
      )
      if elkjs_summary
        File.write(
          "benchmarks/results/elkjs_summary.json",
          JSON.pretty_generate(elkjs_summary),
        )
      end
      example.run
    end
  ensure
    FileUtils.remove_entry(workspace)
  end

  context "when the measurements came from another ElkRb version" do
    let(:benchmark_version) { "0.4.3" }

    it "rejects the stale benchmark input" do
      expect { described_class.new }.to raise_error(
        ArgumentError,
        "benchmark ElkRb version 0.4.3 does not match #{Elkrb::VERSION}",
      )
    end
  end

  describe "#generate" do
    it "limits conclusions to the recorded measurements" do
      described_class.new.generate

      report = File.read("docs/PERFORMANCE.adoc")
      expect(report).to include("These measurements apply only to the recorded")
      expect(report).to include("No elkjs benchmark evidence was provided")
      expect(report).to include("2026-10-10T00:00:00Z")
      expect(report).not_to include("production-ready")
      expect(report).not_to include(
        "same hardware",
        "Node.js unknown",
        "|elkjs (ms)",
      )
    end

    context "when elkjs evidence is present" do
      let(:elkjs_summary) do
        {
          "timestamp" => "2026-10-10T00:05:00Z",
          "node_version" => "v22.0.0",
          "elkjs_version" => "0.11.0",
          "results" => {
            "small_simple" => { "box" => { "avg" => 0.5 } },
          },
        }
      end

      it "includes the supplied comparison" do
        described_class.new.generate

        report = File.read("docs/PERFORMANCE.adoc")
        expect(report).to include("Node.js v22.0.0, elkjs v0.11.0")
        expect(report).to include("|Box |1.0 |0.5 |2.0x |❌ elkjs")
      end
    end
  end
end

RSpec.describe "committed benchmark evidence" do
  it "matches the current version and raw measurements" do
    results_dir = File.expand_path("../../benchmarks/results", __dir__)
    summary_path = File.join(results_dir, "elkrb_summary.json")
    results_path = File.join(results_dir, "elkrb_results.json")
    summary = JSON.parse(File.read(summary_path))
    raw_results = JSON.parse(File.read(results_path))

    expect(summary.fetch("elkrb_version")).to eq(Elkrb::VERSION)
    expect(summary.fetch("results")).to eq(raw_results)
  end
end
