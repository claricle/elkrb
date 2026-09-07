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
  # Only the full-suite run can meet a floor, so only the full-suite run
  # enforces one: `rake` sets COVERAGE_ENFORCE, and a partial run (one spec
  # file, or the subset mutant and mutation-check.sh execute) does not.
  #
  # DO NOT DELETE THE CONDITION OR THE VARIABLE. If COVERAGE_ENFORCE stops
  # being set, this floor silently never fires again and nothing goes red.
  # The Rakefile's `default` task is the only thing that sets it.
  #
  # Compared exactly, not for truthiness: every string is truthy in Ruby, so a
  # bare `if ENV[...]` would still enforce the floor for someone who set
  # COVERAGE_ENFORCE=0 to turn it off.
  minimum_coverage(line: 85, branch: 68) if ENV["COVERAGE_ENFORCE"] == "1"
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
end
