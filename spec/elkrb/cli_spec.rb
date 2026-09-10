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
      pending("RC10")

      stdout, _stderr, status = run_elkrb(
        "layout", File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json"),
        "--verbose"
      )

      expect(status.exitstatus).to eq(0)
      expect { JSON.parse(stdout) }.not_to raise_error
    end

    it "exits non-zero when FILE is missing from the command line" do
      pending("RC10")

      _stdout, _stderr, status = run_elkrb("layout")

      expect(status.exitstatus).not_to eq(0)
    end

    it "reports a missing file on stderr, not stdout" do
      pending("RC10")

      stdout, stderr, status = run_elkrb(
        "layout", File.join(CliRunner::ROOT, "missing.json")
      )

      expect(stdout).to eq("")
      expect(stderr).not_to eq("")
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "render" do
    if Gem.win_platform?
      windows_skip_reason = "fake_dot.rb installs a shebang script, which " \
                            "Windows will not execute from PATH"
    end

    it "never shells out to a string built from the output path",
       skip: windows_skip_reason do
      malicious_dot_file = File.join(CliRunner::ROOT,
                                     "spec/fixtures/render_input.dot")

      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          malicious_output = File.join(dir, "a;touch PWNED;.svg")

          Dir.chdir(dir) do
            run_elkrb("render", malicious_dot_file, "-o", malicious_output)
          end

          log_entries = File.read(log_path).lines.flat_map do |line|
            line.chomp.split("\0")
          end
          expect(log_entries).not_to be_empty

          pending("RC10")

          # Accept either argv shape a real fix might land: a separate
          # "-o" token pair, or today's "-o<path>" suffix kept but built
          # via system(*argv) instead of a shell string. Either way the
          # malicious path must survive as one argv element, not get
          # split by a shell.
          expect(log_entries)
            .to include(malicious_output)
            .or include("-o#{malicious_output}")
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

    # The counterpart to layout's early-hangup example, and it goes the OTHER
    # way on purpose. There, the reader hanging up ends a run that SUCCEEDED,
    # so the status stays 0. Here the validation genuinely failed, and the
    # status must stay 1 whether or not anyone read the report.
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
                            out: writer, err: File::NULL)
        writer.close
        reader.readpartial(1)
        reader.close
        _pid, status = Process.wait2(pid)

        expect(status.exitstatus).to eq(1)
      end
    end
  end

  # bom.elkt and garbage.txt sit in spec/fixtures/corpus/ but are excluded
  # from the layout corpus by its JSON-only glob. The CLI's format
  # detection is the only thing that reads them, so this is where they earn
  # their place.
  describe "input format detection" do
    def corpus_fixture(name)
      File.join(CliRunner::ROOT, "spec/fixtures/corpus", name)
    end

    it "exits 1 and says why when no format can parse the file" do
      stdout, stderr, status = run_elkrb(
        "layout", corpus_fixture("garbage.txt")
      )

      expect(status.exitstatus).to eq(1)
      # Which stream carries it is RC10's business; that it is reported at
      # all is this example's, so an unrelated crash cannot pass for a
      # parse refusal.
      expect(stdout + stderr).to include("input format")
      # Keep this: of the two backtrace assertions in this file, it is the
      # one that runs the real `exe/elkrb` through fail_command's
      # PRINT-AND-WRAP arm, and so the only one proving the entry point
      # rescues what that arm raises -- the other goes through the RE-RAISE
      # arm. The exit status is 1 either way, so nothing else here can tell a
      # clean refusal from an escaped backtrace.
      #
      # `not_to match` rather than `eq("")` because the gemspec shells out
      # to `git ls-files`, so a checkout with no .git writes unrelated noise
      # here. The regex keys on `.rb` frames, which a real CLI backtrace
      # always carries. Probing it with a BARE `ruby -e 'raise'` reads false
      # -- that backtrace is a single `-e:1:in '<main>'` frame naming no .rb
      # file. A `ruby -e` that drives the CLI and lets the error escape does
      # produce lib/elkrb/*.rb frames, and does match.
      expect(stderr).not_to match(/\.rb:\d+:in /)
    end

    # A UTF-8 BOM used to make the ELKT parser drop a file's first declaration
    # (gap1-10), so `node a` vanished and edge e0 pointed at a node that was
    # gone. Converting spec/fixtures/corpus/bom.elkt gave child ids ["b"] at
    # 34d339b and ["a", "b"] at 9ed11d0.
    #
    # Assert the edge as well as the children: that fixture declares three
    # things, and a parser that kept both nodes while dropping e0 would pass a
    # children-only check.
    it "keeps every declaration of a BOM-prefixed ELKT file" do
      Dir.mktmpdir do |dir|
        output = File.join(dir, "bom.json")

        _stdout, _stderr, status = run_elkrb(
          "convert", corpus_fixture("bom.elkt"), "-o", output
        )

        expect(status.exitstatus).to eq(0)
        graph = JSON.parse(File.read(output))
        ids = graph["children"].map { |child| child["id"] }
        expect(ids).to contain_exactly("a", "b")
        expect(graph["edges"].map { |e| [e["id"], e["sources"], e["targets"]] })
          .to eq([["e0", ["a"], ["b"]]])
      end
    end
  end
end
