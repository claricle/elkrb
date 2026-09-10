# frozen_string_literal: true

require "bundler/gem_tasks"
require "fileutils"
require "json"
require "tmpdir"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require_relative "spec/support/sirena_provenance"

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
# The value is load-bearing, but note what it does and does not buy. Under
# `rake` the floor is ALWAYS armed -- this line overwrites whatever the caller
# set, deliberately, because CI must not be able to opt out. The exact `== "1"`
# in spec_helper is for the OTHER path: someone with COVERAGE_ENFORCE=0 in their
# shell running `rspec` directly gets no floor, where a bare truthiness check
# would have fired one, since every string is truthy in Ruby.
#
# No `desc`, deliberately: it is a prerequisite of `default`, not a task anyone
# should invoke, so it stays out of `rake -T`.
# Set by :coverage_enforce and read by :coverage_enforced -- a local both task
# blocks close over, deliberately NOT read back out of the environment. This
# value decides what gets DELETED, and an environment variable is whatever the
# caller says it is. Measured before this was a local: with
# COVERAGE_ENFORCE_RECEIPT pointed at a directory holding an unrelated
# keep.txt, invoking :coverage_enforced on its own removed the receipt, the
# keep.txt and the directory. nil here means this invocation created nothing,
# so there is nothing of ours to remove.
receipt_path = nil

task :coverage_enforce do
  ENV["COVERAGE_ENFORCE"] = "1"
  # A FRESH directory per invocation, and the receipt path handed to the spec
  # subprocess through the environment. Not one fixed path: two `rake` runs
  # overlapping in the same checkout then shared a single receipt, and the
  # unarmed one accepted -- and deleted -- the armed one's proof. Measured, an
  # unarmed `SPEC_OPTS=--help` run passed on a receipt it had not produced.
  #
  # A fresh directory also means a receipt left behind by an EARLIER run is
  # structurally unable to satisfy this one, rather than merely being deleted
  # first, and it keeps the file out of the repository altogether.
  #
  # Nothing can pre-seed the path: this assignment overwrites whatever the
  # caller set.
  receipt_path = File.join(Dir.mktmpdir("elkrb-coverage"), "receipt")
  # The environment is how the path reaches the spec SUBPROCESS, and that is
  # all it is for. Nothing on this side reads it back.
  ENV["COVERAGE_ENFORCE_RECEIPT"] = receipt_path
end

# The half of the gate that lives OUTSIDE the thing being gated, and it is the
# only half that can be trusted on its own. Every guard inside spec_helper.rb
# assumes spec_helper.rb was loaded, and `.rspec` loads it with
# `--require spec_helper`, which RSpec honours only on a run that gets that
# far. Measured on rspec-core 3.13.6, through this very task:
#
#   SPEC_OPTS=--help    rspec prints help and exits 0
#   SPEC_OPTS=--version rspec prints versions and exits 0
#
# Neither loads spec_helper at all, so before(:suite) never runs, the at_exit
# backstop is never registered, and `rake` reported success having enforced
# nothing. That is a family of routes, not two of them, so this does not list
# them: it asserts the property. The spec step has to come back with proof it
# armed the floors, and no proof is a failure whatever the reason.
#
# No `desc` for the same reason as :coverage_enforce.
task :coverage_enforced do
  unless receipt_path && File.exist?(receipt_path)
    raise "the spec step finished without arming the coverage floors, so " \
          "this run enforced nothing. RSpec exits early for --help and " \
          "--version without loading spec/spec_helper.rb. Re-run `rake` " \
          "with no SPEC_OPTS."
  end

  # The whole directory, so a run that gets this far leaves nothing behind --
  # and only ever a directory THIS invocation made, above. A run whose spec
  # step FAILS never reaches here and leaves one empty directory under the
  # system temp root, which the OS reclaims.
  FileUtils.remove_entry(File.dirname(receipt_path))
end

task default: %i[coverage_enforce spec coverage_enforced rubocop]

# Not in `default`: CI runs `bundle exec rake` across a Ruby x OS matrix, and
# this task clones the ruby-advisory-db. A network dependency multiplied across
# every matrix cell turns CI red on code nobody touched.
desc "Check dependencies against the ruby-advisory-db"
task :audit do
  sh "bundle exec bundle-audit check --update"
end

# exe/elkrb is named EXPLICITLY, not reached through "exe". expand_dirs_to_files
# only globs *.rb when it expands a DIRECTORY, so `expand_dirs_to_files("exe")`
# returns [] while `expand_dirs_to_files("exe/elkrb")` returns ["exe/elkrb"] --
# leaving the production entry point out of all three tools if it is not listed.
# Measured 2026-09-07: adding it moves nothing (reek 0 warnings, flog max still
# 106.52, flay total still 5006), so it costs no baseline headroom.
QUALITY_PATHS = ["lib", "exe/elkrb"].freeze

# Flog and flay both exit 0 whatever they find, so on their own they are
# reporters, not gates. These tasks read the score off their Ruby APIs and add
# the comparison.
#
# Every failure below RAISES rather than calling `abort`. This file is loadable
# by any Ruby process -- `load "Rakefile"`, or Rake::Application#load_rakefile
# from an embedding tool -- so `abort` here raises SystemExit in the CALLER and
# terminates it. Only a script entry point may decide a process exit status; the
# rake CLI turns a raised error into exit 1 by itself. spec/rakefile_spec.rb
# pins this for the whole file, not just the tasks that have a failure path
# today. Both scores move when the parser underneath them moves, and
# for these two that is prism and sexp_processor -- not the `parser` gem, which
# is rubocop's and reek's. Gemfile.lock is gitignored, so all four are pinned or
# a fresh `bundle install` alone could move a baseline.
#
# TO RE-BASELINE, whenever anything in QUALITY_PATHS changes under this branch
# -- that is lib/ OR exe/elkrb, not lib/ alone. Both numbers come from the
# tasks' own APIs, so measure them the way the tasks do rather than by reading
# a failure message, and pass the SAME paths the tasks pass or the reading is
# of a different corpus than the gate. Take each reading TWICE -- a number that
# moves between two runs is not a baseline:
#
#   bundle exec ruby -e 'require "flog_cli"; require "sexp_processor"
#     f = FlogCLI.new(methods: true)
#     f.flog(*SexpProcessor.expand_dirs_to_files("lib", "exe/elkrb"))
#     n, s = f.max_method; puts "#{n} #{s}"'
#
#   bundle exec ruby -e 'require "flay"; require "sexp_processor"
#     f = Flay.new(Flay.default_options)
#     f.process(*SexpProcessor.expand_dirs_to_files("lib", "exe/elkrb"))
#     f.report(File.open(File::NULL, "w")); puts f.total'
#
# Note the report call in the flay one: Flay#total reads 0 until #report has
# run, for the reason the :flay task explains below. Then seed a violation --
# a duplicated file for flay, a deliberately tangled method for flog -- and
# watch the task go red before trusting the new number. A ceiling that cannot
# fail is not a gate.
FLOG_MAX_METHOD = 107.0 # worst method today is 106.52
# Re-baselined 2026-09-07 from 4990 when origin/v2 1b305c4 was merged in: PR #10
# deleted graph/layout_options.rb and added graph/normalize_option_keys.rb, and
# PR #17 replaced parsers/elkt_parser.rb with parsers/elkt/. Measured twice.
# This has no headroom by design, which is why any lib/ arriving from v2 reddens
# it on day one -- that is the ratchet working, not a bug, but it does mean a
# refresh onto a moved v2 always owes this measurement.
FLAY_MAX_TOTAL = 5006

# Not in `default`: the pre-existing smell count means this is only ever green
# behind .reek.yml, and behind that baseline it duplicates rubocop's role in
# the task CI runs on every matrix cell.
desc "Report code smells (baseline in .reek.yml)"
task :reek do
  sh "bundle", "exec", "reek", *QUALITY_PATHS
end

desc "Fail if any method's flog score exceeds the recorded ceiling"
task :flog do
  # Required inside the task: CI runs `rake`, and a load failure in a gem only
  # this opt-in task needs must not break the default build.
  require "flog_cli"
  require "sexp_processor"

  # methods: true drops the main#none pseudo-method, which otherwise tops the
  # table and is not a method at all. No score quoted on purpose: it is the sum
  # of everything outside a method body, so it moves with any lib/ change and a
  # number here rots on the next merge. Re-check with
  #   FlogCLI.new.flog(*SexpProcessor.expand_dirs_to_files("lib")).max_method
  flog = FlogCLI.new(methods: true)
  flog.flog(*SexpProcessor.expand_dirs_to_files(*QUALITY_PATHS))

  # Read the score BEFORE reporting: FlogCLI#report ends in `ensure self.reset`,
  # which nils @totals, and max_method would then raise on nil.
  name, score = flog.max_method
  flog.report($stdout)

  # Two decimals, not one: the comparison is exact, so a score of 107.04 would
  # round to "107.0, over the 107.0 ceiling" and read like a bug in the task.
  if score > FLOG_MAX_METHOD
    raise "flog: #{name} scores #{format('%.2f', score)}, " \
          "over the #{FLOG_MAX_METHOD} ceiling"
  end
end

desc "Fail if total flay duplication exceeds the recorded baseline"
task :flay do
  require "flay"
  require "sexp_processor"

  flay = Flay.new(Flay.default_options)
  flay.process(*SexpProcessor.expand_dirs_to_files(*QUALITY_PATHS))

  # Read the total AFTER reporting -- the exact opposite of flog above, so do
  # not "fix" one to match the other. Flay#report runs the analysis itself
  # (flay.rb `data = analyze only`), and the analysis starts by resetting the
  # total to 0, so #total reads 0 until report has run.
  flay.report($stdout)

  if flay.total > FLAY_MAX_TOTAL
    raise "flay: duplication total #{flay.total}, " \
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
    raise "mutant needs Ruby >= 3.3; this is #{RUBY_VERSION}. The gemspec " \
          "floor is 3.2.0, so the Gemfile skips it here. Re-run on 3.3+."
  end

  # Array form, so `sh` runs the command directly instead of through a shell.
  # BASE is caller-supplied and the single-string form hands it to sh -c
  # verbatim, so BASE='v2; some-other-command' would run that command. The array
  # form also means `Elkrb*` needs no quoting, because nothing can glob it.
  base = ENV.fetch("BASE", "origin/v2")
  sh "bundle", "exec", "mutant", "run", "--since", base, "--", "Elkrb*"
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
    raise "usage: rake 'corpus:dump[dir]'" if dir.nil? || dir.empty?

    ruby "spec/cross_validation/corpus_runner.rb", dir
  end
end

desc "Re-capture the sirena consumer fixtures " \
     "(SIRENA_DIR=<sirena checkout>, OUT_DIR=<where to write>)"
# `raise`, not `abort`. A rake task is a method any Ruby caller can
# invoke, and `abort` raises SystemExit: `Rake::Task["fixtures:sirena"]
# .invoke` with no SIRENA_DIR took the CALLING process down past every
# ordinary `rescue StandardError` -- measured. Only the `rake` command
# itself may decide an exit status, and it still does: an exception out
# of a task is what makes rake exit 1.
# The sirena checkout SIRENA_DIR names, as an absolute path.
def sirena_checkout
  requested = ENV.fetch("SIRENA_DIR", nil).to_s
  raise "Set SIRENA_DIR to a sirena checkout, e.g. ~/claricle/sirena" if
    requested.empty?

  File.expand_path(requested).tap do |dir|
    raise "No such directory: #{dir}" unless Dir.exist?(dir)
  end
end

task "fixtures:sirena" do
  sirena_dir = sirena_checkout
  fixture_dir = File.expand_path("spec/fixtures/consumers/sirena", __dir__)
  # Blank is "not given", not "here" -- see SirenaProvenance.out_dir.
  out_dir = SirenaProvenance.out_dir(ENV.fetch("OUT_DIR", nil),
                                     default: fixture_dir)

  # The provenance check REFUSES. It used to print the sha and ask a
  # human to compare it, and a wrong sha on a dirty tree got all the way
  # to the capture command, which overwrites the fixtures in place.
  #
  # `Mismatch` propagates UNCAUGHT. There is nothing to add to it here, and
  # both shapes this line has worn already lost something: `abort e.message`
  # raised SystemExit and took the calling process down, and `raise
  # e.message` -- which replaced it -- reduced a dedicated `Mismatch` to a
  # RuntimeError and reset its backtrace, so a caller could no longer tell a
  # provenance refusal from any other failure. `Mismatch` is a StandardError
  # and rake turns it into exit status 1 on its own.
  SirenaProvenance.assert!(sirena_dir: sirena_dir, fixture_dir: fixture_dir,
                           expected: ENV.fetch("SIRENA_SHA", nil))

  # sirena is a separate gem, so the capture runs in sirena's own bundle.
  Bundler.with_unbundled_env do
    Dir.chdir(sirena_dir) do
      sh "bundle", "exec", "ruby",
         File.join(fixture_dir, "capture.rb"), fixture_dir, out_dir
    end
  end
end

module GoldenFixtures
  ELKJS_DIR = "spec/support/elkjs_golden"
  ELKJS_NODE_MODULES = "#{ELKJS_DIR}/node_modules/elkjs".freeze
  GOLDEN_DIR = "spec/fixtures/golden"

  # Every failure in this module and in the golden tasks RAISES this.
  # Nothing on this path calls `abort`. These are public module methods,
  # and the tasks themselves are reachable as
  # `Rake::Task["golden:generate"].invoke`, so an `abort` anywhere in the
  # path took the CALLING process down with SystemExit 1 -- measured, a
  # probe's own "CALLER SURVIVED" line was never reached. Rake turns this
  # exception into exit status 1 on its own, which is the CLI's job and
  # nobody else's.
  class Failed < StandardError; end

  module_function

  # Runs generate.js into `dir` (all case files + MANIFEST.json, flat).
  # generate.js verifies the pinned elkjs version up front and validates
  # each case as it goes (only the allow-listed hyperedge case may
  # reject), exiting non-zero the moment a case fails its check — `dir`
  # itself CAN end up holding a partial set of case files at that point
  # (every case before the failing one already got written), which is
  # exactly the point: `dir`'s path is printed below so a failure's
  # partial tree is there to inspect. What never happens is GOLDEN_DIR
  # (the real committed destination) being touched — the caller only
  # publishes out of `dir` after `generate_into` returns successfully.
  def generate_into(dir)
    run_generator(dir)
  rescue Errno::ENOENT
    raise Failed, "node not found on PATH (#{left_at(dir)})"
  rescue RuntimeError => e
    # `exception: true` raises plain RuntimeError on a non-zero exit --
    # generate.js already printed its own specific reason to stderr above
    # this, so the message just adds where to look, not a duplicate reason.
    raise Failed, "generate.js failed (#{e.message}); see its output " \
                  "above (#{left_at(dir)})"
  end

  def left_at(dir)
    "generated tree, if any, left at #{dir}"
  end

  def run_generator(dir)
    puts "Generating into #{dir}"
    unless Dir.exist?(ELKJS_NODE_MODULES)
      raise Failed, "elkjs not installed — run: npm ci --prefix #{ELKJS_DIR}"
    end

    system("node", "#{ELKJS_DIR}/generate.js", dir, exception: true)
  end

  # Replaces the committed expected tree and MANIFEST with freshly
  # generated ones. The whole replacement is copied into a staging
  # directory beside the destination FIRST, and the live paths are
  # swapped only once that copy is complete.
  #
  # `rm_rf` then `cp_r` deleted the committed tree before it had a
  # replacement: a `cp_r` forced to raise ENOSPC left `expected/` gone
  # and the previous MANIFEST.json sitting beside nothing -- measured.
  # Uncommitted fixtures were destroyed by a full disk.
  def publish_into(source, golden_dir)
    staged = File.join(golden_dir, ".expected.#{Process.pid}.staged")
    staged_manifest = File.join(golden_dir, ".MANIFEST.#{Process.pid}.staged")
    FileUtils.cp_r(source, staged)
    FileUtils.mv(File.join(staged, "MANIFEST.json"), staged_manifest)
    swap_into_place(golden_dir, staged, staged_manifest)
  ensure
    FileUtils.rm_rf([staged, staged_manifest].compact)
  end

  # FOUR renames, all under one undo. Two move the live tree aside and two
  # move the new one in, and any of the four can fail on its own.
  #
  # The undo used to cover only the last two: forcing ENOSPC on the SECOND
  # keep-aside left `expected/` already moved to `.previous` beside the old
  # MANIFEST.json, with nothing to put it back -- measured. And `ensure`,
  # not `rescue SystemCallError`, because Ctrl-C raises Interrupt, which
  # that rescue never caught.
  def swap_into_place(golden_dir, staged, staged_manifest)
    live = [File.join(golden_dir, "expected"),
            File.join(golden_dir, "MANIFEST.json")]
    kept = []
    swapped = false
    live.each_with_index { |path, index| keep_aside(path, kept, index) }
    [staged, staged_manifest].zip(live)
      .each { |from, to| File.rename(from, to) }
    swapped = true
  ensure
    finish_swap(kept, live, swapped)
  end

  def finish_swap(kept, live, swapped)
    return FileUtils.rm_rf(kept.compact) if swapped

    kept.zip(live).each { |aside, path| restore(aside, path) }
  end

  # Records the aside path BEFORE the rename, and at a FIXED index, so an
  # interruption between the two still leaves an entry naming where the
  # original went and `kept` still lines up with `live`. Appending after
  # the rename left a moved tree with no entry pointing at it.
  def keep_aside(path, kept, index)
    kept[index] = File.exist?(path) ? "#{path}.#{Process.pid}.previous" : nil
    File.rename(path, kept[index]) if kept[index]
  end

  # Asks the filesystem which side of the rename this entry stopped on
  # rather than assuming it ran. An aside that is NOT there means the
  # original never moved and is still at `path`, so removing `path` would
  # destroy the very tree this exists to restore.
  def restore(aside, path)
    return if aside.nil?
    return unless File.exist?(aside)

    FileUtils.rm_rf(path)
    File.rename(aside, path)
  end

  # Compares a freshly generated tree against the committed one and
  # raises on any drift. `source` is deliberately left where it is so a
  # failure can be inspected, which is what every message promises.
  def check_against(source, golden_dir)
    manifest = File.join(golden_dir, "MANIFEST.json")
    unless File.exist?(manifest)
      raise Failed, "#{manifest} missing — run 'rake golden:generate' " \
                    "first (generated tree left at #{source})"
    end

    check_manifest_drift(source, manifest)
    check_tree_drift(source, File.join(golden_dir, "expected"))
  end

  def check_manifest_drift(source, committed_path)
    fresh = JSON.parse(File.read(File.join(source, "MANIFEST.json")))
    committed = JSON.parse(File.read(committed_path))
    # "generated" is a timestamp and "node" is machine-specific — only the
    # pinned elkjs version and the case list are required to match.
    drifted = %w[elkjs cases].reject { |key| fresh[key] == committed[key] }
    return if drifted.empty?

    raise Failed, "MANIFEST.json drift in #{drifted.join(', ')} " \
                  "(generated tree left at #{source})"
  end

  # spec/fixtures/golden/expected holds only case files (no MANIFEST --
  # `publish_into` moves it up to GOLDEN_DIR), so it compares directly
  # against `source` with no extra copy step. `-x` (rather than deleting
  # MANIFEST.json from `source` first) keeps `source` genuinely intact
  # for inspection, matching what the messages below claim — a real
  # BSD/GNU `diff` flag, confirmed working on both during planning.
  def check_tree_drift(source, expected)
    ok = system("diff", "-r", "-x", "MANIFEST.json", expected, source)
    return if ok

    if ok.nil?
      raise Failed, "'diff' not found on PATH (generated tree left at " \
                    "#{source} for inspection)"
    end

    raise Failed, "golden drift detected (see diff above; generated tree " \
                  "left at #{source} for inspection)"
  end
end

namespace :golden do
  desc "Regenerate the committed elkjs golden expected files"
  task :generate do
    golden_dir = GoldenFixtures::GOLDEN_DIR
    # Non-block Dir.mktmpdir (not `do |tmp| ... end`): the block form
    # removes the directory on ANY exit, including a raised failure,
    # which would leave nothing to inspect. Removed explicitly below,
    # only once the whole regeneration has actually succeeded.
    tmp = Dir.mktmpdir
    GoldenFixtures.generate_into(tmp)
    GoldenFixtures.publish_into(tmp, golden_dir)
    FileUtils.remove_entry(tmp)
    puts "Golden expected files regenerated in #{golden_dir}/expected"
  end

  desc "Diff freshly generated goldens against the committed ones (no writes)"
  task :check do
    tmp = Dir.mktmpdir
    GoldenFixtures.generate_into(tmp)
    GoldenFixtures.check_against(tmp, GoldenFixtures::GOLDEN_DIR)
    FileUtils.remove_entry(tmp)
  end
end
