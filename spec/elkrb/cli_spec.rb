# frozen_string_literal: true

require "spec_helper"
require "support/cli_runner"
require "support/fake_dot"
require "json"
require "tmpdir"

RSpec.describe "elkrb CLI" do
  include CliRunner
  include FakeDot

  describe "version" do
    it "exits 0 and prints the gem version" do
      stdout, _stderr, status = run_elkrb("version")

      expect(status.exitstatus).to eq(0)
      expect(stdout).to include(Elkrb::VERSION)
    end
  end

  describe "algorithms" do
    it "exits 0" do
      _stdout, _stderr, status = run_elkrb("algorithms")

      expect(status.exitstatus).to eq(0)
    end
  end

  describe "usage errors" do
    # `Kernel#warn` is a no-op once `-W0` sets `$VERBOSE` to nil, so routing
    # the usage-error report through it silently drops the only diagnostic a
    # mistyped command produces. `$stderr.puts` is not silenced by `-W0`,
    # which is the property this pins: not just "stderr is non-empty" (that
    # would equally pass piping through `warn` under the default verbosity)
    # but "still non-empty with warnings off".
    it "still reports an unknown command on stderr under ruby -W0" do
      stdout, stderr, status = run_elkrb(
        "no-such-command", env: { "RUBYOPT" => "-W0" }
      )

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq("")
      expect(stderr).to include('Could not find command "no-such-command"')
    end

    # Thor's own `start` contract re-raises under THOR_DEBUG=1 so the
    # backtrace reaches the user; `rescue Thor::Error => e; warn e.message`
    # swallowed it unconditionally. A one-line message and a backtrace both
    # land on stderr, so exit status and non-emptiness cannot tell them
    # apart -- only the backtrace names the raising class and file, which is
    # what distinguishes "the backtrace survived" from "just the message
    # again".
    it "lets THOR_DEBUG=1 report the backtrace for an unknown command" do
      _stdout, stderr, status = run_elkrb(
        "no-such-command", env: { "THOR_DEBUG" => "1" }
      )

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("Thor::UndefinedCommandError")
      expect(stderr.lines.length).to be > 1
    end
  end

  describe "layout" do
    # A reader hanging up ends a SUCCESSFUL run, so the status must stay 0.
    # Keep this: it is the only thing holding fail_command's
    # `raise error if error.is_a?(Errno::EPIPE)` in place. Drop that line and
    # the EPIPE is wrapped into CommandFailed instead, which exe/elkrb turns
    # into exit 1 -- a working pipeline starts failing.
    #
    # The reader takes ONE byte and closes, rather than shelling out to
    # `head`, whose own buffering can drain the pipe fast enough that the
    # child finishes writing and never sees EPIPE at all.
    it "exits 0 when the reader closes the pipe early" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "wide.json")
        pad = "p" * 2000
        payload = JSON.dump(
          id: "root", edges: [],
          children: (1..100).map do |i|
            { id: "n#{i}-#{pad}", width: 40, height: 20 }
          end
        )
        File.write(path, payload)

        # Guard the guard. Long ids inflate the payload without inflating the
        # layout work, and the laid-out JSON is at least this large. Under the
        # 64 KiB pipe buffer the child would finish writing before the reader
        # hung up, and this example would pass having exercised nothing.
        expect(payload.bytesize).to be > 65_536

        reader, writer = IO.pipe
        pid = Process.spawn(RbConfig.ruby, "-I#{CliRunner::LIB}",
                            CliRunner::EXE, "layout", path,
                            out: writer, err: File::NULL)
        writer.close
        reader.readpartial(1)
        reader.close
        _pid, status = Process.wait2(pid)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 0 and prints JSON to stdout" do
      stdout, _stderr, status = run_elkrb(
        "layout", File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json")
      )

      expect(status.exitstatus).to eq(0)
      expect { JSON.parse(stdout) }.not_to raise_error
    end

    it "prints only JSON to stdout with --verbose" do
      stdout, _stderr, status = run_elkrb(
        "layout", File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json"),
        "--verbose"
      )

      expect(status.exitstatus).to eq(0)
      expect { JSON.parse(stdout) }.not_to raise_error
    end

    it "exits non-zero when FILE is missing from the command line" do
      _stdout, _stderr, status = run_elkrb("layout")

      expect(status.exitstatus).not_to eq(0)
    end

    it "reports a missing file on stderr, not stdout" do
      stdout, stderr, status = run_elkrb(
        "layout", File.join(CliRunner::ROOT, "missing.json")
      )

      expect(stdout).to eq("")
      expect(stderr).not_to eq("")
      expect(status.exitstatus).to eq(1)
    end

    it "resolves a graph-carried algorithm when --algorithm is not given" do
      Dir.mktmpdir do |dir|
        input_file = File.join(dir, "graph.json")
        # Chained edges so box (ignores edges, packs into a row) and layered
        # (ranks by edge direction, stacks into a column) are guaranteed to
        # disagree. Disconnected nodes let both land on the same grid.
        File.write(input_file, {
          id: "root",
          layoutOptions: { "elk.algorithm" => "box" },
          children: [
            { id: "n1", width: 30, height: 30 },
            { id: "n2", width: 30, height: 30 },
            { id: "n3", width: 30, height: 30 },
          ],
          edges: [
            { id: "e1", sources: ["n1"], targets: ["n2"] },
            { id: "e2", sources: ["n2"], targets: ["n3"] },
          ],
        }.to_json)

        # Same file, same lack of an explicit flag on the graph-carried run --
        # only the ELK-standard layoutOptions selects box. Asserting the
        # PROPERTY (a different algorithm actually ran) rather than pinning
        # exact positions: comparing against an explicit --algorithm layered
        # run on the identical input is what distinguishes "the graph-carried
        # selector was honoured" from "it silently ran layered either way".
        graph_carried_stdout, _e1, graph_carried_status =
          run_elkrb("layout", input_file)
        layered_stdout, _e2, layered_status =
          run_elkrb("layout", input_file, "--algorithm", "layered")

        expect(graph_carried_status.exitstatus).to eq(0)
        expect(layered_status.exitstatus).to eq(0)
        expect(JSON.parse(graph_carried_stdout))
          .not_to eq(JSON.parse(layered_stdout))
      end
    end

    it "does not print a blank algorithm with --verbose and no --algorithm" do
      _stdout, stderr, status = run_elkrb(
        "layout", File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json"),
        "--verbose"
      )

      expect(status.exitstatus).to eq(0)
      # RC10: verbose progress lines are on stderr, not stdout -- see
      # "prints only JSON to stdout with --verbose" above.
      expect(stderr)
        .to include("Using algorithm: the graph's own, else layered")
    end

    # A Thor default would always beat the graph's own elk.algorithm.
    %w[layout diagram batch].each do |command|
      it "gives #{command}'s --algorithm no default" do
        require "elkrb/cli"
        option = Elkrb::Cli.commands[command].options[:algorithm]

        expect(option.default).to be_nil
      end
    end
  end

  describe "render" do
    posix_only = "fake_dot.rb installs a shebang script, which Windows " \
                 "will not execute from PATH"
    windows_skip_reason = posix_only if Gem.win_platform?

    it "never shells out to a string built from the output path",
       skip: windows_skip_reason do
      malicious_dot_file = File.join(CliRunner::ROOT,
                                     "spec/fixtures/render_input.dot")

      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          # The payload CLOSES a single quote before its metacharacters.
          # A shell string built by wrapping each argument in quotes
          # neutralises a bare `a;touch PWNED;.svg`, so that payload stays
          # green against the very implementation this example exists to
          # refuse. This one escapes the quoting, so the example fails when
          # the command is a shell string and passes when it is argv.
          malicious_output = File.join(dir, "a'; touch PWNED; echo '.svg")

          Dir.chdir(dir) do
            run_elkrb("render", malicious_dot_file, "-o", malicious_output)
          end

          log_entries = File.read(log_path).lines.flat_map do |line|
            line.chomp.split("\0")
          end
          expect(log_entries).not_to be_empty

          # The path survives as ONE argv element. `-o` and the path are a
          # separate token pair now, so the exact string is asserted rather
          # than an `-o<path>` alternative: an assertion that accepts both
          # shapes cannot tell a fix from the shape it replaced.
          expect(log_entries).to include(malicious_output)
          expect(File.exist?(File.join(dir, "PWNED"))).to be(false)
        end
      end
    end
  end

  describe "validate" do
    let(:invalid_graph) do
      { id: "root", children: [{ width: 10, height: 10 }], edges: [] }
    end
    let(:valid_graph) do
      { id: "root", children: [{ id: "n1", width: 10, height: 10 }], edges: [] }
    end

    it "exits 1 and reports an invalid graph's errors exactly once, " \
       "with no backtrace" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "invalid.json")
        File.write(path, invalid_graph.to_json)

        stdout, stderr, status = run_elkrb("validate", path)

        expect(status.exitstatus).to eq(1)
        # Which stream carries the report is card 26's business; that it is
        # reported at all, and reported ONCE, is this example's. Count rather
        # than `include`: `include` passes just as happily on a report printed
        # twice, which is the regression the name promises to catch.
        #
        # Both LINES are counted. The summary alone would leave a mutation
        # that repeats only the bullet list undetected, and "errors exactly
        # once" is a claim about the errors, not just the headline.
        report = stdout + stderr
        expect(report.scan("has 1 error(s)").length).to eq(1)
        expect(report.scan("  • ").length).to eq(1)
        expect(stdout + stderr).not_to include("Error:")
        expect(stderr).not_to match(/\.rb:\d+:in /)
      end
    end

    # Regression cover, not cover of this change: exit 0 here is identical
    # before and after. It is the positive control that stops a later change
    # failing what used to succeed.
    it "exits 0 for a valid graph" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "valid.json")
        File.write(path, valid_graph.to_json)

        _stdout, _stderr, status = run_elkrb("validate", path)

        expect(status.exitstatus).to eq(0)
      end
    end

    # The counterpart to layout's early-hangup example. The validation report
    # belongs on stderr, and a consumer closing that diagnostic stream must
    # not turn a genuine validation failure into success.
    #
    # This used to depend on the size of the error list: below the 64 KiB pipe
    # buffer `elkrb validate bad.json | head` exited 1, and above it the EPIPE
    # escaped to Thor and it exited 0. Same failing graph, two statuses.
    #
    # 4000 invalid children report ~183 KB, so the write blocks and the hangup
    # is reached. Under the buffer this example would exit 1 without touching
    # the EPIPE path at all -- reverting BestEffortWrite.attempt in
    # ValidateCommand is what proves it is live rather than merely green.
    it "exits 1 when the reader closes the pipe on a failing validation" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "many-errors.json")
        payload = JSON.dump(
          id: "root", edges: [],
          children: Array.new(4000) { { width: 10, height: 10 } }
        )
        File.write(path, payload)

        reader, writer = IO.pipe
        pid = Process.spawn(RbConfig.ruby, "-I#{CliRunner::LIB}",
                            CliRunner::EXE, "validate", path,
                            out: File::NULL, err: writer)
        writer.close
        reader.readpartial(1)
        reader.close
        _pid, status = Process.wait2(pid)

        expect(status.exitstatus).to eq(1)
      end
    end
  end

  # bom.elkt and garbage.txt sit in spec/fixtures/corpus/ but are excluded
  # from the layout corpus by its JSON-only glob. Only the CLI reads them,
  # through format detection. shell_boundary_spec.rb drives the same two
  # fixtures through `layout`; these drive `convert` and the exact refusal
  # message, so the two files cover different commands, not the same one
  # twice.
  describe "input format detection" do
    def corpus_fixture(name)
      File.join(CliRunner::ROOT, "spec/fixtures/corpus", name)
    end

    it "exits 1 and says why on stderr when no format can parse the file" do
      stdout, stderr, status = run_elkrb(
        "layout", corpus_fixture("garbage.txt")
      )

      expect(status.exitstatus).to eq(1)
      # The message names the supported formats. Pinning that exact text,
      # not merely "something was printed", is what separates a parse
      # refusal from a leaked internal error: before FormatSniffer this
      # said "input format is invalid, try to pass correct `json` format"
      # -- a lutaml message about the LAST format tried, from a CLI that
      # tries three.
      expect(stderr)
        .to include("Unable to parse input file. Supported formats:")
      expect(stdout).to eq("")
      # `not_to match` rather than `eq("")` because the gemspec shells out
      # to `git ls-files`, so a checkout with no .git writes unrelated noise
      # here. The regex keys on `.rb` frames, which a real CLI backtrace
      # always carries. Probing it with a BARE `ruby -e 'raise'` reads false
      # -- that backtrace is a single `-e:1:in '<main>'` frame naming no .rb
      # file. A `ruby -e` that drives the CLI and lets the error escape does
      # produce lib/elkrb/*.rb frames, and does match.
      expect(stderr).not_to match(/\.rb:\d+:in /)
    end

    # yaml_no_extension.txt holds the same graph as simple_graph.json,
    # reserialized to YAML.
    it "falls back to YAML for a file with no JSON or YAML extension" do
      stdout, _stderr, status = run_elkrb(
        "layout", corpus_fixture("yaml_no_extension.txt")
      )

      expect(status.exitstatus).to eq(0)
      result = JSON.parse(stdout)
      expect(result["children"].map { |c| c["id"] }).to eq(%w[n1 n2 n3])
    end

    # A UTF-8 BOM left glued to the file's first declaration matches no ELKT
    # rule and is dropped silently, so FormatSniffer strips the mark by byte
    # before the parser ever sees it. Assert both ids in order, not just a
    # count -- dropping `a` and keeping `b` is the exact shape of that bug --
    # and assert the edge too: a parser that kept both nodes while dropping
    # e0 would still pass a children-only check.
    it "keeps every declaration of a BOM-prefixed ELKT file" do
      Dir.mktmpdir do |dir|
        output = File.join(dir, "bom.json")

        _stdout, _stderr, status = run_elkrb(
          "convert", corpus_fixture("bom.elkt"), "-o", output
        )

        expect(status.exitstatus).to eq(0)
        graph = JSON.parse(File.read(output))
        ids = graph["children"].map { |child| child["id"] }
        expect(ids).to eq(%w[a b])
        expect(graph["edges"].map { |e| [e["id"], e["sources"], e["targets"]] })
          .to eq([["e0", ["a"], ["b"]]])
      end
    end
  end

  describe "with a diagnostic stream the consumer has closed" do
    let(:fixture) do
      File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json")
    end
    let(:missing) { "/nope/missing.json" }

    # `layout` emits its first --verbose line before it reads the input, so a
    # closed stderr raised EPIPE, the generic rescue caught it, and the run
    # aborted before writing anything -- while still exiting 0. A caller
    # piping stderr to `head -1` got success and no output file.
    it "still writes the output file when stderr is gone" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out.json")

        status = run_elkrb_with_stream_closed(
          :err, "layout", "--verbose", "-o", out, fixture
        )

        # Name the file, not just the status: exiting 0 was exactly the bug.
        expect(File.exist?(out)).to be(true)
        expect(JSON.parse(File.read(out))).to include("id")
        expect(status).to eq(0)
      end
    end

    # The full truth table, because this guard was wrong in BOTH directions:
    # a valid layout with stdout closed exited 1 reporting "Broken pipe",
    # while a genuine failure with stderr closed exited 0. One example per
    # outcome, since the outcomes are the property.
    {
      "a valid layout with stdout closed" => [:out, :ok, 0],
      "a valid layout with stderr closed" => [:err, :verbose, 0],
      "a missing file with stdout closed" => [:out, :missing, 1],
      "a missing file with stderr closed" => [:err, :missing, 1],
    }.each do |label, (stream, shape, expected)|
      it "exits #{expected} for #{label}" do
        args = case shape
               when :ok then ["layout", fixture]
               when :verbose then ["layout", "--verbose", fixture]
               else ["layout", missing]
               end

        expect(run_elkrb_with_stream_closed(stream, *args)).to eq(expected)
      end
    end
  end
end
