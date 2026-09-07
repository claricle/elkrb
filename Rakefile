# frozen_string_literal: true

require "bundler/gem_tasks"
require "fileutils"
require "json"
require "tmpdir"
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

task default: %i[spec rubocop]

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

  # The two renames, with an undo. One rename cannot half-happen; two of
  # them can, so the first is put back if the second fails and the
  # directory never holds a new tree beside an old manifest.
  def swap_into_place(golden_dir, staged, staged_manifest)
    live = [File.join(golden_dir, "expected"),
            File.join(golden_dir, "MANIFEST.json")]
    kept = live.map { |path| keep_aside(path) }
    rename_pair([staged, staged_manifest], live, kept)
    FileUtils.rm_rf(kept.compact)
  end

  def rename_pair(sources, live, kept)
    sources.zip(live).each { |from, to| File.rename(from, to) }
  rescue SystemCallError
    kept.zip(live).each { |aside, path| restore(aside, path) }
    raise
  end

  def keep_aside(path)
    return nil unless File.exist?(path)

    aside = "#{path}.#{Process.pid}.previous"
    File.rename(path, aside)
    aside
  end

  def restore(aside, path)
    return if aside.nil?

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
