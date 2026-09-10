# frozen_string_literal: true

# English gives $ERROR_INFO its readable name; the at_exit guard at the bottom
# of this file reads it.
require "English"
require "fileutils"

# Must start before any application code loads, or Coverage observes nothing.
require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  # SimpleCov treats a process with TEST_ENV_NUMBER set as one worker of a
  # parallel run, and a non-first worker does NOT enforce the minimum -- it
  # leaves that to whoever merges the results. Nothing here runs in parallel,
  # so that autodetection can only ever be wrong, and it turned the gate off
  # from the environment. Measured against this very config, with a floor the
  # run cannot meet:
  #
  #   (nothing set)                          exit 2   floor enforced
  #   TEST_ENV_NUMBER=2                      exit 0   SILENTLY NOT ENFORCED
  #   TEST_ENV_NUMBER=2 + parallel_tests false  exit 2   enforced again
  #
  # DO NOT DELETE. Every other guard in this file checks that a floor was
  # ARMED; this is what keeps an armed floor from being ignored.
  parallel_tests false
  # And result MERGING, which `parallel_tests false` does NOT turn off. With
  # merging on, SimpleCov folds a cached result from an earlier process into
  # this run's report, so a run that covers almost nothing inherits a passing
  # number from one that covered everything. Measured on the tiny project
  # Codex's probe builds, with the floors this file arms:
  #
  #   fresh low-coverage run                  8% line, exit 2   correct
  #   seed a covered run under TEST_ENV_NUMBER   100%, exit 0
  #   the SAME low-coverage run again          100%, exit 0   MERGED, WRONG
  #   the same again with `merging false`       8%, exit 2   correct
  #
  # Nothing here runs across processes, so a merged result can only ever be a
  # stale one. DO NOT DELETE: without this the floor is armed, obeyed, and
  # measuring a number this run did not earn.
  merging false
  # Without this, a file no spec ever loads is ABSENT from the report rather
  # than reported at 0% -- which is the case most worth surfacing.
  track_files "lib/**/*.rb"
  # Anchored with no leading slash on purpose. SimpleCov matches a Regexp filter
  # against SourceFile#project_filename, which is root-relative with its leading
  # separator already stripped -- it reads "spec/foo.rb" -- so the older
  # `%r{^/spec/}` idiom matches nothing at all and silently guards nothing.
  add_filter %r{\Aspec/}
  add_filter %r{\Abenchmarks/}
  # A String filter rather than a Regexp one, so this is a path-segment match
  # rather than an anchored pattern. The gemspec requires this file, and bundler
  # runs the gemspec before Coverage starts, so it can never be observed and
  # would otherwise sit at 0% forever.
  add_filter "lib/elkrb/version.rb"
  # The floor is NOT armed here. SimpleCov.start runs before RSpec has decided
  # which files it will load, so at this point nothing can tell a full run from
  # a narrowed one -- see the before(:suite) hook below, which arms it once that
  # is knowable. SimpleCov reads the minimum at process exit, so setting it
  # later still takes effect.
end

require "elkrb"

# Not redundant, despite the cop: measured on ruby 3.4.8, `Dir[]` walks a
# directory's contents before a sibling file of the same name, so the raw
# order here puts every `support/invariants/*.rb` ahead of
# `support/invariants.rb`. Sorting makes the require order deterministic
# and identical on every machine rather than filesystem-dependent.
# rubocop:disable Lint/RedundantDirGlobSort
Dir[File.join(__dir__, "support/**/*.rb")].sort.reject do |f|
  f.end_with?("_spec.rb")
end.each { |f| require f }
# rubocop:enable Lint/RedundantDirGlobSort

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.profile_examples = 10

  config.order = :random
  Kernel.srand config.seed

  # Only the full-suite run can meet a floor, so only the full-suite run
  # enforces one. COVERAGE_ENFORCE says "this is a gate run"; the file list says
  # whether the run is actually the whole suite. Both are needed: `rake` sets
  # the variable unconditionally, and RSpec's rake task honours ENV["SPEC"],
  # so `SPEC=one_spec.rb rake` used to arm the full-suite floor over a single
  # file and fail on coverage.
  #
  # DO NOT DELETE THE VARIABLE OR THIS HOOK. If COVERAGE_ENFORCE stops being
  # set, this floor silently never fires again and nothing goes red. The
  # Rakefile's `default` task is the only thing that sets it.
  #
  # Compared exactly, not for truthiness: every string is truthy in Ruby, so a
  # bare `if ENV[...]` would still enforce the floor for someone who set
  # COVERAGE_ENFORCE=0 to turn it off.
  config.before(:suite) do
    next unless ENV["COVERAGE_ENFORCE"] == "1"

    # Dir.glob returns sorted results on Ruby 3.0+, which is below the gemspec
    # floor, so only files_to_run needs sorting.
    all = Dir.glob(File.expand_path("**/*_spec.rb", __dir__))
    ran = config.files_to_run.map { |file| File.expand_path(file) }.sort

    # BOTH sides of the filter manager. RSpec keeps them in separate rule sets,
    # so counting only inclusions accepts `--tag ~slow`, which drops examples
    # while inclusions stays at 0. Measured on rspec-core 3.13.6: with no
    # filters both read []; `--tag bar` gives inclusions [:bar]; `--tag ~foo`
    # gives exclusions [:foo].
    manager = config.filter_manager
    filters = manager.inclusions.rules.size + manager.exclusions.rules.size

    # RAISE rather than quietly skip the floor. A narrowed `rake` that reported
    # green would be a gate CI could opt out of, which is the one thing the
    # arming exists to prevent.
    unless ran == all && filters.zero?
      raise "COVERAGE_ENFORCE=1 but this is not a full-suite run " \
            "(#{ran.size} of #{all.size} spec files, #{filters} filters). " \
            "Run `rake` with no SPEC, tag or example filter."
    end

    SimpleCov.minimum_coverage(line: 85, branch: 68)

    # The receipt the Rakefile's :coverage_enforced task reads after `spec`.
    # Written HERE because this is the only line in the process that proves
    # the floors are armed, and read from a task OUTSIDE this file because
    # every check inside it presupposes the file was loaded -- which
    # `rspec --help` and `rspec --version` skip entirely. The Rakefile owns
    # the path; nothing here decides it.
    receipt = ENV.fetch("COVERAGE_ENFORCE_RECEIPT", nil)
    next unless receipt

    FileUtils.mkdir_p(File.dirname(receipt))
    File.write(receipt, Process.pid.to_s)
  end
end

# The SECOND layer, and the one that cannot be skipped. The hook above is a
# before(:suite) hook, and rspec-core skips EVERY suite hook on a dry run --
# configuration.rb#with_suite_hooks opens `return yield if dry_run?` (measured
# on rspec-core 3.13.6). So before this existed, with the SAME single spec file:
#
#   COVERAGE_ENFORCE=1 rspec spec/rakefile_spec.rb
#     -> exit 1, refused
#   COVERAGE_ENFORCE=1 SPEC_OPTS=--dry-run rspec spec/rakefile_spec.rb
#     -> exit 0, GREEN
#
# One environment variable turned the gate off and reported success, which is
# the exact opt-out the arming exists to prevent.
#
# This is deliberately NOT another list of invocation modes to reject. It
# asserts the property itself: if this was a gate run, a floor is in force at
# exit. Any route that skips the hook -- --dry-run today, anything else later
# -- fails here, because the check does not depend on how RSpec was invoked.
#
# It must be registered AFTER SimpleCov.start. at_exit handlers run LIFO, so
# this runs BEFORE SimpleCov's own handler reads the minimum and reports.
#
# It RAISES rather than calling exit. Ruby turns an exception raised in an
# at_exit handler into exit status 1 and still runs the remaining handlers, so
# SimpleCov's report is not suppressed. Measured, both facts.
#
# DO NOT DELETE. Deleting this restores the bypass above, with every run green.
# spec/coverage_enforcement_spec.rb pins both arms of it.
at_exit do
  # Only judge a run that is otherwise on course to succeed. A run already
  # failing -- including one the hook above refused -- has its own message, and
  # a second error stacked on top would obscure it.
  error = $ERROR_INFO
  next unless error.nil? || (error.is_a?(SystemExit) && error.success?)
  next unless ENV["COVERAGE_ENFORCE"] == "1"

  # The floors themselves, not a flag recording that the hook ran.
  # SimpleCov.minimum_coverage reads {} until something sets it, and it is what
  # SimpleCov actually enforces at exit.
  next unless SimpleCov.minimum_coverage.empty?

  raise "COVERAGE_ENFORCE=1 but no coverage floor was ever armed, so this " \
        "run enforced nothing. before(:suite) hooks do not run under " \
        "--dry-run. Re-run `rake` without --dry-run."
end
