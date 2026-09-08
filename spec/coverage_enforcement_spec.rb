# frozen_string_literal: true

require "rbconfig"
require "fileutils"
require "tmpdir"

# The floors in spec/spec_helper.rb are armed from a before(:suite) hook, and
# rspec-core skips EVERY suite hook on a dry run -- configuration.rb's
# #with_suite_hooks opens `return yield if dry_run?`. So `SPEC_OPTS=--dry-run`
# used to turn the whole coverage gate off and still report success. The guard
# these examples pin is the at_exit backstop at the bottom of spec_helper.rb,
# which asserts the property directly: if this was a gate run, a floor is in
# force at exit, whatever mode RSpec was invoked in.
RSpec.describe "coverage floor arming" do
  # Out of process, because the property IS the process exit status, and
  # because a dry run inside this one would not have its own at_exit.
  #
  # The subprocess is deliberately given a single spec file. That makes it a
  # run the before(:suite) hook would REFUSE on its own, so a pass here cannot
  # come from the hook having quietly done the work -- only the at_exit guard
  # can produce this outcome under --dry-run.
  def dry_run(env)
    rspec = Gem.bin_path("rspec-core", "rspec")
    target = File.join(__dir__, "rakefile_spec.rb")
    out = IO.popen(
      env.merge("SPEC_OPTS" => "--dry-run --no-color"),
      [RbConfig.ruby, rspec, target],
      err: %i[child out],
      chdir: File.expand_path("..", __dir__),
      &:read
    )
    [$CHILD_STATUS.exitstatus, out]
  end

  it "refuses a gate run that armed no floor" do
    status, out = dry_run("COVERAGE_ENFORCE" => "1")

    expect(out).to include("no coverage floor was ever armed")
    expect(status).to eq(1)
  end

  # The other arm, and it is not decoration: without it the guard could be
  # refusing every dry run rather than every UNARMED gate run, and the example
  # above would look identical. A dry run outside a gate is a legitimate thing
  # to do and must stay silent.
  it "leaves a dry run that is not a gate run alone" do
    status, out = dry_run("COVERAGE_ENFORCE" => nil)

    expect(out).not_to include("no coverage floor was ever armed")
    expect(status).to eq(0)
  end

  # Everything above lives INSIDE spec_helper.rb, so all of it presupposes
  # spec_helper.rb was loaded. `.rspec` loads it with `--require spec_helper`,
  # which RSpec honours only on a run that gets that far: `rspec --help` and
  # `rspec --version` print and exit 0 first, so under `rake` the whole gate
  # was absent and the build was green. The Rakefile's :coverage_enforced task
  # is the half that sits outside, and these two examples are its matrix.
  # Everything else here checks that a floor was ARMED. This checks that an
  # armed floor is OBEYED, which SimpleCov skips for a process it believes is
  # one worker of a parallel run -- and it believes that whenever
  # TEST_ENV_NUMBER is in the environment. Nothing in this repository runs in
  # parallel, so `parallel_tests false` in the SimpleCov.start block turns the
  # autodetection off.
  describe "enforcement under a parallel-worker environment variable" do
    # The REAL spec/spec_helper.rb, so this is the shipped SimpleCov config.
    # COVERAGE_ENFORCE is cleared because `rake` sets it for the outer run and
    # the at_exit backstop would otherwise fire in the child for its own,
    # unrelated reason.
    def exit_status_with_floor(floor)
      script = <<~RUBY
        ENV.delete("COVERAGE_ENFORCE")
        # spec_helper.rb calls RSpec.configure, so rspec-core has to be loaded
        # first. Without it the child died with a NameError and the
        # below-the-floor example passed for entirely the wrong reason --
        # which is what the meets-the-floor example below exists to catch.
        require "rspec/core"
        load #{File.expand_path('spec_helper.rb', __dir__).inspect}
        SimpleCov.minimum_coverage(#{floor})
      RUBY
      IO.popen(
        { "TEST_ENV_NUMBER" => "2", "COVERAGE_ENFORCE" => nil },
        [RbConfig.ruby, "-Ilib", "-Ispec", "-e", script],
        err: %i[child out],
        chdir: File.expand_path("..", __dir__),
        &:read
      )
      $CHILD_STATUS.exitstatus
    end

    it "fails a run below the floor" do
      expect(exit_status_with_floor("line: 99, branch: 99")).not_to eq(0)
    end

    # The other arm. Without it the example above would pass just as well if
    # the child were failing for some reason of its own.
    it "passes a run that meets its floor" do
      expect(exit_status_with_floor("line: 0, branch: 0")).to eq(0)
    end
  end

  describe "the Rakefile's coverage receipt" do
    # The repository's OWN Rakefile, loaded in a child process rather than
    # copied, so this is the shipped file and not a paraphrase of it. Nothing
    # in the repository is touched: :coverage_enforce puts the receipt under a
    # fresh system temp directory, which is also what keeps this example from
    # deleting the receipt of the `rake` run that is executing it.
    #
    # bundler/gem_tasks is marked loaded rather than stubbed: it wants to build
    # a gem release task and has nothing to do with what is being tested.
    def run_default(spec_task)
      script = <<~RUBY
        $LOADED_FEATURES << "bundler/gem_tasks.rb"
        require "rake"
        require "fileutils"
        Rake.application = Rake::Application.new
        Rake.application.init("rake", [])
        load #{File.expand_path('../Rakefile', __dir__).inspect}
        Rake::Task[:rubocop].clear
        Rake::Task[:spec].clear
        #{spec_task}
        begin
          Rake::Task[:default].invoke
          puts "COMPLETED \#{ENV.fetch('COVERAGE_ENFORCE_RECEIPT', 'none')}"
        rescue RuntimeError => e
          puts "RAISED: \#{e.message}"
        end
      RUBY
      IO.popen([RbConfig.ruby, "-e", script], err: %i[child out], &:read)
    end

    # A `let`, not a constant: RuboCop's Lint/ConstantDefinitionInBlock would
    # fire on a constant here and its autocorrect rewrites one into a
    # block-local, which is a documented way to make a spec quietly assert
    # something else.
    let(:armed_spec_task) do
      <<~TASK
        task(:spec) do
          receipt = ENV.fetch("COVERAGE_ENFORCE_RECEIPT")
          FileUtils.mkdir_p(File.dirname(receipt))
          File.write(receipt, "1")
        end
      TASK
    end

    it "refuses a spec step that left no receipt" do
      out = run_default("task(:spec) { nil }")

      expect(out).to include("finished without arming the coverage floors")
      expect(out).not_to include("COMPLETED")
    end

    # The other arm. Without it the task could be raising unconditionally and
    # the example above would read exactly the same. The fake spec step writes
    # to the path the Rakefile EXPORTED, which is also what pins that the path
    # it exports and the path it later reads are one definition, not two.
    it "accepts a spec step that left one" do
      out = run_default(armed_spec_task)

      expect(out).to include("COMPLETED")
      expect(out).not_to include("RAISED")
    end

    # A receipt is proof only if it belongs to the run reading it. With one
    # fixed path, two overlapping runs shared a single receipt: both ran
    # :coverage_enforce, the ARMED one wrote the receipt, and the UNARMED one
    # then accepted it and deleted it -- passing on proof it had not produced
    # and failing the run that had. Disjoint paths make that impossible rather
    # than merely unlikely, which is why this asserts the paths and not the
    # interleaving.
    it "gives each invocation a receipt path of its own" do
      paths = Array.new(2) do
        # The whole rest of the LINE. `(\S+)` cut every path at its first
        # space, so under a TMPDIR containing one both paths read as the same
        # truncated string and this example passed while asserting nothing.
        run_default(armed_spec_task)[/^COMPLETED (.+)$/, 1]
      end

      expect(paths).to all(be_a(String))
      expect(paths.uniq.size).to eq(2)
    end
  end
end
