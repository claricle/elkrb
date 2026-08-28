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

  desc "Run cross-validation tests"
  task :run do
    ruby "spec/cross_validation/validation_runner.rb"
  end

  desc "Import and run cross-validation (full pipeline)"
  task all: %i[import_all run]

  desc "Generate validation report (AsciiDoc)"
  task :report do
    ruby "spec/cross_validation/generate_validation_report.rb"
  end
end

namespace :golden do
  ELKJS_DIR = "spec/support/elkjs_golden"
  ELKJS_NODE_MODULES = "#{ELKJS_DIR}/node_modules/elkjs"
  GOLDEN_DIR = "spec/fixtures/golden"

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
    puts "Generating into #{dir}"
    abort "elkjs not installed — run: npm ci --prefix #{ELKJS_DIR}" unless Dir.exist?(ELKJS_NODE_MODULES)

    system("node", "#{ELKJS_DIR}/generate.js", dir, exception: true)
  rescue Errno::ENOENT
    abort "node not found on PATH (generated tree, if any, left at #{dir})"
  rescue RuntimeError => e
    # `exception: true` raises plain RuntimeError on a non-zero exit --
    # generate.js already printed its own specific reason to stderr above
    # this, so the abort just adds where to look, not a duplicate reason.
    abort "generate.js failed (#{e.message}); see its output above (generated tree, if any, left at #{dir})"
  end

  desc "Regenerate the committed elkjs golden expected files"
  task :generate do
    require "tmpdir"
    require "fileutils"

    # Non-block Dir.mktmpdir (not `do |tmp| ... end`): the block form
    # removes the directory on ANY exit, including a raised `abort`, which
    # would leave nothing to inspect after a failed generation. Removed
    # explicitly below, only once generation has actually succeeded.
    tmp = Dir.mktmpdir
    generate_into(tmp)

    FileUtils.rm_rf("#{GOLDEN_DIR}/expected")
    FileUtils.cp_r(tmp, "#{GOLDEN_DIR}/expected")
    FileUtils.mv("#{GOLDEN_DIR}/expected/MANIFEST.json",
                 "#{GOLDEN_DIR}/MANIFEST.json")
    FileUtils.remove_entry(tmp)
    puts "Golden expected files regenerated in #{GOLDEN_DIR}/expected"
  end

  desc "Diff freshly generated goldens against the committed ones (no writes)"
  task :check do
    require "tmpdir"
    require "json"

    tmp = Dir.mktmpdir
    generate_into(tmp)

    unless File.exist?("#{GOLDEN_DIR}/MANIFEST.json")
      abort "#{GOLDEN_DIR}/MANIFEST.json missing — run 'rake golden:generate' first (generated tree left at #{tmp})"
    end

    fresh_manifest = JSON.parse(File.read(File.join(tmp, "MANIFEST.json")))
    committed_manifest = JSON.parse(File.read("#{GOLDEN_DIR}/MANIFEST.json"))
    # "generated" is a timestamp and "node" is machine-specific — only the
    # pinned elkjs version and the case list are required to match.
    drifted_keys = %w[elkjs cases].select do |key|
      fresh_manifest[key] != committed_manifest[key]
    end
    abort "MANIFEST.json drift in #{drifted_keys.join(', ')} (generated tree left at #{tmp})" unless drifted_keys.empty?

    # spec/fixtures/golden/expected already holds only case files (no
    # MANIFEST — golden:generate moves it up to GOLDEN_DIR), so it
    # compares directly against `tmp` with no extra copy step. `-x` (not
    # deleting MANIFEST.json from `tmp` first) keeps `tmp` genuinely
    # intact for inspection on failure, matching what the abort message
    # below claims — a real BSD/GNU `diff` flag, confirmed working on
    # both during planning.
    ok = system("diff", "-r", "-x", "MANIFEST.json", "#{GOLDEN_DIR}/expected",
                tmp)
    if ok
      FileUtils.remove_entry(tmp)
    elsif ok.nil?
      abort "'diff' not found on PATH (generated tree left at #{tmp} for inspection)"
    else
      abort "golden drift detected (see diff above; generated tree left at #{tmp} for inspection)"
    end
  end
end
