# frozen_string_literal: true

require "spec_helper"
require "json"
require "timeout"
require "tmpdir"
require_relative "corpus_runner"

# Held in a module because a constant assigned inside a `describe` block
# lands on Object regardless. Naming the namespace makes that explicit and
# keeps both constants greppable.
module CorpusCatalogue
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
end

RSpec.describe "Elkrb layout corpus" do
  # Every node/label/port/section coordinate is a finite Float and every
  # width/height is a finite, non-negative Float. The root graph itself
  # is checked for size only (ELK's root canvas is never positioned).
  # S0a extends this set.
  def assert_layout_invariants(result, input)
    assert_finite_size(result, "$")
    assert_structure_preserved(result, input)
    (result.children || []).each_with_index do |node, i|
      assert_node_invariants(node, "$.children[#{i}]")
    end
    (result.edges || []).each_with_index do |edge, i|
      assert_edge_invariants(edge, "$.edges[#{i}]")
    end
  end

  # Layout moves elements; it must not add, drop, reorder or rename one.
  # Coordinates alone cannot see that: an element that is simply gone
  # takes its coordinates with it, so a regression that loses every edge
  # keeps every finite-number assertion green. The fixtures added to
  # exercise edges -- hyperedge, cycle3, self_loop, port_id_edges,
  # stale_sections -- are the ones this covers.
  def assert_structure_preserved(result, input)
    expect(node_ids(result)).to eq(input_node_ids(input))
    expect(edge_ids(result)).to eq(input_edge_ids(input))
  end

  def node_ids(element)
    (element.children || []).flat_map { |c| [c.id, *node_ids(c)] }
  end

  def edge_ids(element)
    (element.edges || []).map(&:id) +
      (element.children || []).flat_map { |c| edge_ids(c) }
  end

  def input_node_ids(hash)
    (hash["children"] || []).flat_map { |c| [c["id"], *input_node_ids(c)] }
  end

  def input_edge_ids(hash)
    (hash["edges"] || []).map { |e| e["id"] } +
      (hash["children"] || []).flat_map { |c| input_edge_ids(c) }
  end

  def assert_node_invariants(node, label)
    assert_finite_point(node, label)
    assert_finite_size(node, label)
    assert_labels(node.labels, label)
    assert_ports(node.ports, label)
    (node.children || []).each_with_index do |c, i|
      assert_node_invariants(c, "#{label}.children[#{i}]")
    end
    (node.edges || []).each_with_index do |e, i|
      assert_edge_invariants(e, "#{label}.edges[#{i}]")
    end
  end

  def assert_ports(ports, owner_label)
    (ports || []).each_with_index do |port, i|
      label = "#{owner_label}.ports[#{i}]"
      assert_finite_point(port, label)
      assert_finite_size(port, label)
      assert_labels(port.labels, label)
    end
  end

  def assert_edge_invariants(edge, label)
    assert_labels(edge.labels, label)
    (edge.sections || []).each_with_index do |section, i|
      assert_section_invariants(section, "#{label}.sections[#{i}]")
    end
  end

  def assert_section_invariants(section, label)
    start_point = section.start_point
    end_point = section.end_point
    expect(start_point).not_to be_nil, "#{label}.start is nil"
    expect(end_point).not_to be_nil, "#{label}.end is nil"
    assert_finite_point(start_point, "#{label}.start")
    assert_finite_point(end_point, "#{label}.end")
    (section.bend_points || []).each_with_index do |bp, j|
      assert_finite_point(bp, "#{label}.bend[#{j}]")
    end
  end

  def assert_labels(labels, owner_label)
    (labels || []).each_with_index do |l, i|
      assert_finite_point(l, "#{owner_label}.labels[#{i}]")
      assert_finite_size(l, "#{owner_label}.labels[#{i}]")
    end
  end

  def assert_finite_point(point, label)
    assert_finite_number(point.x, "#{label}.x")
    assert_finite_number(point.y, "#{label}.y")
  end

  def assert_finite_size(element, label)
    assert_non_negative(element.width, "#{label}.width")
    assert_non_negative(element.height, "#{label}.height")
  end

  def assert_finite_number(value, label)
    expect(value).to be_a(Float), "#{label} is #{value.inspect}, not a Float"
    expect(value).to be_finite, "#{label}=#{value} is not finite"
  end

  def assert_non_negative(value, label)
    assert_finite_number(value, label)
    expect(value).to be >= 0, "#{label}=#{value} is negative"
  end

  def known_failure_reason(id, check)
    CorpusCatalogue::KNOWN_FAILURES[[id, check]]
  end

  # Corpus fixtures can regress into a hang, not just a crash; without
  # this, a single case would stall the whole suite instead of failing
  # it. corpus_runner.rb has the same 30s guard for the same reason.
  def layout_with_timeout(kase)
    Timeout.timeout(30) { Elkrb.layout(kase.graph, algorithm: kase.algorithm) }
  end

  CorpusCatalogue::CASES.each do |kase|
    describe kase.id do
      it "does not raise" do
        reason = known_failure_reason(kase.id, "no_crash")
        pending(reason) if reason

        expect { layout_with_timeout(kase) }.not_to raise_error
      end

      it "keeps layout invariants" do
        reason = known_failure_reason(kase.id, "invariants") ||
          known_failure_reason(kase.id, "no_crash")
        pending(reason) if reason

        result = layout_with_timeout(kase)
        assert_layout_invariants(result, kase.graph)
      end
    end
  end

  it "keeps the KNOWN_FAILURES ledger honest" do
    ledger = CorpusCatalogue::KNOWN_FAILURES
    cases_by_id = CorpusCatalogue::CASES.to_h { |kase| [kase.id, kase] }

    stale_ids = ledger.keys.map(&:first).uniq - cases_by_id.keys
    expect(stale_ids).to(
      be_empty,
      "KNOWN_FAILURES references case ids that no longer exist in the " \
      "corpus: #{stale_ids.inspect}",
    )

    now_passing = ledger.keys.reject do |id, check|
      entry_still_fails?(cases_by_id.fetch(id), check)
    end

    expect(now_passing).to(
      be_empty,
      "KNOWN_FAILURES entries now pass and must be removed from the " \
      "ledger: #{now_passing.inspect}",
    )
  end

  def entry_still_fails?(kase, check)
    result = layout_with_timeout(kase)
    assert_layout_invariants(result, kase.graph) if check == "invariants"
    false
  rescue StandardError, SystemStackError, RSpec::Expectations::ExpectationNotMetError
    true
  end

  describe CorpusRunner, ".source_directory?" do
    # Case ids are fixture basenames, so a dump into spec/fixtures would
    # overwrite the tracked inputs with layout output -- and prune would
    # delete the ones the corpus no longer names. The rule has to
    # recognise a source directory under any name it can be reached by: an
    # alias is not a different directory just because it spells
    # differently.
    #
    # Asserted through the predicate rather than through `run`, because a
    # `run` pointed at spec/fixtures is the exact accident being guarded
    # against, and a spec that does it for real destroys the fixtures the
    # moment the guard regresses.
    def root(*parts)
      File.join(CorpusRunner::ROOT, *parts)
    end

    it "is true for each source directory and for paths beneath it" do
      CorpusRunner::SOURCE_DIRS.each do |dir|
        expect(CorpusRunner.source_directory?(dir)).to be(true)
      end

      probe = root("spec/fixtures/dump_probe")
      expect(CorpusRunner.source_directory?(probe)).to be(true)
    end

    it "is true for a symlink that resolves to a source directory" do
      Dir.mktmpdir do |tmp|
        link = File.join(tmp, "alias")
        File.symlink(root("spec/fixtures"), link)

        expect(CorpusRunner.source_directory?(link)).to be(true)
        under_link = File.join(link, "dump_probe")
        expect(CorpusRunner.source_directory?(under_link)).to be(true)
      end
    end

    it "is true for a name that differs only by case on a " \
       "case-insensitive filesystem" do
      aliased = root("spec/Fixtures")
      unless File.identical?(aliased, root("spec/fixtures"))
        skip "filesystem is case-sensitive, so spec/Fixtures is a " \
             "different directory"
      end

      expect(CorpusRunner.source_directory?(aliased)).to be(true)
    end

    it "is false for a sibling that merely shares a source " \
       "directory's prefix" do
      sibling = root("spec/fixtures_elsewhere")
      expect(CorpusRunner.source_directory?(sibling)).to be(false)
      expect(CorpusRunner.source_directory?(root("tmp/corpus"))).to be(false)
    end
  end

  describe CorpusRunner, ".cases" do
    it "refuses a case id that would collide with summary.json" do
      reserved = CorpusRunner::Case.new(id: CorpusRunner::RESERVED_ID)
      allow(CorpusRunner).to receive(:imported_cases).and_return([reserved])

      expect { CorpusRunner.cases }
        .to raise_error(ArgumentError, /collides with summary\.json/)
    end

    # macOS and Windows resolve SUMMARY.json and summary.json to ONE file, so
    # a differently-cased id passed the guard and then had its payload
    # overwritten by the dump's own index. One example per casing would be
    # four examples asserting one property, so the casings are a table.
    # "\u017Fummary" is not a casing, it is a FOLD: Unicode folds long s to s,
    # and macOS resolves it to the same file as summary.json. A bytewise
    # downcase misses it entirely, which is why the comparison stays
    # encoding-aware for any id whose encoding is valid.
    # The last two are not casings. "\u017Fummary" is a FOLD -- Unicode folds
    # long s to s and macOS resolves it to the same file. The BINARY one is
    # the same bytes in ASCII-8BIT, which is what `Dir.glob` hands back under
    # LC_ALL=C: it is `valid_encoding?`, so a plain `casecmp?` accepted it as
    # a valid string and then folded nothing, and it walked past the guard.
    # The early guard is ASCII-only ON PURPOSE. Anything beyond ASCII casing
    # is settled by the filesystem in the .case_path examples below, because
    # predicting a volume's own folding from a String is not winnable.
    %w[SUMMARY Summary sUmMaRy].each do |cased|
      it "refuses the id #{cased} before any directory is touched" do
        reserved = CorpusRunner::Case.new(id: cased)
        allow(CorpusRunner).to receive(:imported_cases).and_return([reserved])

        expect { CorpusRunner.cases }
          .to raise_error(ArgumentError, /collides with summary\.json/)
      end
    end

    it "answers for an id whose encoding is invalid, instead of raising" do
      # `casecmp?` RAISES on a string with invalid encoding rather than
      # answering false, so such an id used to surface Ruby's own
      # "input string invalid" from inside the guard. It is not a collision --
      # "SUMMARY\xff.json" is a different filename -- so the guard must let it
      # through, and the point is that it decides rather than blowing up.
      broken = "SUMMARY\xff".dup.force_encoding("UTF-8")
      allow(CorpusRunner).to receive(:imported_cases)
        .and_return([CorpusRunner::Case.new(id: broken)])

      expect(CorpusRunner.cases.map(&:id)).to include(broken)
    end

    it "accepts ISO-8859-1 bytes that only LOOK like the reserved name" do
      # "\xC5\xBFummary" in ISO-8859-1 is not summary. An earlier fix
      # reinterpreted such bytes as UTF-8, read them as "\u017Fummary", and
      # refused the case -- though both files coexist happily on disk. This
      # pins the rejection of that approach: restoring it turns this red.
      latin1 = "\xC5\xBFummary".dup.force_encoding(Encoding::ISO_8859_1)
      allow(CorpusRunner).to receive(:imported_cases)
        .and_return([CorpusRunner::Case.new(id: latin1)])

      expect(CorpusRunner.cases.map(&:id)).to include(latin1)
    end

    # The ids differ, the file names do not: 1 and "1" both dump to
    # 1.json. One dump overwrote the other while summary.json still
    # counted two cases, so a case vanished from the snapshot every later
    # slice diffs against.
    it "refuses two ids that become the same dump file name" do
      pair = [CorpusRunner::Case.new(id: 1), CorpusRunner::Case.new(id: "1")]
      allow(CorpusRunner).to receive(:imported_cases).and_return(pair)

      expect { CorpusRunner.cases }
        .to raise_error(ArgumentError, /become the same dump file name/)
    end

    # Refused on a case-sensitive filesystem too, where Foo.json and
    # foo.json really are two files. A corpus that works on Linux and
    # quietly loses a case on macOS is the worse outcome.
    it "refuses two ids that differ only in ASCII case" do
      pair = %w[Foo foo].map { |id| CorpusRunner::Case.new(id: id) }
      allow(CorpusRunner).to receive(:imported_cases).and_return(pair)

      expect { CorpusRunner.cases }
        .to raise_error(ArgumentError, /become the same dump file name/)
    end

    it "still accepts an id that merely contains the reserved word" do
      fine = CorpusRunner::Case.new(id: "notsummary")
      allow(CorpusRunner).to receive(:imported_cases).and_return([fine])

      # `cases` returns the fixture corpus alongside the imported ones, so
      # this asserts the id survived rather than that it is the only one.
      expect(CorpusRunner.cases.map(&:id)).to include("notsummary")
    end
  end

  describe CorpusRunner, ".run ordering" do
    it "creates no directory when case discovery fails" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "fresh")
        allow(CorpusRunner).to receive(:cases).and_raise(ArgumentError, "boom")

        expect { CorpusRunner.run(out) }.to raise_error(ArgumentError, "boom")

        # Claiming creates the directory and writes the marker. Doing it
        # before discovery left one behind on every failed run.
        expect(File.directory?(out)).to be(false)
      end
    end

    # Pruning used to run BEFORE the case ids were checked, so a corpus
    # with one bad id deleted the last good dump and then aborted.
    it "deletes nothing when a case id is unusable" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, CorpusRunner::OWNER_MARKER), "mine")
        File.write(File.join(dir, "summary.json"),
                   JSON.generate("cases" => [{ "id" => "old" }]))
        File.write(File.join(dir, "old.json"), "{}")
        allow(CorpusRunner).to receive(:cases)
          .and_return([CorpusRunner::Case.new(id: "../invalid")])

        expect { CorpusRunner.run(dir) }
          .to raise_error(ArgumentError, /does not name a file inside/)

        expect(File.exist?(File.join(dir, "old.json"))).to be(true)
      end
    end

    # `strip` RAISES on invalid bytes rather than answering, so this id
    # used to surface Ruby's own Encoding::CompatibilityError from inside
    # case_path, after the directory was already claimed.
    it "refuses an id with invalid bytes before touching any directory" do
      broken = "case\xff".dup.force_encoding("UTF-8")

      Dir.mktmpdir do |dir|
        out = File.join(dir, "dump")
        allow(CorpusRunner).to receive(:cases)
          .and_return([CorpusRunner::Case.new(id: broken)])

        expect { CorpusRunner.run(out) }
          .to raise_error(ArgumentError, /does not name a file inside/)
        expect(File.directory?(out)).to be(false)
      end
    end
  end

  describe CorpusRunner, ".case_path" do
    # A case id becomes a filename, and importers are a documented extension
    # point, so an id is not assumed to be a plain name. This guard had NO
    # spec at all -- the traversal its own comment names was never exercised.
    outdir = "/tmp/corpus-outdir"

    {
      "climbing out of the directory" => "../victim",
      "carrying a separator" => "a/b",
      "empty" => "",
      "only whitespace" => "   ",
    }.each do |name, id|
      it "refuses an id that is #{name}" do
        expect { CorpusRunner.send(:case_path, outdir, id) }
          .to raise_error(ArgumentError, /does not name a file inside/)
      end
    end

    it "refuses an id whose path is a link to summary.json" do
      # The fold and casing examples below only exercise refusal where the
      # VOLUME folds; on a case-sensitive disk they take the accepting branch
      # and prove nothing. A symlink aliases on EVERY filesystem, so this
      # covers the refusal path on every machine.
      #
      # The exact name "summary" would not work here. Through the CLI the
      # ASCII guard rejects it at `cases` time; and called directly, as this
      # example does, `case_path` returns early because the path IS the
      # summary -- the runner must be able to write its own index.
      Dir.mktmpdir do |dir|
        summary = File.join(dir, "summary.json")
        File.write(summary, "{}")
        File.symlink("summary.json", File.join(dir, "aliased.json"))

        expect { CorpusRunner.send(:case_path, dir, "aliased") }
          .to raise_error(ArgumentError, /names the same file as summary/)
      end
    end

    # These are the ids the early ASCII guard cannot settle. Unicode folds
    # long s to s and macOS resolves it to one file; the same bytes arrive as
    # ASCII-8BIT from `Dir.glob` under LC_ALL=C, and as other encodings under
    # other locales. Rather than predict any of that, the runner writes
    # summary.json first and asks whether the case path is File.identical? to
    # it -- which is the property, answered by the thing that decides it.
    {
      "an ASCII casing" => "SUMMARY",
      "a Unicode fold" => "\u017Fummary",
      "the same fold as binary bytes" =>
        "\u017Fummary".dup.force_encoding(Encoding::ASCII_8BIT),
    }.each do |label, id|
      it "refuses #{label} when it names summary.json on this disk" do
        Dir.mktmpdir do |dir|
          summary = File.join(dir, "summary.json")
          File.write(summary, "{}")

          # Whether these spellings alias is a property of the VOLUME, not of
          # the id. On a case-sensitive filesystem they are genuinely
          # different files and accepting them is the correct answer -- a
          # run on /Volumes/CS3 failed all three of these before this guard.
          # So the example asserts the rule the code follows, either way.
          candidate = File.join(dir, "#{id}.json")
          aliases = File.exist?(candidate) &&
            File.identical?(candidate, summary)

          if aliases
            expect { CorpusRunner.send(:case_path, dir, id) }
              .to raise_error(ArgumentError, /names the same file as summary/)
          else
            expect(CorpusRunner.send(:case_path, dir, id)).to eq(candidate)
          end
        end
      end
    end

    it "refuses an aliasing id on the SECOND run too" do
      # The placeholder used to be written inside the claim, and the claim
      # returns early for a directory it already owns -- so on run 2 there was
      # no placeholder to compare against and the aliasing case sailed through
      # to the write, where the final summary overwrote its payload.
      long_s = "\u017Fummary"
      kase = CorpusRunner::Case.new(
        id: long_s, algorithm: "layered",
        graph: { "id" => "g", "children" => [], "edges" => [] }
      )
      allow(CorpusRunner).to receive(:cases).and_return([kase])

      Dir.mktmpdir do |dir|
        out = File.join(dir, "dump")
        summary = File.join(out, "summary.json")
        FileUtils.mkdir_p(out)
        File.write(summary, "{}")
        skip "needs a case-insensitive filesystem" unless
          File.identical?(File.join(out, "#{long_s}.json"), summary)
        FileUtils.rm_rf(out)

        2.times do
          expect { CorpusRunner.run(out) }
            .to raise_error(ArgumentError, /names the same file as summary/)
        end
      end
    end

    it "keeps an ordinary id inside the output directory" do
      expect(CorpusRunner.send(:case_path, outdir, "simple_graph"))
        .to eq(File.join(outdir, "simple_graph.json"))
    end

    it "treats a leading tilde as a literal name, not a home directory" do
      # File.expand_path would have expanded this, escaping outdir before the
      # guard ran, or raising Ruby's own "user doesn't exist" instead.
      expect(CorpusRunner.send(:case_path, outdir, "~root"))
        .to eq(File.join(outdir, "~root.json"))
    end
  end

  describe CorpusRunner, ".exit_code" do
    # The measured truth table proved this behaves correctly, but nothing
    # committed preserved it: deleting the zero-total branch left every
    # committed example green. The outcomes ARE the property, so they are a
    # table rather than four hand-written examples.
    {
      "an empty run" => [{ "total" => 0, "cases" => [] }, 1],
      "a summary with no total at all" => [{ "cases" => [] }, 1],
      "an all-ok run" => [{ "total" => 2,
                            "cases" => [{ "status" => "ok" },
                                        { "status" => "ok" }] }, 0],
      "a declared failure" => [{ "total" => 1,
                                 "cases" => [{ "status" => "error",
                                               "expected" => true }] }, 0],
      "a fresh regression" => [{ "total" => 1,
                                 "cases" => [{ "status" => "error" }] }, 1],
    }.each do |name, (summary, expected)|
      it "exits #{expected} for #{name}" do
        summary["unexpected_failures"] =
          CorpusRunner.send(:unexpected_failure?, summary)

        expect(CorpusRunner.exit_code(summary)).to eq(expected)
      end
    end
  end

  describe CorpusRunner, ".run" do
    # AlgorithmRegistry holds process-wide state, and one example below
    # registers a deliberately slow algorithm into it.
    around do |example|
      registry = Elkrb::Layout::AlgorithmRegistry
      algorithms = registry.instance_variable_get(:@algorithms).dup
      metadata = registry.instance_variable_get(:@metadata).dup
      example.run
      registry.instance_variable_set(:@algorithms, algorithms)
      registry.instance_variable_set(:@metadata, metadata)
    end

    it "refuses the destination before creating it when the guard says so" do
      allow(CorpusRunner).to receive(:source_directory?).and_return(true)

      Dir.mktmpdir do |tmp|
        outdir = File.join(tmp, "dump")

        expect { CorpusRunner.run(outdir) }
          .to raise_error(ArgumentError,
                          /refusing to dump into a corpus source directory/)
        expect(Dir.exist?(outdir)).to be(false)
      end
    end

    # A dump is compared with `diff -r`, and validate:run reuses tmp/corpus
    # every time, so a case that was renamed or dropped must not leave its
    # old file behind to be reported as a difference forever.
    #
    # Only the case list is stubbed. Pruning, the summary and every file
    # write are the real thing, so these examples still fail if any of them
    # regresses; the stub only keeps two full 47-case runs out of an
    # example that does not need them.
    def trivial_case(id)
      CorpusRunner::Case.new(
        id: id, algorithm: "layered",
        graph: { "id" => "root", "children" => [], "edges" => [] }
      )
    end

    def corpus_of(*ids)
      allow(CorpusRunner).to receive(:cases)
        .and_return(ids.map { |id| trivial_case(id) })
    end

    it "deletes a case file the corpus no longer names" do
      corpus_of("kept", "renamed_away")

      Dir.mktmpdir do |dir|
        CorpusRunner.run(dir)
        expect(File.exist?(File.join(dir, "renamed_away.json"))).to be(true)

        corpus_of("kept")
        File.write(File.join(dir, "notes.txt"), "mine")
        CorpusRunner.run(dir)

        expect(File.exist?(File.join(dir, "renamed_away.json"))).to be(false)
        expect(File.exist?(File.join(dir, "kept.json"))).to be(true)
        expect(File.exist?(File.join(dir, "summary.json"))).to be(true)
        expect(File.exist?(File.join(dir, "notes.txt"))).to be(true)
      end
    end

    it "refuses a directory it does not own, and touches nothing in it" do
      corpus_of("kept")

      Dir.mktmpdir do |dir|
        # This used to RUN here and merely promise not to delete. That promise
        # rested on reading the directory's own summary.json as proof of
        # provenance, and an unrelated file of the right shape was accepted as
        # that proof. Refusing outright is the guarantee that does not depend
        # on guessing who wrote what.
        File.write(File.join(dir, "someones.json"), "{}")
        before_entries = Dir.children(dir).sort

        expect do
          CorpusRunner.run(dir)
        end.to raise_error(ArgumentError, /does not own/)

        # Compare the WHOLE listing, not just the file we planted: a run that
        # dropped its own marker in before raising would leave someones.json
        # intact and still pass a narrower assertion.
        expect(Dir.children(dir).sort).to eq(before_entries)
        expect(File.read(File.join(dir, "someones.json"))).to eq("{}")
      end
    end

    it "adopts an empty directory and runs there again afterwards" do
      corpus_of("kept")

      Dir.mktmpdir do |dir|
        # An EXISTING empty directory, not an absent one. Those are different
        # branches and only the absent one was covered.
        empty = File.join(dir, "dump")
        FileUtils.mkdir_p(empty)

        CorpusRunner.run(empty)
        expect(File.exist?(File.join(empty, CorpusRunner::OWNER_MARKER)))
          .to be(true)

        # Make the second run's work observable. Delete the case dump and
        # require the second run to put it back -- otherwise a second run
        # that did nothing at all would pass.
        FileUtils.rm_f(File.join(empty, "kept.json"))
        CorpusRunner.run(empty)

        expect(File.exist?(File.join(empty, "kept.json"))).to be(true)
        # The marker has to SURVIVE the second run. Stale-dump pruning runs
        # over this directory, and a regression that swept the marker away
        # would make every later run refuse the directory it owns.
        expect(File.exist?(File.join(empty, CorpusRunner::OWNER_MARKER)))
          .to be(true)
      end
    end

    # One run is not enough to see this. `run` is what writes summary.json,
    # so the first run used to manufacture the second run's licence: run 1
    # left a summary behind and run 2 read it as proof the directory was
    # ours. Reading the directory's own summary as provenance is the part
    # that was wrong -- an unrelated file of the same shape was accepted as
    # that proof. Ownership is now an explicit marker the runner writes.
    it "refuses the same directory on a second run, not just the first" do
      corpus_of("kept")

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "someones.json"), "{}")
        File.write(File.join(dir, "notes.txt"), "mine")

        2.times do
          expect do
            CorpusRunner.run(dir)
          end.to raise_error(ArgumentError, /does not own/)
        end

        # One run used to manufacture the next run's licence: it left a
        # summary.json behind, and the second run read that as proof the whole
        # directory was its own. Refusing both times is what closes that.
        expect(File.read(File.join(dir, "someones.json"))).to eq("{}")
        expect(File.read(File.join(dir, "notes.txt"))).to eq("mine")
      end
    end

    # Kernel.srand is process-wide. The suite seeds deliberately, and two
    # algorithms call bare `rand`, so a reseed left in place would decide
    # what every later example sees.
    #
    # This asserts the SEED is put back, which is all `srand` can do. It does
    # NOT assert the stream resumes where the caller left off, because it does
    # not: `srand(previous)` restarts that seed's sequence from its first
    # value. Naming the weaker property is the point -- the example used to
    # read as though position were restored.
    it "restores the caller's random seed" do
      corpus_of("kept")

      Dir.mktmpdir do |dir|
        previous = Kernel.srand(12_345)
        CorpusRunner.run(dir)

        expect(Kernel.srand(previous)).to eq(12_345)
      end
    end

    it "has no unexpected failures over the real corpus" do
      Dir.mktmpdir do |dir|
        summary = CorpusRunner.run(dir)
        expect(summary["unexpected_failures"]).to be(false)
      end
    end

    # The four outcomes the dump has to handle, shared by the examples
    # below. Each case is here for a reason:
    #
    # - ok: width/height 10/3 forces layered's own arithmetic (centring,
    #   padding) to produce a Float with far more than 6 decimal digits
    #   before canonicalize rounds it. A 1.0/1.0 node never exercises
    #   rounding, since layered never needs to divide it further.
    # - boom: a nil graph, so the case errors.
    # - force: force calls Kernel#rand. Only a case that actually consumes
    #   randomness can prove the per-case srand reseed makes two runs
    #   agree -- a layered-only corpus passes "stable across two runs"
    #   even with the reseed deleted.
    # - slow: sleeps far longer than the 0.02s timeout below, so a loaded
    #   CI box cannot let it finish before the timeout it is here to
    #   trigger. Nothing waits it out: Timeout interrupts the sleep.
    def mixed_corpus
      slow_algorithm = Class.new(Elkrb::Layout::Algorithms::BaseAlgorithm) do
        def layout_flat(_graph, _options = {})
          sleep 5
        end
      end
      Elkrb::Layout::AlgorithmRegistry
        .register("corpus_runner_spec_slow", slow_algorithm)

      corpus = [
        sized_case("ok", "layered", 10.0 / 3),
        CorpusRunner::Case.new(id: "boom", algorithm: "layered", graph: nil),
        sized_case("force", "force", 10.0),
        CorpusRunner::Case.new(
          id: "slow", algorithm: "corpus_runner_spec_slow",
          graph: { "id" => "root", "children" => [], "edges" => [] }
        ),
      ]
      allow(CorpusRunner).to receive(:cases).and_return(corpus)
      corpus
    end

    def sized_case(id, algorithm, side)
      CorpusRunner::Case.new(
        id: id, algorithm: algorithm,
        graph: {
          "id" => "root",
          "children" => [
            { "id" => "a", "width" => side, "height" => side },
            { "id" => "b", "width" => side, "height" => side },
          ],
          "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }],
        }
      )
    end

    def run_mixed_corpus(dir)
      mixed_corpus
      CorpusRunner.run(dir, timeout: 0.02)
    end

    it "counts every case and writes the same summary it returns" do
      Dir.mktmpdir do |dir|
        summary = run_mixed_corpus(dir)

        expect(summary["total"]).to eq(4)
        expect(summary["ok"]).to eq(2)
        expect(summary["error"]).to eq(1)
        expect(summary["timeout"]).to eq(1)
        expect(JSON.parse(File.read(File.join(dir, "summary.json"))))
          .to eq(summary)
      end
    end

    # boom and slow both carry expect: nil, so neither matches its own
    # outcome: this corpus must be flagged and the CLI must exit non-zero.
    it "flags a corpus whose failures were not declared" do
      Dir.mktmpdir do |dir|
        summary = run_mixed_corpus(dir)

        expect(summary["unexpected_failures"]).to be(true)
        expect(CorpusRunner.exit_code(summary)).to eq(1)
      end
    end

    it "writes a dump for every case, whatever its outcome" do
      Dir.mktmpdir do |dir|
        run_mixed_corpus(dir)

        expect(JSON.parse(File.read(File.join(dir, "ok.json"))))
          .to include("id" => "root")
        # Any exception class is acceptable here: the contract is "a nil
        # graph errors out with a class+message payload", not which class
        # Elkrb.layout happens to raise for nil today.
        expect(JSON.parse(File.read(File.join(dir, "boom.json")))["error"])
          .to match(/\A\w+(::\w+)*: /)
        expect(JSON.parse(File.read(File.join(dir, "slow.json"))))
          .to eq("error" => "Timeout")
      end
    end

    # Canonical means deep-sorted keys and floats rounded to 6 places, not
    # just "some JSON got written". The raw text is parsed (not a fresh
    # Hash literal) so the file's actual on-disk key order is preserved.
    it "writes canonical JSON: sorted keys, floats rounded to 6 places" do
      Dir.mktmpdir do |dir|
        run_mixed_corpus(dir)

        ok = JSON.parse(File.read(File.join(dir, "ok.json")))
        assert_deep_sorted_keys(ok)
        assert_rounded_floats(ok)
        force = JSON.parse(File.read(File.join(dir, "force.json")))
        assert_rounded_floats(force)
      end
    end

    it "writes the same bytes when the same corpus is dumped again" do
      Dir.mktmpdir do |first|
        run_mixed_corpus(first)

        Dir.mktmpdir do |second|
          run_mixed_corpus(second)

          %w[ok.json force.json].each do |name|
            expect(File.read(File.join(second, name)))
              .to eq(File.read(File.join(first, name)))
          end
        end
      end
    end

    # `File.write` FOLLOWS a symlink, so a link planted in a directory the
    # runner owns sent a dump straight out of it -- measured, a case wrote
    # over a file in the parent directory. Writing through a temp file and
    # renaming replaces the link itself.
    it "replaces a symlink in the dump instead of writing through it" do
      corpus_of("kept")

      Dir.mktmpdir do |tmp|
        victim = File.join(tmp, "victim.txt")
        File.write(victim, "not mine")
        dir = File.join(tmp, "dump")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, CorpusRunner::OWNER_MARKER), "mine")
        File.symlink(victim, File.join(dir, "kept.json"))

        CorpusRunner.run(dir)

        expect(File.read(victim)).to eq("not mine")
        expect(File.symlink?(File.join(dir, "kept.json"))).to be(false)
      end
    end

    # Two runs pointed at one directory used to interleave, leaving files
    # that neither summary.json described. flock on a second descriptor is
    # refused even inside one process, so this asserts the real lock.
    it "holds an exclusive lock on the dump directory while it works" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, CorpusRunner::OWNER_MARKER)
        File.write(marker, "mine")

        inside = nil
        CorpusRunner.send(:with_directory_lock, dir) do
          inside = lockable?(marker)
        end

        expect(inside).to be(false)
        expect(lockable?(marker)).to be(true)
      end
    end

    # The lock is held on an open file description, so it protects an INODE,
    # not a path. Installing the marker by renaming a temp file over it gave
    # two runs whose claims interleaved a lock each, on two different inodes,
    # and neither blocked -- measured 28 of 30 concurrent trials. So the
    # marker's inode has to be installed exactly once, and these three pin
    # that from three directions.
    #
    # The create step is reached directly rather than through
    # `claim_output_directory!`, because once the marker exists the claim
    # returns early and the step is unreachable. That unreachability IS the
    # defect: the racing run decided to create before the winner's marker
    # appeared.

    # A DIAGNOSTIC rather than a unit of coverage -- it names the inode, so a
    # failure points at the rename instead of at the lock. The content is
    # asserted here because nothing else in the suite does, which let a
    # create step writing no bytes at all stay green.
    it "installs the owner marker once, leaving the first inode in place" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, CorpusRunner::OWNER_MARKER)

        CorpusRunner.send(:create_owner_marker, marker)
        first = File.stat(marker).ino
        CorpusRunner.send(:create_owner_marker, marker)

        expect(File.stat(marker).ino).to eq(first)
        expect(File.read(marker)).to eq(CorpusRunner::OWNER_MARKER_TEXT)
      end
    end

    it "keeps the directory excluded while a racing run performs its claim" do
      Dir.mktmpdir do |dir|
        outdir = File.join(dir, "dump")
        marker = File.join(outdir, CorpusRunner::OWNER_MARKER)
        CorpusRunner.send(:claim_output_directory!, outdir)

        still_excluded = nil
        CorpusRunner.send(:with_directory_lock, outdir) do
          CorpusRunner.send(:create_owner_marker, marker)
          still_excluded = !lockable?(marker)
        end

        expect(still_excluded).to be(true)
      end
    end

    # The one input that separates an atomic exclusive create from an
    # `unless File.exist?` guard, which is the refactor most likely to land
    # here -- `place_summary_marker` uses that exact idiom a few lines below
    # the lock. `File.exist?` FOLLOWS a symlink, so on a dangling one it
    # reports false and the guard writes through the link; O_CREAT|O_EXCL
    # tests the link itself and refuses. Both shapes satisfy every other
    # example in this file, so without this one the suite cannot tell them
    # apart.
    it "refuses to create the owner marker through a dangling symlink" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, CorpusRunner::OWNER_MARKER)
        target = File.join(dir, "absent-target")
        File.symlink(target, marker)

        CorpusRunner.send(:create_owner_marker, marker)

        expect(File.symlink?(marker)).to be(true)
        expect(File.exist?(target)).to be(false)
      end
    end

    def lockable?(path)
      File.open(path, File::RDONLY) do |file|
        next false unless file.flock(File::LOCK_EX | File::LOCK_NB)

        file.flock(File::LOCK_UN)
        true
      end
    end
  end

  def assert_deep_sorted_keys(value)
    case value
    when Hash
      keys = value.keys
      expect(keys).to eq(keys.sort), "keys not sorted: #{keys.inspect}"
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
      expect(value.round(6)).to(
        eq(value),
        "#{value} has more than 6 decimal places",
      )
    end
  end
end
