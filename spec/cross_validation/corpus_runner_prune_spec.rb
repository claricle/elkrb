# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require_relative "corpus_runner"

# `prune_stale_dumps` deletes from a destination the caller chose, so what
# it may delete is the whole design. The set is the ids the previous
# summary.json recorded minus the ids this run writes, resolved against
# what the directory actually holds.
#
# Two shapes are pinned here.
#
# The delete set itself: a file the previous summary did not record is
# never a candidate, and a summary that cannot be read as one of ours
# records nothing. Building the set the other way round -- every *.json
# that is not a current case -- is what let `run` authorise itself, since
# `run` is what writes the summary the next run reads.
#
# Reaching a sibling: `base:` scopes the glob to the directory itself.
# Joining the destination into the pattern instead let a metacharacter in
# it escape. `*` still matches its own directory, so it ADDS siblings'
# files; `[...]` and `{...}` do not match it, so the directory is never
# listed at all.
RSpec.describe CorpusRunner, ".prune_stale_dumps" do
  # Each scenario gets its own parent. Sharing one would let the patterns
  # match each other's directories and manufacture findings that are not real.
  def in_isolated_parent(&)
    Dir.mktmpdir(&)
  end

  def make_dir(parent, name, files)
    dir = File.join(parent, name)
    Dir.mkdir(dir)
    files.each { |f| File.write(File.join(dir, f), "{}") }
    dir
  end

  # A directory as this runner leaves it: one file per case it wrote, and
  # the summary.json recording which ids those were.
  def previous_dump(parent, name, ids, extra: [])
    dir = make_dir(parent, name, ids.map { |id| "#{id}.json" } + extra)
    write_summary(dir, "cases" => ids.map { |id| { "id" => id } })
    dir
  end

  def write_summary(dir, value)
    File.write(File.join(dir, "summary.json"),
               value.is_a?(String) ? value : JSON.generate(value))
  end

  def prune(outdir, keep_ids)
    corpus = keep_ids.map { |id| CorpusRunner::Case.new(id: id) }
    CorpusRunner.send(:prune_stale_dumps, outdir, corpus)
  end

  def names_in(dir)
    Dir.children(dir).sort
  end

  it "removes a recorded dump the corpus no longer names" do
    in_isolated_parent do |parent|
      dir = previous_dump(parent, "dumps", %w[live stale])

      prune(dir, ["live"])

      expect(names_in(dir)).to eq(%w[live.json summary.json])
    end
  end

  it "removes a recorded dot-prefixed dump the corpus no longer names" do
    in_isolated_parent do |parent|
      dir = previous_dump(parent, "dumps", %w[live .retired])

      prune(dir, ["live"])

      expect(names_in(dir)).to eq(%w[live.json summary.json])
    end
  end

  it "keeps a file the previous summary did not record" do
    in_isolated_parent do |parent|
      dir = previous_dump(parent, "dumps", %w[live stale],
                          extra: %w[someones.json])

      prune(dir, ["live"])

      expect(names_in(dir)).to eq(%w[live.json someones.json summary.json])
    end
  end

  it "leaves a directory alone when it holds no summary of its own" do
    in_isolated_parent do |parent|
      dir = make_dir(parent, "untouched", %w[precious.json])

      prune(dir, ["live"])

      expect(names_in(dir)).to eq(%w[precious.json])
    end
  end

  it "deletes nothing when the summary is not JSON" do
    in_isolated_parent do |parent|
      dir = make_dir(parent, "dumps", %w[stale.json])
      write_summary(dir, "not json at all")

      prune(dir, ["live"])

      expect(names_in(dir)).to eq(%w[stale.json summary.json])
    end
  end

  it "deletes nothing when the summary records no cases" do
    in_isolated_parent do |parent|
      dir = make_dir(parent, "dumps", %w[stale.json])
      write_summary(dir, "total" => 0)

      prune(dir, ["live"])

      expect(names_in(dir)).to eq(%w[stale.json summary.json])
    end
  end

  # A recorded id is resolved against the directory's own listing, so a
  # summary this runner did not write cannot name a path outside it.
  it "cannot delete outside the directory through a recorded id" do
    in_isolated_parent do |parent|
      neighbour = make_dir(parent, "neighbour", %w[precious.json])
      dir = make_dir(parent, "dumps", [])
      write_summary(dir, "cases" => [{ "id" => "../neighbour/precious" }])

      prune(dir, ["live"])

      expect(names_in(neighbour)).to eq(%w[precious.json])
    end
  end

  # `*` matches its own directory, so a joined pattern pruned there AND
  # reached out.
  it "does not reach a sibling when the name holds a star" do
    in_isolated_parent do |parent|
      starred = previous_dump(parent, "dump*", %w[live stale])
      sibling = previous_dump(parent, "dumpster", %w[stale])

      prune(starred, ["live"])

      expect(names_in(sibling)).to eq(%w[stale.json summary.json])
      expect(names_in(starred)).to eq(%w[live.json summary.json])
    end
  end

  # `[...]` does NOT match its own directory. A joined pattern listed only
  # the sibling, so the real directory kept its stale dump while the
  # sibling lost a file it never offered.
  it "does not reach a sibling when the name holds a bracket class" do
    in_isolated_parent do |parent|
      bracketed = previous_dump(parent, "my[x]work", %w[live stale])
      sibling = previous_dump(parent, "myxwork", %w[stale])

      prune(bracketed, ["live"])

      expect(names_in(sibling)).to eq(%w[stale.json summary.json])
      expect(names_in(bracketed)).to eq(%w[live.json summary.json])
    end
  end

  it "does not reach a sibling when the name holds a brace list" do
    in_isolated_parent do |parent|
      braced = previous_dump(parent, "my{a,b}work", %w[live stale])
      sibling = previous_dump(parent, "myawork", %w[stale])

      prune(braced, ["live"])

      expect(names_in(sibling)).to eq(%w[stale.json summary.json])
      expect(names_in(braced)).to eq(%w[live.json summary.json])
    end
  end
end
