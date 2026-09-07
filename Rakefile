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

desc "Re-capture the sirena consumer fixtures " \
     "(SIRENA_DIR=<sirena checkout>, OUT_DIR=<where to write>)"
task "fixtures:sirena" do
  sirena_dir = ENV.fetch("SIRENA_DIR", nil).to_s
  if sirena_dir.empty?
    abort "Set SIRENA_DIR to a sirena checkout, for example: " \
          "rake fixtures:sirena SIRENA_DIR=~/claricle/sirena"
  end

  sirena_dir = File.expand_path(sirena_dir)
  abort "No such directory: #{sirena_dir}" unless Dir.exist?(sirena_dir)

  fixture_dir = File.expand_path("spec/fixtures/consumers/sirena", __dir__)
  out_dir = File.expand_path(ENV.fetch("OUT_DIR", fixture_dir))

  sh "git", "-C", sirena_dir, "log", "-1", "--format=sirena is at %H"
  sh "git", "-C", sirena_dir, "status", "--porcelain"
  puts "Check that sha, and an empty status above, against the " \
       "provenance table in spec/fixtures/consumers/sirena/README.md."

  # sirena is a separate gem, so the capture runs in sirena's own bundle.
  Bundler.with_unbundled_env do
    Dir.chdir(sirena_dir) do
      sh "bundle", "exec", "ruby",
         File.join(fixture_dir, "capture.rb"), fixture_dir, out_dir
    end
  end
end
