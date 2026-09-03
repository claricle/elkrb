# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "corpus_runner"

# Only the coverage this branch actually adds lives here: the two new
# .cases guards (invalid encoding, duplicate output filenames), the two new
# filesystem-alias guards on .run, and the imported-cases ordering fix.
# Every pre-existing CorpusRunner behavior (.source_directory?, .case_path,
# .exit_code, the rest of .run) is already covered in corpus_spec.rb -- a
# first draft of this file duplicated 24 of those examples verbatim, which
# is what spec-auditor caught: two copies of the same assertion can drift
# independently (one already had, over one commit), for zero extra coverage.
RSpec.describe CorpusRunner do
  describe ".cases" do
    it "refuses an id whose encoding is invalid" do
      # The id is also written into summary.json, so letting malformed UTF-8
      # through discovery only moves the failure past directory claiming.
      broken = "SUMMARY\xff".dup.force_encoding("UTF-8")
      allow(CorpusRunner).to receive(:imported_cases)
        .and_return([CorpusRunner::Case.new(id: broken)])

      expect { CorpusRunner.cases }
        .to raise_error(ArgumentError, /does not have a valid encoding/)
    end

    it "refuses distinct ids that become the same output filename" do
      cases = [
        CorpusRunner::Case.new(id: 1),
        CorpusRunner::Case.new(id: "1"),
      ]
      allow(CorpusRunner).to receive(:imported_cases).and_return(cases)

      expect { CorpusRunner.cases }
        .to raise_error(ArgumentError, /map to duplicate files.*1\.json/)
    end
  end

  describe ".run" do
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

    it "refuses two current ids that alias the same existing file" do
      Dir.mktmpdir do |dir|
        corpus_of("real")
        CorpusRunner.run(dir)
        File.symlink("real.json", File.join(dir, "alias.json"))
        corpus_of("real", "alias")

        expect { CorpusRunner.run(dir) }
          .to raise_error(ArgumentError, /name the same output file/)
      end
    end

    it "asks the destination filesystem whether two fresh names alias" do
      corpus_of("fold", "FOLD")

      Dir.mktmpdir do |dir|
        lower = File.join(dir, "fold.json")
        upper = File.join(dir, "FOLD.json")
        File.write(lower, "{}")
        aliases = File.exist?(upper) && File.identical?(lower, upper)
        File.delete(lower)

        if aliases
          expect { CorpusRunner.run(dir) }
            .to raise_error(ArgumentError, /name the same output file/)
        else
          expect { CorpusRunner.run(dir) }.not_to raise_error
          expect(File.exist?(lower)).to be(true)
          expect(File.exist?(upper)).to be(true)
        end
      end
    end

    it "raises naming both ids when the probe reports an EEXIST collision" do
      # The example above defers to the DESTINATION FILESYSTEM: it only takes
      # the raising branch on a case-folding volume. CI runs on ubuntu-latest
      # (ext4, case-sensitive), so it never does there -- this guard's raise
      # path would have zero coverage on the runner that actually matters.
      # Driving refuse_new_case_file_aliases! with a simulated EEXIST
      # exercises the alias-resolution logic on every runner regardless of
      # what that runner's filesystem actually folds.
      seen = []
      allow(File).to receive(:open)
        .and_wrap_original do |original, path, mode, &blk|
        if path.end_with?("fold.json", "FOLD.json")
          seen << path
          raise Errno::EEXIST, path if seen.size == 2
        end
        original.call(path, mode, &blk)
      end
      allow(File).to receive(:identical?).and_wrap_original do |original, a, b|
        seen.include?(a) && seen.include?(b) ? true : original.call(a, b)
      end

      Dir.mktmpdir do |outdir|
        expect do
          CorpusRunner.send(
            :refuse_new_case_file_aliases!,
            outdir,
            [["id-fold", File.join(outdir, "fold.json")],
             ["id-FOLD", File.join(outdir, "FOLD.json")]],
          )
        end.to raise_error(ArgumentError, /"id-fold" and "id-FOLD"/)
      end
    end
  end

  describe ".imported_cases" do
    it "orders imported fixture files by their full path" do
      Dir.mktmpdir do |dir|
        late = File.join(dir, "elkjs-2", "imported_tests.json")
        early = File.join(dir, "elkjs", "imported_tests.json")
        [late, early].each { |path| FileUtils.mkdir_p(File.dirname(path)) }
        graph = { "id" => "root", "children" => [], "edges" => [] }
        File.write(late, JSON.generate([{ "id" => "late", "graph" => graph }]))
        File.write(
          early,
          JSON.generate([{ "id" => "early", "graph" => graph }]),
        )
        allow(CorpusRunner).to receive(:fixture_paths)
          .and_return([early, late])

        expect(CorpusRunner.send(:imported_cases).map(&:id))
          .to eq(%w[late early])
      end
    end
  end
end
