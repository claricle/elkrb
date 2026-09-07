# frozen_string_literal: true

require "bundler/gem_tasks"
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

desc "Re-capture the sirena consumer fixtures " \
     "(SIRENA_DIR=<sirena checkout>, OUT_DIR=<where to write>)"
task "fixtures:sirena" do
  sirena_dir = ENV.fetch("SIRENA_DIR", nil).to_s
  abort "Set SIRENA_DIR to a sirena checkout, e.g. ~/claricle/sirena" if
    sirena_dir.empty?

  sirena_dir = File.expand_path(sirena_dir)
  abort "No such directory: #{sirena_dir}" unless Dir.exist?(sirena_dir)

  fixture_dir = File.expand_path("spec/fixtures/consumers/sirena", __dir__)
  out_dir = File.expand_path(ENV.fetch("OUT_DIR", fixture_dir))

  # The provenance check REFUSES. It used to print the sha and ask a
  # human to compare it, and a wrong sha on a dirty tree got all the way
  # to the capture command, which overwrites the fixtures in place.
  begin
    SirenaProvenance.assert!(sirena_dir: sirena_dir, fixture_dir: fixture_dir,
                             expected: ENV.fetch("SIRENA_SHA", nil))
  rescue SirenaProvenance::Mismatch => e
    abort e.message
  end

  # sirena is a separate gem, so the capture runs in sirena's own bundle.
  Bundler.with_unbundled_env do
    Dir.chdir(sirena_dir) do
      sh "bundle", "exec", "ruby",
         File.join(fixture_dir, "capture.rb"), fixture_dir, out_dir
    end
  end
end
