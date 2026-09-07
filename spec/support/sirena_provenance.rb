# frozen_string_literal: true

require "English"

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
  # table. The README is the single place the expected commit is written
  # down, so the guard reads it rather than carrying a second copy.
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
  def assert!(sirena_dir:, fixture_dir:, expected: nil)
    readme = File.join(fixture_dir, "README.md")
    check!(sha: git(sirena_dir, "rev-parse", "HEAD"),
           status: git(sirena_dir, "status", "--porcelain"),
           expected: expected || expected_sha(readme))
  end

  def git(dir, *args)
    out = IO.popen(["git", "-C", dir, *args], err: %i[child out], &:read)
    unless $CHILD_STATUS.success?
      raise Mismatch, "git #{args.join(' ')} failed in #{dir}:\n#{out}"
    end

    out.strip
  end
end
