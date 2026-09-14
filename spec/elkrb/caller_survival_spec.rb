# frozen_string_literal: true

require "spec_helper"
require "support/cli_runner"
require "support/fake_dot"
require "json"
require "tmpdir"
require "fileutils"

# Every entry point a Ruby caller can reach must raise rather than exit.
#
# No child rescues SystemExit. SystemExit is not a StandardError, so a child
# that reaches `exit` or `abort` dies before it can print -- the sentinel
# cannot be produced by a process that was killed, which is what makes its
# presence a proof rather than an absence check. Most children rescue
# StandardError; two deliberately rescue the narrower Elkrb::Error and
# Elkrb::CommandFailed to pin the idiom this repo documents, and each says so
# where it sits.
RSpec.describe "library callers keep control of their own process" do
  include CliRunner
  include FakeDot

  def survives(source)
    stdout, stderr, status = run_ruby(source)
    expect(stdout).to include(CliRunner::SENTINEL), "died: #{stderr}"
    # A SEPARATE property, not a restatement of the sentinel. Printing and
    # exiting cleanly are independent: `puts SENTINEL; at_exit { exit 7 }`
    # prints the sentinel and still exits 7 (measured). So this catches a
    # child that survived the call and then died on the way out, which the
    # sentinel alone cannot see. Keep both.
    expect(status.exitstatus).to eq(0)
    stdout
  end

  describe "Elkrb::Cli" do
    # One argv per rescue site in cli.rb. All six are reachable with the same
    # input -- a path that does not exist -- and all six killed the caller
    # before this change.
    {
      "layout" => %w[layout MISSING],
      "diagram" => %w[diagram MISSING -o OUT.svg],
      "convert" => %w[convert MISSING -o OUT.yaml],
      "render" => %w[render MISSING -o OUT.png],
      "validate" => %w[validate MISSING],
      "batch" => %w[batch MISSING --output-dir OUT],
    }.each do |command, argv|
      it "lets a caller of Cli.start(#{command.inspect}) rescue and continue" do
        Dir.mktmpdir do |dir|
          resolved = argv.map do |token|
            token.sub("MISSING", File.join(dir, "absent.json"))
              .sub("OUT", File.join(dir, "out"))
          end

          stdout = survives(<<~RUBY)
            require "elkrb"
            require "elkrb/cli"
            begin
              Elkrb::Cli.start(#{resolved.inspect})
            rescue StandardError => e
              puts "RESCUED \#{e.class}"
            end
            puts #{CliRunner::SENTINEL.inspect}
          RUBY

          expect(stdout).to include("RESCUED Elkrb::CommandFailed")
        end
      end
    end

    # Every argv above names a path that does NOT exist, and a nonexistent
    # path can only ever produce the print-and-wrap arm of fail_command. This
    # example exists to drive the RE-RAISE arm instead: ValidateCommand raises
    # CommandFailed itself, and fail_command has to pass it out untouched.
    # Without it, putting `exit 1` back on that arm passes the entire suite.
    it "lets a caller of Cli.start(\"validate\") rescue a re-raised " \
       "CommandFailed and continue" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "invalid.json")
        File.write(path,
                   { id: "root", children: [{ width: 10, height: 10 }],
                     edges: [] }.to_json)

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/cli"
          begin
            Elkrb::Cli.start(["validate", #{path.inspect}])
          rescue StandardError => e
            puts "RESCUED \#{e.class}"
          end
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        expect(stdout).to include("RESCUED Elkrb::CommandFailed")
      end
    end

    # A failure to REPORT must not preempt the raise. With stdout closed,
    # `say` raises Errno::EPIPE from inside fail_command; that used to escape
    # past the raise to Thor, which rescues EPIPE and calls exit(true) -- so
    # the caller lost its error AND its process, silently, at exit 0.
    #
    # The child restores stdout before printing, so the sentinel arriving at
    # all is what says it was still alive to print it.
    it "keeps the caller's error when stdout is a closed pipe" do
      Dir.mktmpdir do |dir|
        missing = File.join(dir, "absent.json")

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/cli"
          saved = $stdout.dup
          reader, writer = IO.pipe
          reader.close
          $stdout.reopen(writer)
          outcome = begin
            Elkrb::Cli.start(["layout", #{missing.inspect}])
            "NO RAISE"
          rescue StandardError => e
            "RESCUED \#{e.class}: \#{e.message} CAUSE=\#{e.cause.class}"
          ensure
            $stdout.reopen(saved)
          end
          puts outcome
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        # The class alone is a PROXY: a guard that swallowed the real error and
        # raised a CommandFailed of its own -- carrying the report writer's
        # message -- satisfies it while losing the failure entirely. Pin what a
        # caller actually needs instead: the missing path in the message, and
        # the original Errno still reachable as #cause.
        expect(stdout).to include("RESCUED Elkrb::CommandFailed")
        expect(stdout).to include(missing)
        expect(stdout).to include("CAUSE=Errno::ENOENT")
      end
    end

    # The defect this branch closes, and it is earlier still than the two
    # above. `verbose_output` writes a progress line BEFORE `layout` ever
    # reads the input file -- fail_command has not run yet, so its own
    # Errno::EPIPE guard cannot reach this write. With `--verbose` and a
    # closed stdout, that progress write raised Errno::EPIPE straight out of
    # `layout`'s body; `Errno::EPIPE < StandardError`, so `layout`'s own
    # rescue caught it and handed it to fail_command, which re-raised it
    # (the guard meant for a hung-up READER on a SUCCESSFUL run) -- and Thor
    # turned that into exit(true) before the missing file was ever noticed.
    # The caller lost its process with no exception it could ever have
    # caught, and never got as far as learning what actually failed.
    it "keeps the caller's error when a verbose progress line cannot be " \
       "printed" do
      Dir.mktmpdir do |dir|
        missing = File.join(dir, "absent.json")

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/cli"
          saved = $stdout.dup
          reader, writer = IO.pipe
          reader.close
          $stdout.reopen(writer)
          outcome = begin
            Elkrb::Cli.start(["layout", #{missing.inspect}, "--verbose"])
            "NO RAISE"
          rescue StandardError => e
            "RESCUED \#{e.class}: \#{e.message} CAUSE=\#{e.cause.class}"
          ensure
            $stdout.reopen(saved)
          end
          puts outcome
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        # Same shape as the non-verbose example above: class alone is a
        # proxy a swallowing guard could satisfy, so pin the missing path
        # and the real Errno underneath.
        expect(stdout).to include("RESCUED Elkrb::CommandFailed")
        expect(stdout).to include(missing)
        expect(stdout).to include("CAUSE=Errno::ENOENT")
      end
    end

    # The SAME shape, found by Codex's final gate on this branch after the
    # `--verbose` fix above landed: `convert`, `diagram`, `render`, and
    # `batch` each write a confirmation line AFTER their real result -- a
    # file -- is already on disk. That confirmation is not the result, so a
    # dead stdout must not be allowed to take the caller down with it. Before
    # the fix, all four of these SUCCEEDED (the file was written) and still
    # killed the caller: `Errno::EPIPE` from the trailing `puts` propagated
    # to `fail_command`'s deliberate EPIPE re-raise (meant only for a reader
    # hanging up on a successful `layout | head`), and Thor's `exit(true)`
    # took the caller's process with it -- with no exception it could ever
    # have caught, despite the operation having fully succeeded.
    #
    # `batch` additionally proved a SECOND bug from the same cause: its
    # completion write lives inside `DiagramCommand#run`, called once per
    # file inside `BatchCommand`'s own `rescue StandardError`. The escaping
    # `Errno::EPIPE` used to be caught THERE instead, so a successfully
    # diagrammed file was reported as a processing failure
    # ("Error processing ...: Broken pipe"). Fixing `DiagramCommand#run`
    # fixes both.
    #
    # Each example asserts TWO separate properties: the caller survives
    # (checked by `survives`), and the file was actually written -- a swallow
    # that also skipped the real work would pass the first and fail the
    # second.
    {
      "convert" => {
        setup: lambda { |dir|
          input = File.join(dir, "in.json")
          File.write(input, { id: "root", children: [], edges: [] }.to_json)
          [input, File.join(dir, "out.yaml")]
        },
        argv: ->(input, output) { ["convert", input, "-o", output] },
      },
      "diagram" => {
        setup: lambda { |dir|
          input = File.join(dir, "in.json")
          File.write(input, { id: "root", children: [], edges: [] }.to_json)
          [input, File.join(dir, "out.json")]
        },
        argv: ->(input, output) { ["diagram", input, "-o", output] },
      },
    }.each do |command, spec|
      it "keeps the caller alive when #{command}'s completion message " \
         "cannot be printed after a successful run" do
        Dir.mktmpdir do |dir|
          input, output = spec[:setup].call(dir)
          argv = spec[:argv].call(input, output)

          stdout = survives(<<~RUBY)
            require "elkrb"
            require "elkrb/cli"
            saved = $stdout.dup
            reader, writer = IO.pipe
            reader.close
            $stdout.reopen(writer)
            outcome = begin
              Elkrb::Cli.start(#{argv.inspect})
              "NO RAISE"
            rescue StandardError => e
              "RESCUED \#{e.class}: \#{e.message}"
            ensure
              $stdout.reopen(saved)
            end
            puts outcome
            puts #{CliRunner::SENTINEL.inspect}
          RUBY

          expect(stdout).to include("NO RAISE")
          expect(File.exist?(output)).to be(true), "#{command} did not " \
                                                   "write its result file " \
                                                   "-- a swallow that " \
                                                   "skips the real work " \
                                                   "would pass caller-" \
                                                   "survival too"
        end
      end
    end

    # `render` needs its own example: it shells out to Graphviz, so it uses
    # the fake `dot` from spec/support/fake_dot.rb rather than depending on a
    # real install. `with_fake_dot` sets PATH and FAKE_DOT_LOG in THIS
    # process's env, which `run_ruby`'s child inherits.
    it "keeps the caller alive when render's completion message cannot be " \
       "printed after a successful run" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          dot_file = File.join(dir, "in.dot")
          File.write(dot_file, "digraph { a -> b; }")
          output = File.join(dir, "out.svg")

          stdout = survives(<<~RUBY)
            require "elkrb"
            require "elkrb/cli"
            saved = $stdout.dup
            reader, writer = IO.pipe
            reader.close
            $stdout.reopen(writer)
            outcome = begin
              Elkrb::Cli.start(["render", #{dot_file.inspect}, "-o", #{output.inspect}])
              "NO RAISE"
            rescue StandardError => e
              "RESCUED \#{e.class}: \#{e.message}"
            ensure
              $stdout.reopen(saved)
            end
            puts outcome
            puts #{CliRunner::SENTINEL.inspect}
          RUBY

          expect(stdout).to include("NO RAISE")
          expect(File.exist?(output)).to be(true)
        end
      end
    end

    # `batch` needs its own example too: its completion write is a
    # multi-line summary block, and the property under test is the SECOND
    # bug described above -- the per-file diagram write must not get
    # miscounted as a processing error.
    #
    # This does NOT use `survives`: that helper only returns stdout, and the
    # second bug is only visible on STDERR (`warn`, unaffected by $stdout
    # being closed). A spec-auditor caught the gap this closes -- an earlier
    # version asserted only "NO RAISE" and the file's existence, which is
    # satisfied identically whether `DiagramCommand#run`'s completion write
    # is guarded or not, because `BatchCommand`'s own `rescue StandardError`
    # swallows either way. Reverting ONLY `diagram_command.rb`'s guard (with
    # `batch_command.rb`'s own guard left in place) now fails THIS assertion
    # -- and also the dedicated "diagram's completion message" example above,
    # since `diagram_command.rb` is exercised directly there too. Confirmed
    # by hand (2 failures, nothing else), restored, `git status --porcelain`
    # clean afterward.
    it "keeps the caller alive when batch's summary cannot be printed, " \
       "and does not miscount a successfully diagrammed file as an error" do
      Dir.mktmpdir do |dir|
        input_dir = File.join(dir, "in")
        FileUtils.mkdir_p(input_dir)
        File.write(File.join(input_dir, "g.json"),
                   { id: "root", children: [], edges: [] }.to_json)
        output_dir = File.join(dir, "out")

        source = <<~RUBY
          require "elkrb"
          require "elkrb/cli"
          saved = $stdout.dup
          reader, writer = IO.pipe
          reader.close
          $stdout.reopen(writer)
          outcome = begin
            Elkrb::Cli.start(["batch", #{input_dir.inspect},
                              "--output-dir", #{output_dir.inspect},
                              "--format", "json"])
            "NO RAISE"
          rescue StandardError => e
            "RESCUED \#{e.class}: \#{e.message}"
          ensure
            $stdout.reopen(saved)
          end
          puts outcome
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        stdout, stderr, status = run_ruby(source)

        expect(stdout).to include(CliRunner::SENTINEL), "died: #{stderr}"
        expect(status.exitstatus).to eq(0)
        expect(stdout).to include("NO RAISE")
        expect(File.exist?(File.join(output_dir, "g.json"))).to be(true)
        # The property the docstring above promises: a successfully
        # diagrammed file must not be reported as a processing error just
        # because ITS OWN completion write hit the same closed stdout.
        expect(stderr).not_to include("Error processing")
      end
    end

    # `batch`'s EARLY-RETURN arm, found by a design reviewer of the previous
    # example on this same branch, refuting the belief that it belonged with
    # `validate`'s success message and `layout`'s bare-stdout write (neither
    # of which precede any file write, and both of which ARE their command's
    # entire result). This notice precedes no file write either, but it
    # is not a result any caller depends on -- an empty directory has
    # nothing to report beyond "nothing happened", so wrapping it changes no
    # observable outcome for a caller that never sees the message. Before
    # the fix, reproduced directly: a closed stdout here killed the caller
    # via the same `Errno::EPIPE` -> `fail_command` re-raise -> Thor
    # `exit(true)` path as the four sites above, on a directory holding no
    # matching files at all.
    it "keeps the caller alive when batch's empty-directory notice cannot " \
       "be printed" do
      Dir.mktmpdir do |dir|
        input_dir = File.join(dir, "in")
        FileUtils.mkdir_p(input_dir)
        output_dir = File.join(dir, "out")

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/cli"
          saved = $stdout.dup
          reader, writer = IO.pipe
          reader.close
          $stdout.reopen(writer)
          outcome = begin
            Elkrb::Cli.start(["batch", #{input_dir.inspect},
                              "--output-dir", #{output_dir.inspect}])
            "NO RAISE"
          rescue StandardError => e
            "RESCUED \#{e.class}: \#{e.message}"
          ensure
            $stdout.reopen(saved)
          end
          puts outcome
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        expect(stdout).to include("NO RAISE")
      end
    end

    # The same invariant, one layer earlier and strictly harder. `layout`
    # reports THROUGH fail_command, so guarding fail_command covers it.
    # `validate` reports from inside the command, BEFORE any raise, so a dead
    # stdout used to kill the report and the raise together: the EPIPE escaped
    # to Thor, which rescues it and calls exit(true), and the caller died at
    # exit 0 with no exception it could ever have caught.
    it "keeps the caller's error when a validation report cannot be printed" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "invalid.json")
        File.write(path,
                   { id: "root", children: [{ width: 10, height: 10 }],
                     edges: [] }.to_json)

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/cli"
          saved = $stdout.dup
          reader, writer = IO.pipe
          reader.close
          $stdout.reopen(writer)
          outcome = begin
            Elkrb::Cli.start(["validate", #{path.inspect}])
            "NO RAISE"
          rescue StandardError => e
            "RESCUED \#{e.class}: \#{e.message}"
          ensure
            $stdout.reopen(saved)
          end
          puts outcome
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        # Identity, not just class -- see the layout example above for why.
        # The FILE and the COUNT are the whole content of a validation
        # failure, so a failed report must not cost the caller either.
        expect(stdout)
          .to include("RESCUED Elkrb::CommandFailed: #{path} has 1 error(s)")
      end
    end

    # The other way reporting dies. lutaml-model echoes the offending token
    # into its message, so a file whose FIRST token holds invalid UTF-8 hands
    # fail_command a message `say` cannot print: it raised ArgumentError,
    # which escaped in place of the raise, and a caller rescuing the
    # documented Elkrb::CommandFailed missed the failure entirely.
    #
    # The child prints only the error's CLASS. `puts` would accept the invalid
    # bytes quite happily -- it is Thor's `say` that rejects them, which is the
    # whole point of the example -- but an expectation carrying invalid UTF-8
    # is fragile for no gain, and the class is what identifies the failure.
    it "keeps the caller's error when the failure message is not valid UTF-8" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "invalid-utf8.json")
        File.binwrite(path, "\xFF\xFE not json")

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/cli"
          begin
            Elkrb::Cli.start(["layout", #{path.inspect}])
          rescue StandardError => e
            puts "RESCUED \#{e.class}"
          end
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        expect(stdout).to include("RESCUED Elkrb::CommandFailed")
      end
    end

    # CommandFailed inherits Elkrb::Error, not StandardError directly. A caller
    # using the narrower idiom this repo documents must still be able to catch
    # it; every other example here rescues StandardError, which cannot tell the
    # two apart.
    it "lets a caller rescuing Elkrb::Error, not StandardError, continue" do
      Dir.mktmpdir do |dir|
        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/cli"
          begin
            Elkrb::Cli.start(["layout", #{File.join(dir, 'absent.json').inspect}])
          rescue Elkrb::Error => e
            puts "RESCUED \#{e.class}"
          end
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        expect(stdout).to include("RESCUED Elkrb::CommandFailed")
      end
    end

    # A caller that rescues CommandFailed must still reach the original
    # failure. Ruby sets #cause automatically on a re-raise inside a rescue,
    # so this pins the SHAPE of fail_command: move the raise outside the
    # rescue body -- a plausible refactor -- and cause becomes nil.
    #
    # lutaml-model wraps the JSON error before elkrb sees it, so one link out
    # is InvalidFormatError; JSON::ParserError is two links out.
    it "keeps the original failure as the raised error's cause" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.json")
        File.write(path, "this is not json")

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/cli"
          begin
            Elkrb::Cli.start(["layout", #{path.inspect}])
          rescue Elkrb::CommandFailed => e
            puts "CAUSE \#{e.cause.class}"
          end
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        expect(stdout).to include("CAUSE Lutaml::Model::InvalidFormatError")
      end
    end
  end

  describe "Elkrb::Commands::ValidateCommand" do
    it "lets a caller of #run rescue an invalid graph and continue" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "invalid.json")
        File.write(path,
                   { id: "root", children: [{ width: 10, height: 10 }],
                     edges: [] }.to_json)

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/commands/validate_command"
          begin
            Elkrb::Commands::ValidateCommand.new(#{path.inspect}, {}).run
          rescue StandardError => e
            puts "RESCUED \#{e.class}: \#{e.message}"
          end
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        expect(stdout).to include("RESCUED Elkrb::CommandFailed")
        expect(stdout).to match(/has 1 error\(s\)/)
      end
    end

    # Thor is not involved here, so nothing turns this into an exit -- the
    # caller survives either way. What it pins is the error IDENTITY: the
    # unguarded `puts` raised Errno::EPIPE straight out of #run, so a caller
    # using the documented `rescue Elkrb::CommandFailed` idiom saw no failure
    # at all, and one rescuing StandardError got a pipe error where the real
    # fault was an invalid graph.
    it "reports an invalid graph as CommandFailed even when stdout is dead" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "invalid.json")
        File.write(path,
                   { id: "root", children: [{ width: 10, height: 10 }],
                     edges: [] }.to_json)

        stdout = survives(<<~RUBY)
          require "elkrb"
          require "elkrb/commands/validate_command"
          saved = $stdout.dup
          reader, writer = IO.pipe
          reader.close
          $stdout.reopen(writer)
          outcome = begin
            Elkrb::Commands::ValidateCommand.new(#{path.inspect}, {}).run
            "NO RAISE"
          rescue StandardError => e
            "RESCUED \#{e.class}: \#{e.message}"
          ensure
            $stdout.reopen(saved)
          end
          puts outcome
          puts #{CliRunner::SENTINEL.inspect}
        RUBY

        # Same identity assertion as the Cli.start path, at the site that
        # actually raises. #cause is deliberately NOT asserted here: `attempt`
        # finishes its own rescue before this raise, so $! is already clear and
        # the cause is nil. Pinning it would pin nothing.
        expect(stdout)
          .to include("RESCUED Elkrb::CommandFailed: #{path} has 1 error(s)")
      end
    end
  end

  describe "rake corpus:dump" do
    def invoke_dump(dir)
      survives(<<~RUBY)
        require "rake"
        Rake.application.init("rake", ["--rakefile", "Rakefile"])
        Rake.application.load_rakefile
        begin
          Rake::Task["corpus:dump"].invoke(#{dir.inspect})
        rescue StandardError => e
          puts "RESCUED \#{e.class}: \#{e.message}"
        end
        puts #{CliRunner::SENTINEL.inspect}
      RUBY
    end

    it "raises the usage error for an empty directory argument" do
      stdout = invoke_dump("")

      expect(stdout).to include("RESCUED ArgumentError")
      expect(stdout).to include("usage: rake 'corpus:dump[dir]'")
    end

    # The other direction. Without it, deleting the guard's CONDITION and
    # leaving the raise unconditional passes -- the task would refuse every
    # directory, including valid ones, and no example would notice.
    #
    # The directory deliberately holds a foreign file, so the corpus runner
    # refuses to claim it and THE DUMP ITSELF NEVER RUNS. That is sufficient
    # here: the guard under test is the usage check in the Rakefile, and
    # reaching the runner at all is already past it. Naming the runner in the
    # failure it does raise is what proves that, which is why the positive
    # assertion comes first -- `not_to include("usage: rake")` on its own also
    # passes when the child dies before the task ever starts.
    it "does not raise the usage error when a directory is given" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "not-ours.txt"), "junk")

        stdout = invoke_dump(dir)

        expect(stdout).to include("corpus_runner.rb")
        expect(stdout).not_to include("usage: rake")
      end
    end
  end
end
