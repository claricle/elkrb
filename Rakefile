# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new do |task|
  # A worktree checked out under a parent directory that itself has a
  # .rubocop.yml (e.g. a git worktree nested under this repo's own clone)
  # would otherwise inherit that parent's AllCops:Exclude and its own
  # inherit_from chain. This flag keeps every checkout self-contained.
  task.options = ["--ignore-parent-exclusion"]
end

# DO NOT DELETE. This is the only thing that arms the SimpleCov floors in
# spec/spec_helper.rb. Remove it and coverage silently stops being enforced
# anywhere, with every run still green. CI runs `bundle exec rake`, so the
# default task is where the floor has to be armed.
#
# The value is load-bearing: spec_helper compares it to "1" exactly, so that
# COVERAGE_ENFORCE=0 disables the floor instead of enabling it the way a bare
# truthiness check would.
task :coverage_enforce do
  ENV["COVERAGE_ENFORCE"] = "1"
end

task default: %i[coverage_enforce spec rubocop]

# Not in `default`: CI runs `bundle exec rake` across a Ruby x OS matrix, and
# this task clones the ruby-advisory-db. A network dependency multiplied across
# every matrix cell turns CI red on code nobody touched.
desc "Check dependencies against the ruby-advisory-db"
task :audit do
  sh "bundle exec bundle-audit check --update"
end

# Not in `default`: the pre-existing smell count means this is only ever green
# behind .reek.yml, and behind that baseline it duplicates rubocop's role in
# the task CI runs on every matrix cell.
desc "Report code smells (baseline in .reek.yml)"
task :reek do
  sh "bundle exec reek lib"
end

# Flog and flay both exit 0 whatever they find, so on their own they are
# reporters, not gates. These tasks read the score off their Ruby APIs and add
# the comparison. Both scores move when the PARSER underneath moves, and for
# these two that is prism and sexp_processor -- not `parser`, which belongs to
# rubocop and reek. Gemfile.lock is gitignored, so all four gems are pinned or
# a fresh `bundle install` alone could move a baseline.
FLOG_MAX_METHOD = 107.0 # worst today is 106.5
FLAY_MAX_TOTAL = 4990

# exe/elkrb has no .rb extension, so expand_dirs_to_files skips it and lib is
# the whole of what either tool can see here.
QUALITY_PATHS = ["lib"].freeze

desc "Fail if any method's flog score exceeds the recorded ceiling"
task :flog do
  # Required inside the task: CI runs `rake`, and a load failure in a gem only
  # this opt-in task needs must not break the default build.
  require "flog_cli"
  require "sexp_processor"

  # methods: true drops the main#none pseudo-method, which otherwise tops the
  # table at 127.6 and is not a method at all.
  flog = FlogCLI.new(methods: true)
  flog.flog(*SexpProcessor.expand_dirs_to_files(*QUALITY_PATHS))

  # Read the score BEFORE reporting: FlogCLI#report ends in `ensure self.reset`,
  # which nils @totals, and max_method would then raise on nil.
  name, score = flog.max_method
  flog.report($stdout)

  if score > FLOG_MAX_METHOD
    abort "flog: #{name} scores #{score.round(1)}, " \
          "over the #{FLOG_MAX_METHOD} ceiling"
  end
end

desc "Fail if total flay duplication exceeds the recorded baseline"
task :flay do
  require "flay"
  require "sexp_processor"

  flay = Flay.new(Flay.default_options)
  flay.process(*SexpProcessor.expand_dirs_to_files(*QUALITY_PATHS))
  flay.analyze # #total stays 0 until this runs
  flay.report($stdout)

  if flay.total > FLAY_MAX_TOTAL
    abort "flay: duplication total #{flay.total}, " \
          "over the #{FLAY_MAX_TOTAL} baseline"
  end
end

# Not in `default`: mutant needs a git ref to scope against, and CI's checkout
# depth is not ours to assume. Diff-scoped it takes seconds; across all of lib/
# it is not something to run per matrix cell.
#
# This does NOT replace ~/.claude/bin/mutation-check.sh. That asks whether each
# NEW SPEC goes red when the code is reverted; this asks which parts of the
# CHANGED CODE no test protects. Different questions -- run both.
desc "Mutation-test subjects changed since BASE (default origin/v2)"
task :mutant do
  # The Gemfile only installs mutant on 3.3+, so say why rather than letting
  # bundler report a missing binary the Gemfile deliberately never asked for.
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3")
    abort "mutant needs Ruby >= 3.3; this is #{RUBY_VERSION}. " \
          "The gemspec floor is 3.2.0, so the Gemfile skips it here."
  end

  base = ENV.fetch("BASE", "origin/v2")
  sh "bundle exec mutant run --since #{base} -- 'Elkrb*'"
end

namespace :benchmark do
  desc "Generate test graphs for benchmarking"
  task :generate_graphs do
    ruby "benchmarks/generate_test_graphs.rb"
  end

  desc "Run ElkRb benchmarks"
  task elkrb: :generate_graphs do
    ruby "benchmarks/elkrb_benchmark.rb"
  end

  desc "Run elkjs benchmarks (requires Node.js and elkjs)"
  task elkjs: :generate_graphs do
    sh "node benchmarks/elkjs_benchmark.js"
  end

  desc "Generate performance report"
  task :report do
    ruby "benchmarks/generate_report.rb"
  end

  desc "Run all benchmarks and generate report"
  task all: %i[elkrb report] do
    puts "\nAll benchmarks completed!"
    puts "Note: Run 'rake benchmark:elkjs' separately if elkjs is installed"
  end
end

namespace :validate do
  desc "Import test cases from elkjs"
  task :import_elkjs do
    ruby "spec/cross_validation/elkjs_test_importer.rb"
  end

  desc "Import test cases from Java ELK"
  task :import_java_elk do
    ruby "spec/cross_validation/java_elk_test_importer.rb"
  end

  desc "Import all test cases from elkjs and Java ELK"
  task import_all: %i[import_elkjs import_java_elk]

  # There is no `validate:report` task any more. It printed a pass/fail
  # table from a stub comparison, which nothing in this repo read. The
  # dump this task writes is the real artifact: later slices diff two dump
  # directories against each other.
  desc "Dump canonical layout JSON for every corpus case to tmp/corpus"
  task :run do
    ruby "spec/cross_validation/corpus_runner.rb", "tmp/corpus"
  end

  desc "Import all test cases and dump the corpus (full pipeline)"
  task all: %i[import_all run]
end

namespace :corpus do
  desc "Dump canonical layout JSON for every corpus case to DIR"
  task :dump, [:dir] do |_t, args|
    dir = args[:dir]
    abort "usage: rake 'corpus:dump[dir]'" if dir.nil? || dir.empty?

    ruby "spec/cross_validation/corpus_runner.rb", dir
  end
end
