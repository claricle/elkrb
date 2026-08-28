# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "corpus_runner"

# `prune_stale_dumps` is given a destination the caller chose. Before the
# `base:` fix it built a glob by joining that destination into the pattern,
# so a metacharacter in the destination escaped the directory: `File.file?`
# read the path literally while `Dir[]` globbed it, and the two disagreed
# about which directory was meant.
#
# The two metacharacter families fail differently, so both are pinned here.
# `*` and `?` still match their own directory, so they ADD siblings' files to
# the delete set. `[...]` and `{...}` do not match it, so the real directory
# is never listed and the set becomes entirely foreign.
RSpec.describe CorpusRunner, ".prune_stale_dumps" do
  # Each scenario gets its own parent. Sharing one would let the patterns
  # match each other's directories and manufacture findings that are not real.
  def in_isolated_parent(&)
    Dir.mktmpdir(&)
  end

  def dump_dir(parent, name, files)
    dir = File.join(parent, name)
    Dir.mkdir(dir)
    files.each { |f| File.write(File.join(dir, f), "{}") }
    dir
  end

  def prune(outdir, keep_ids)
    corpus = keep_ids.map { |id| CorpusRunner::Case.new(id: id) }
    CorpusRunner.send(:prune_stale_dumps, outdir, corpus)
  end

  def names_in(dir)
    Dir.children(dir).sort
  end

  it "removes a stale dump from the directory it was given" do
    in_isolated_parent do |parent|
      dir = dump_dir(parent, "dumps", %w[summary.json live.json stale.json])

      prune(dir, ["live"])

      expect(names_in(dir)).to eq(%w[live.json summary.json])
    end
  end

  it "leaves a directory alone when it holds no summary of its own" do
    in_isolated_parent do |parent|
      dir = dump_dir(parent, "untouched", %w[precious.json])

      prune(dir, ["live"])

      expect(names_in(dir)).to eq(%w[precious.json])
    end
  end

  # `*` matches its own directory, so the old code pruned there AND reached out.
  it "does not reach a sibling when the name holds a star" do
    in_isolated_parent do |parent|
      starred = dump_dir(parent, "dump*",
                         %w[summary.json live.json stale.json])
      sibling = dump_dir(parent, "dumpster", %w[precious.json])

      prune(starred, ["live"])

      expect(names_in(sibling)).to eq(%w[precious.json])
      expect(names_in(starred)).to eq(%w[live.json summary.json])
    end
  end

  # `[...]` does NOT match its own directory. The old code listed only the
  # sibling, so the real directory kept its stale dump while the sibling lost
  # a file it never offered.
  it "does not reach a sibling when the name holds a bracket class" do
    in_isolated_parent do |parent|
      bracketed = dump_dir(parent, "my[x]work",
                           %w[summary.json live.json stale.json])
      sibling = dump_dir(parent, "myxwork", %w[precious.json])

      prune(bracketed, ["live"])

      expect(names_in(sibling)).to eq(%w[precious.json])
      expect(names_in(bracketed)).to eq(%w[live.json summary.json])
    end
  end

  it "does not reach a sibling when the name holds a brace list" do
    in_isolated_parent do |parent|
      braced = dump_dir(parent, "my{a,b}work",
                        %w[summary.json live.json stale.json])
      sibling = dump_dir(parent, "myawork", %w[precious.json])

      prune(braced, ["live"])

      expect(names_in(sibling)).to eq(%w[precious.json])
      expect(names_in(braced)).to eq(%w[live.json summary.json])
    end
  end
end
