# frozen_string_literal: true

require "open3"

# The provenance guard for `rake fixtures:sirena`.
#
# The fixtures under spec/fixtures/consumers/sirena record what one
# specific sirena commit produces, and their README says to assert that
# commit before re-capturing. Printing the sha and asking a human to
# compare it is not an assertion -- measured, a checkout sitting on the
# wrong sha with a dirty `lib/sirena.rb` reached the capture command,
# which defaults to overwriting the committed fixtures in place.
module SirenaProvenance
  class Mismatch < StandardError; end

  # The `| sirena commit | `<sha>` |` row of the README's provenance
  # table. That row is the ONLY place the expected commit is written
  # down -- no spec hardcodes it either, so following the instruction in
  # the mismatch message below (update the table) is genuinely all that
  # a deliberate move to a newer sirena takes.
  README_SHA = /^\|\s*sirena commit\s*\|\s*`([0-9a-f]{40})`\s*\|/

  module_function

  def expected_sha(readme_path)
    sha = File.read(readme_path)[README_SHA, 1]
    raise Mismatch, "no `sirena commit` row in #{readme_path}" if sha.nil?

    sha
  end

  # Raises unless the checkout is clean and sitting on `expected`.
  #
  # `status` is `git status --porcelain` output and `sha` is the checkout's
  # HEAD. Both are passed in so the decision is a pure function of them.
  def check!(sha:, status:, expected:)
    unless status.strip.empty?
      raise Mismatch,
            "sirena checkout is dirty, so its sha does not describe what " \
            "would be captured:\n#{status.strip}\n" \
            "Commit or stash there, then re-run."
    end

    return sha if sha == expected

    raise Mismatch,
          "sirena is at #{sha}, but the fixtures record #{expected}.\n" \
          "Capturing would replace them with a different consumer's " \
          "output. To move the fixtures to this commit deliberately, " \
          "re-run with SIRENA_SHA=#{sha} and update the provenance table."
  end

  # Gathers HEAD and the working-tree status from a checkout and applies
  # `check!`. `expected` overrides the README's sha, which is how a
  # deliberate move to a newer sirena is stated rather than assumed.
  #
  # The confirmation is printed HERE, beside the refusals, so it cannot
  # drift from what was actually checked -- it used to say "matches the
  # provenance table" even on a run where SIRENA_SHA had replaced it.
  def assert!(sirena_dir:, fixture_dir:, expected: nil, io: $stdout)
    readme = File.join(fixture_dir, "README.md")
    sha = check!(sha: git(sirena_dir, "rev-parse", "HEAD"),
                 status: git(sirena_dir, "status", "--porcelain"),
                 expected: expected || expected_sha(readme))
    io.puts "sirena is at #{sha}, clean, and matches " \
            "#{expected ? 'the SIRENA_SHA override' : 'the provenance table'}."
    sha
  end

  # stdout ONLY. Merging stderr in made a benign git warning part of the
  # value read back as the sha or the status -- measured, `GIT_TRACE=1`
  # on a clean checkout reported it as dirty, and git warns on its own
  # for plenty of reasons nobody chose.
  def git(dir, *args)
    out, err, status = Open3.capture3("git", "-C", dir, *args)
    unless status.success?
      raise Mismatch, "git #{args.join(' ')} failed in #{dir}:\n#{err}"
    end

    out.strip
  end
end
