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

  # Every failure below RAISES this. These are public module methods, and
  # they used to `abort`: any Ruby process that loaded this Rakefile and
  # called `generate_into` was terminated with SystemExit 1 instead of
  # getting an exception it could handle. Only a rake task -- the CLI
  # entry point -- decides an exit status, which the tasks below do by
  # rescuing this and calling `abort` themselves.
  class GenerationFailed < StandardError; end

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
  # copies out of `dir` after `generate_into` returns successfully.
  def generate_into(dir)
    run_generator(dir)
  rescue Errno::ENOENT
    raise GenerationFailed, "node not found on PATH (#{left_at(dir)})"
  rescue RuntimeError => e
    # `exception: true` raises plain RuntimeError on a non-zero exit --
    # generate.js already printed its own specific reason to stderr above
    # this, so the message just adds where to look, not a duplicate reason.
    raise GenerationFailed,
          "generate.js failed (#{e.message}); see its output above " \
          "(#{left_at(dir)})"
  end

  def left_at(dir)
    "generated tree, if any, left at #{dir}"
  end

  def run_generator(dir)
    puts "Generating into #{dir}"
    unless Dir.exist?(ELKJS_NODE_MODULES)
      raise GenerationFailed,
            "elkjs not installed — run: npm ci --prefix #{ELKJS_DIR}"
    end

    system("node", "#{ELKJS_DIR}/generate.js", dir, exception: true)
  end
end

# rubocop:disable Metrics/BlockLength
namespace :golden do
  desc "Regenerate the committed elkjs golden expected files"
  task :generate do
    require "tmpdir"
    require "fileutils"

    golden_dir = GoldenFixtures::GOLDEN_DIR

    # Non-block Dir.mktmpdir (not `do |tmp| ... end`): the block form
    # removes the directory on ANY exit, including a raised `abort`, which
    # would leave nothing to inspect after a failed generation. Removed
    # explicitly below, only once generation has actually succeeded.
    tmp = Dir.mktmpdir
    # The task, not the module, turns a failure into an exit status.
    begin
      GoldenFixtures.generate_into(tmp)
    rescue GoldenFixtures::GenerationFailed => e
      abort e.message
    end

    FileUtils.rm_rf("#{golden_dir}/expected")
    FileUtils.cp_r(tmp, "#{golden_dir}/expected")
    FileUtils.mv("#{golden_dir}/expected/MANIFEST.json",
                 "#{golden_dir}/MANIFEST.json")
    FileUtils.remove_entry(tmp)
    puts "Golden expected files regenerated in #{golden_dir}/expected"
  end

  desc "Diff freshly generated goldens against the committed ones (no writes)"
  task :check do
    require "tmpdir"
    require "fileutils"
    require "json"

    golden_dir = GoldenFixtures::GOLDEN_DIR

    tmp = Dir.mktmpdir
    begin
      GoldenFixtures.generate_into(tmp)
    rescue GoldenFixtures::GenerationFailed => e
      abort e.message
    end

    unless File.exist?("#{golden_dir}/MANIFEST.json")
      abort "#{golden_dir}/MANIFEST.json missing — run " \
            "'rake golden:generate' first (generated tree left at #{tmp})"
    end

    fresh_manifest = JSON.parse(File.read(File.join(tmp, "MANIFEST.json")))
    committed_manifest = JSON.parse(File.read("#{golden_dir}/MANIFEST.json"))
    # "generated" is a timestamp and "node" is machine-specific — only the
    # pinned elkjs version and the case list are required to match.
    drifted_keys = %w[elkjs cases].reject do |key|
      fresh_manifest[key] == committed_manifest[key]
    end
    unless drifted_keys.empty?
      abort "MANIFEST.json drift in #{drifted_keys.join(', ')} " \
            "(generated tree left at #{tmp})"
    end

    # spec/fixtures/golden/expected already holds only case files (no
    # MANIFEST — golden:generate moves it up to GOLDEN_DIR), so it
    # compares directly against `tmp` with no extra copy step. `-x` (not
    # deleting MANIFEST.json from `tmp` first) keeps `tmp` genuinely
    # intact for inspection on failure, matching what the abort message
    # below claims — a real BSD/GNU `diff` flag, confirmed working on
    # both during planning.
    ok = system("diff", "-r", "-x", "MANIFEST.json", "#{golden_dir}/expected",
                tmp)
    if ok
      FileUtils.remove_entry(tmp)
    elsif ok.nil?
      abort "'diff' not found on PATH (generated tree left at #{tmp} " \
            "for inspection)"
    else
      abort "golden drift detected (see diff above; generated tree left " \
            "at #{tmp} for inspection)"
    end
  end
end
# rubocop:enable Metrics/BlockLength
