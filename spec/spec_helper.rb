# frozen_string_literal: true

# Must start before any application code loads, or Coverage observes nothing.
require "simplecov"
SimpleCov.start do
  enable_coverage :branch
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
  end
end
