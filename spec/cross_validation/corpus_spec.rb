# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "corpus_runner"

RSpec.describe "Elkrb layout corpus" do
  CASES = CorpusRunner.cases.freeze

  # [case id, check] => RC id. A listed check is `pending`; the guard
  # example at the bottom fails if a listed check now passes, forcing
  # this ledger to be edited when a slice fixes the underlying bug.
  KNOWN_FAILURES = {
    ["self_loop", "no_crash"] => "RC4",
    ["self_loop", "invariants"] => "RC4",
    ["sizeless_node", "no_crash"] => "RC4",
    ["sizeless_node", "invariants"] => "RC4",
    ["no_children_key", "no_crash"] => "RC4",
    ["no_children_key", "invariants"] => "RC4",
    ["duplicate_ids", "no_crash"] => "RC4",
    ["duplicate_ids", "invariants"] => "RC4",
    ["labelled_only_text", "no_crash"] => "RC4",
    ["labelled_only_text", "invariants"] => "RC4",
    ["compound_unsized", "no_crash"] => "RC4",
    ["compound_unsized", "invariants"] => "RC4",
    ["java_elk_self_loops", "no_crash"] => "RC4",
    ["java_elk_self_loops", "invariants"] => "RC4",
    ["java_elk_sporeOverlap", "no_crash"] => "RC14",
    ["java_elk_sporeOverlap", "invariants"] => "RC14",
    ["java_elk_sporeCompaction", "no_crash"] => "RC14",
    ["java_elk_sporeCompaction", "invariants"] => "RC14",
    ["port_id_edges", "invariants"] => "RC8",
    ["elkjs_bug7_complex", "invariants"] => "RC8",
    ["java_elk_ports", "invariants"] => "RC4",
  }.freeze

  # Every node/label/port/section coordinate is a finite Float and every
  # width/height is a finite, non-negative Float. The root graph itself
  # is checked for size only (ELK's root canvas is never positioned).
  # S0a extends this set.
  def assert_layout_invariants(result)
    assert_finite_size(result, "$")
    (result.children || []).each_with_index do |node, i|
      assert_node_invariants(node, "$.children[#{i}]")
    end
    (result.edges || []).each_with_index do |edge, i|
      assert_edge_invariants(edge, "$.edges[#{i}]")
    end
  end

  def assert_node_invariants(node, label)
    assert_finite_point(node, label)
    assert_finite_size(node, label)
    (node.labels || []).each_with_index do |l, i|
      assert_finite_point(l, "#{label}.labels[#{i}]")
      assert_finite_size(l, "#{label}.labels[#{i}]")
    end
    (node.ports || []).each_with_index do |p, i|
      assert_finite_point(p, "#{label}.ports[#{i}]")
      assert_finite_size(p, "#{label}.ports[#{i}]")
    end
    (node.children || []).each_with_index do |c, i|
      assert_node_invariants(c, "#{label}.children[#{i}]")
    end
    (node.edges || []).each_with_index do |e, i|
      assert_edge_invariants(e, "#{label}.edges[#{i}]")
    end
  end

  def assert_edge_invariants(edge, label)
    (edge.sections || []).each_with_index do |section, i|
      section_label = "#{label}.sections[#{i}]"
      assert_finite_point(section.start_point, "#{section_label}.start") if section.start_point
      assert_finite_point(section.end_point, "#{section_label}.end") if section.end_point
      (section.bend_points || []).each_with_index do |bp, j|
        assert_finite_point(bp, "#{section_label}.bend[#{j}]")
      end
    end
  end

  def assert_finite_point(point, label)
    expect(point.x).to be_a(Float), "#{label}.x is #{point.x.inspect}, not a Float"
    expect(point.x).to be_finite, "#{label}.x=#{point.x} is not finite"
    expect(point.y).to be_a(Float), "#{label}.y is #{point.y.inspect}, not a Float"
    expect(point.y).to be_finite, "#{label}.y=#{point.y} is not finite"
  end

  def assert_finite_size(element, label)
    expect(element.width).to be_a(Float), "#{label}.width is #{element.width.inspect}, not a Float"
    expect(element.width).to be_finite
    expect(element.width).to be >= 0
    expect(element.height).to be_a(Float), "#{label}.height is #{element.height.inspect}, not a Float"
    expect(element.height).to be_finite
    expect(element.height).to be >= 0
  end

  def known_failure_reason(id, check)
    KNOWN_FAILURES[[id, check]]
  end

  CASES.each do |kase|
    describe kase.id do
      it "does not raise" do
        reason = known_failure_reason(kase.id, "no_crash")
        pending(reason) if reason

        expect { Elkrb.layout(kase.graph, algorithm: kase.algorithm) }.not_to raise_error
      end

      it "keeps layout invariants" do
        reason = known_failure_reason(kase.id, "invariants") || known_failure_reason(kase.id, "no_crash")
        pending(reason) if reason

        result = Elkrb.layout(kase.graph, algorithm: kase.algorithm)
        assert_layout_invariants(result)
      end
    end
  end

  it "keeps the KNOWN_FAILURES ledger honest" do
    cases_by_id = CASES.to_h { |kase| [kase.id, kase] }

    now_passing = KNOWN_FAILURES.keys.reject do |id, check|
      entry_still_fails?(cases_by_id.fetch(id), check)
    end

    expect(now_passing).to be_empty,
      "KNOWN_FAILURES entries now pass and must be removed from the ledger: #{now_passing.inspect}"
  end

  def entry_still_fails?(kase, check)
    result = Elkrb.layout(kase.graph, algorithm: kase.algorithm)
    assert_layout_invariants(result) if check == "invariants"
    false
  rescue StandardError, SystemStackError, RSpec::Expectations::ExpectationNotMetError
    true
  end

  describe CorpusRunner, ".run" do
    it "writes a canonical file per case, records errors and timeouts, and totals a summary" do
      ok_case = CorpusRunner::Case.new(
        id: "ok",
        algorithm: "layered",
        graph: {
          "id" => "root",
          "children" => [
            { "id" => "a", "width" => 1.0, "height" => 1.0 },
            { "id" => "b", "width" => 1.0, "height" => 1.0 },
          ],
          "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }],
        }
      )
      error_case = CorpusRunner::Case.new(id: "boom", algorithm: "layered", graph: nil)

      slow_algorithm = Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
        def layout_flat(_graph, _options = {})
          sleep 0.05
        end
      end
      Elkrb::Layout::AlgorithmRegistry.register("corpus_runner_spec_slow", slow_algorithm)
      timeout_case = CorpusRunner::Case.new(
        id: "slow", algorithm: "corpus_runner_spec_slow",
        graph: { "id" => "root", "children" => [], "edges" => [] }
      )

      allow(CorpusRunner).to receive(:cases).and_return([ok_case, error_case, timeout_case])

      Dir.mktmpdir do |dir|
        summary = CorpusRunner.run(dir, timeout: 0.01)

        expect(summary["total"]).to eq(3)
        expect(summary["ok"]).to eq(1)
        expect(summary["error"]).to eq(1)
        expect(summary["timeout"]).to eq(1)

        ok_payload = JSON.parse(File.read(File.join(dir, "ok.json")))
        expect(ok_payload).to include("id" => "root")

        # Any exception class is acceptable here: the contract under test is
        # "graph: nil errors out with a class+message payload", not which
        # specific class Elkrb.layout happens to raise for nil today.
        error_payload = JSON.parse(File.read(File.join(dir, "boom.json")))
        expect(error_payload["error"]).to match(/\A\w+(::\w+)*: /)

        timeout_payload = JSON.parse(File.read(File.join(dir, "slow.json")))
        expect(timeout_payload).to eq("error" => "Timeout")

        expect(JSON.parse(File.read(File.join(dir, "summary.json")))).to eq(summary)
      end
    end
  end
end
