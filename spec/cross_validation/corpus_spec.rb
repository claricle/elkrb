# frozen_string_literal: true

require "spec_helper"
require "json"
require "timeout"
require "tmpdir"
require_relative "corpus_runner"

RSpec.describe "Elkrb layout corpus" do
  CASES = CorpusRunner.cases.freeze

  # [case id, check] => RC id. A listed check is `pending`; the guard
  # example at the bottom fails if a listed check now passes, forcing
  # this ledger to be edited when a slice fixes the underlying bug.
  # Re-authored against origin/v2 (slice 1, a008889: nil-safe LayoutOptions,
  # self-loop fixes in layered/mrtree, size-less nodes/labels treated as 0
  # at read sites, nil collections). self_loop, java_elk_self_loops, and
  # compound_unsized no longer crash AND now produce finite invariants
  # (compound sizing is computed from children, so removed outright).
  # sizeless_node, labelled_only_text, and no_children_key no longer crash
  # (removed from "no_crash"), but the element that never had a declared
  # size still carries a nil width/height on the object itself -- slice 1
  # is a read-site guard (arithmetic treats nil as 0), not an attribute
  # default (verified: lib/elkrb/layout/label_placer.rb's width_of/
  # height_of helpers), so "invariants" still fails for real. That is
  # decision 5 of the remediation plan ("output omits width/height for
  # nodes that never had them"), tracked here as D5 until S0a's
  # `omit_size_for_unsized_input` matcher lands to assert it correctly.
  KNOWN_FAILURES = {
    ["sizeless_node", "invariants"] => "D5",
    ["no_children_key", "invariants"] => "D5",
    ["duplicate_ids", "no_crash"] => "RC4",
    ["duplicate_ids", "invariants"] => "RC4",
    ["labelled_only_text", "invariants"] => "D5",
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
    assert_labels(node.labels, label)
    (node.ports || []).each_with_index do |p, i|
      port_label = "#{label}.ports[#{i}]"
      assert_finite_point(p, port_label)
      assert_finite_size(p, port_label)
      assert_labels(p.labels, port_label)
    end
    (node.children || []).each_with_index do |c, i|
      assert_node_invariants(c, "#{label}.children[#{i}]")
    end
    (node.edges || []).each_with_index do |e, i|
      assert_edge_invariants(e, "#{label}.edges[#{i}]")
    end
  end

  def assert_edge_invariants(edge, label)
    assert_labels(edge.labels, label)
    (edge.sections || []).each_with_index do |section, i|
      section_label = "#{label}.sections[#{i}]"
      expect(section.start_point).not_to be_nil, "#{section_label}.start is nil"
      expect(section.end_point).not_to be_nil, "#{section_label}.end is nil"
      assert_finite_point(section.start_point, "#{section_label}.start")
      assert_finite_point(section.end_point, "#{section_label}.end")
      (section.bend_points || []).each_with_index do |bp, j|
        assert_finite_point(bp, "#{section_label}.bend[#{j}]")
      end
    end
  end

  def assert_labels(labels, owner_label)
    (labels || []).each_with_index do |l, i|
      assert_finite_point(l, "#{owner_label}.labels[#{i}]")
      assert_finite_size(l, "#{owner_label}.labels[#{i}]")
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
    expect(element.width).to be_finite, "#{label}.width=#{element.width} is not finite"
    expect(element.width).to be >= 0, "#{label}.width=#{element.width} is negative"
    expect(element.height).to be_a(Float), "#{label}.height is #{element.height.inspect}, not a Float"
    expect(element.height).to be_finite, "#{label}.height=#{element.height} is not finite"
    expect(element.height).to be >= 0, "#{label}.height=#{element.height} is negative"
  end

  def known_failure_reason(id, check)
    KNOWN_FAILURES[[id, check]]
  end

  # Corpus fixtures can regress into a hang, not just a crash; without
  # this, a single case would stall the whole suite instead of failing
  # it. corpus_runner.rb has the same 30s guard for the same reason.
  def layout_with_timeout(kase)
    Timeout.timeout(30) { Elkrb.layout(kase.graph, algorithm: kase.algorithm) }
  end

  CASES.each do |kase|
    describe kase.id do
      it "does not raise" do
        reason = known_failure_reason(kase.id, "no_crash")
        pending(reason) if reason

        expect { layout_with_timeout(kase) }.not_to raise_error
      end

      it "keeps layout invariants" do
        reason = known_failure_reason(kase.id, "invariants") || known_failure_reason(kase.id, "no_crash")
        pending(reason) if reason

        result = layout_with_timeout(kase)
        assert_layout_invariants(result)
      end
    end
  end

  it "keeps the KNOWN_FAILURES ledger honest" do
    cases_by_id = CASES.to_h { |kase| [kase.id, kase] }

    stale_ids = KNOWN_FAILURES.keys.map(&:first).uniq - cases_by_id.keys
    expect(stale_ids).to be_empty,
      "KNOWN_FAILURES references case ids that no longer exist in the corpus: #{stale_ids.inspect}"

    now_passing = KNOWN_FAILURES.keys.reject do |id, check|
      entry_still_fails?(cases_by_id.fetch(id), check)
    end

    expect(now_passing).to be_empty,
      "KNOWN_FAILURES entries now pass and must be removed from the ledger: #{now_passing.inspect}"
  end

  def entry_still_fails?(kase, check)
    result = layout_with_timeout(kase)
    assert_layout_invariants(result) if check == "invariants"
    false
  rescue StandardError, SystemStackError, RSpec::Expectations::ExpectationNotMetError
    true
  end

  describe CorpusRunner, ".run" do
    it "has no unexpected failures over the real corpus" do
      Dir.mktmpdir do |dir|
        summary = CorpusRunner.run(dir)
        expect(summary["unexpected_failures"]).to be(false)
      end
    end

    it "writes a canonical file per case, records errors and timeouts, and totals a summary" do
      # width/height 10/3 forces layered's own arithmetic (centring,
      # padding) to produce a Float with far more than 6 decimal digits
      # before canonicalize rounds it -- a 1.0/1.0 node never exercises
      # rounding at all, since layered never needs to divide it further.
      ok_case = CorpusRunner::Case.new(
        id: "ok",
        algorithm: "layered",
        graph: {
          "id" => "root",
          "children" => [
            { "id" => "a", "width" => 10.0 / 3, "height" => 10.0 / 3 },
            { "id" => "b", "width" => 10.0 / 3, "height" => 10.0 / 3 },
          ],
          "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }],
        }
      )
      error_case = CorpusRunner::Case.new(id: "boom", algorithm: "layered", graph: nil)

      # force calls Kernel#rand; only a case that actually consumes
      # randomness can prove the per-case srand reseed makes two runs
      # agree -- a layered-only corpus would pass "stable across two
      # runs" even with the reseed deleted, since layered never calls
      # rand at all.
      force_case = CorpusRunner::Case.new(
        id: "force",
        algorithm: "force",
        graph: {
          "id" => "root",
          "children" => [
            { "id" => "a", "width" => 10.0, "height" => 10.0 },
            { "id" => "b", "width" => 10.0, "height" => 10.0 },
          ],
          "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }],
        }
      )

      slow_algorithm = Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
        def layout_flat(_graph, _options = {})
          sleep 0.15
        end
      end
      Elkrb::Layout::AlgorithmRegistry.register("corpus_runner_spec_slow", slow_algorithm)
      timeout_case = CorpusRunner::Case.new(
        id: "slow", algorithm: "corpus_runner_spec_slow",
        graph: { "id" => "root", "children" => [], "edges" => [] }
      )

      allow(CorpusRunner).to receive(:cases).and_return([ok_case, error_case, force_case, timeout_case])

      Dir.mktmpdir do |dir|
        summary = CorpusRunner.run(dir, timeout: 0.02)

        expect(summary["total"]).to eq(4)
        expect(summary["ok"]).to eq(2)
        expect(summary["error"]).to eq(1)
        expect(summary["timeout"]).to eq(1)
        # error_case and timeout_case both carry expect: nil, so neither
        # matches its own outcome -- this corpus must be flagged, and
        # the CLI entrypoint must exit non-zero for it.
        expect(summary["unexpected_failures"]).to be(true)
        expect(CorpusRunner.exit_code(summary)).to eq(1)

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

        # Canonical means deep-sorted keys, floats rounded to 6 places,
        # and stable across repeated runs -- not just "some JSON got
        # written". Parsing the raw text (not a fresh Hash literal)
        # preserves the file's actual on-disk key order.
        ok_text = File.read(File.join(dir, "ok.json"))
        force_text = File.read(File.join(dir, "force.json"))
        assert_deep_sorted_keys(JSON.parse(ok_text))
        assert_rounded_floats(JSON.parse(ok_text))
        assert_rounded_floats(JSON.parse(force_text))

        Dir.mktmpdir do |second_dir|
          CorpusRunner.run(second_dir, timeout: 0.02)
          expect(File.read(File.join(second_dir, "ok.json"))).to eq(ok_text)
          expect(File.read(File.join(second_dir, "force.json"))).to eq(force_text)
        end
      end
    end
  end

  def assert_deep_sorted_keys(value)
    case value
    when Hash
      expect(value.keys).to eq(value.keys.sort), "keys not sorted: #{value.keys.inspect}"
      value.each_value { |v| assert_deep_sorted_keys(v) }
    when Array
      value.each { |v| assert_deep_sorted_keys(v) }
    end
  end

  def assert_rounded_floats(value)
    case value
    when Hash
      value.each_value { |v| assert_rounded_floats(v) }
    when Array
      value.each { |v| assert_rounded_floats(v) }
    when Float
      expect(value.round(6)).to eq(value), "#{value} has more than 6 decimal places"
    end
  end
end
