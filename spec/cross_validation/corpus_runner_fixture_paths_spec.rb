# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "corpus_runner"

# `fixture_paths` globs the three corpus source directories, and each of them
# is built from `ROOT` -- the checkout path, wherever the repo happens to sit.
# Before the `base:` fix the directory was joined into the pattern, so a glob
# metacharacter in that path was interpreted rather than matched: the glob and
# the later `File.read` disagreed about which directory was meant.
#
# The two families fail differently, so both are pinned here. `*` and `?` still
# match their own directory, so they ADD a sibling's files. `[...]`, `{...}`
# and an unclosed `[` do not match it, so the listing is either entirely
# foreign or empty.
#
# Each example asserts the whole absolute-path list, which pins both
# directions at once: a sibling's file would show up in it, and a missing file
# of the directory's own would drop out of it.
RSpec.describe CorpusRunner, ".fixture_paths" do
  # Each scenario gets its own parent. Sharing one would let the patterns match
  # each other's directories and manufacture findings that are not real.
  def in_isolated_parent(&)
    Dir.mktmpdir(&)
  end

  def fixture_dir(parent, name, files)
    dir = File.join(parent, name)
    files.each do |rel|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "{}")
    end
    dir
  end

  def fixture_paths(dir, pattern)
    CorpusRunner.send(:fixture_paths, dir, pattern)
  end

  def expected(dir, *names)
    names.map { |name| File.join(dir, name) }
  end

  it "lists the directory it was given and nothing beside it" do
    in_isolated_parent do |parent|
      dir = fixture_dir(parent, "fixtures", %w[a.json b.json notes.txt])
      fixture_dir(parent, "other", %w[foreign.json])

      expect(fixture_paths(dir, "*.json"))
        .to eq(expected(dir, "a.json", "b.json"))
    end
  end

  it "returns nothing for a directory that does not exist" do
    in_isolated_parent do |parent|
      expect(fixture_paths(File.join(parent, "absent"), "*.json")).to be_empty
    end
  end

  # `*` matches its own directory, so the old form listed there AND reached out.
  it "does not reach a sibling when the name holds a star" do
    in_isolated_parent do |parent|
      starred = fixture_dir(parent, "fix*", %w[a.json b.json])
      fixture_dir(parent, "fixtures", %w[foreign.json])

      expect(fixture_paths(starred, "*.json"))
        .to eq(expected(starred, "a.json", "b.json"))
    end
  end

  it "does not reach a sibling when the name holds a question mark" do
    in_isolated_parent do |parent|
      marked = fixture_dir(parent, "fix?ures", %w[a.json b.json])
      fixture_dir(parent, "fixtures", %w[foreign.json])

      expect(fixture_paths(marked, "*.json"))
        .to eq(expected(marked, "a.json", "b.json"))
    end
  end

  # `[...]` does NOT match its own directory. The old form listed only the
  # sibling, so the corpus became entirely foreign.
  it "does not read a sibling when the name holds a bracket class" do
    in_isolated_parent do |parent|
      bracketed = fixture_dir(parent, "fix[t]ures", %w[a.json b.json])
      fixture_dir(parent, "fixtures", %w[foreign.json])

      expect(fixture_paths(bracketed, "*.json"))
        .to eq(expected(bracketed, "a.json", "b.json"))
    end
  end

  it "does not read a sibling when the name holds a brace list" do
    in_isolated_parent do |parent|
      braced = fixture_dir(parent, "fix{t,T}ures", %w[a.json b.json])
      fixture_dir(parent, "fixtures", %w[foreign.json])

      expect(fixture_paths(braced, "*.json"))
        .to eq(expected(braced, "a.json", "b.json"))
    end
  end

  # An unclosed `[` matches nothing at all, so the old form returned an empty
  # list however many files the directory held.
  it "lists a directory whose name holds an unclosed bracket" do
    in_isolated_parent do |parent|
      unclosed = fixture_dir(parent, "fix[tures", %w[a.json b.json])

      expect(fixture_paths(unclosed, "*.json"))
        .to eq(expected(unclosed, "a.json", "b.json"))
    end
  end

  # `imported_cases` globs a directory component, not just a basename, so the
  # metacharacter and the wildcard sit in different components.
  it "does not reach a sibling for a pattern with a directory component" do
    in_isolated_parent do |parent|
      bracketed = fixture_dir(parent, "fix[t]ures",
                              %w[elkjs/imported_tests.json
                                 java_elk/imported_tests.json])
      fixture_dir(parent, "fixtures", %w[foreign/imported_tests.json])

      expect(fixture_paths(bracketed, "*/imported_tests.json"))
        .to eq(expected(bracketed,
                        "elkjs/imported_tests.json",
                        "java_elk/imported_tests.json"))
    end
  end
end
