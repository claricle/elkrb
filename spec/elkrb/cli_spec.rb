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
    end

    # A UTF-8 BOM used to stay glued to the file's first declaration, which
    # then matched no ELKT rule and was dropped silently: `node a`
    # disappeared and edge e0 was left pointing at a node no longer in the
    # graph. FormatSniffer strips the mark by byte before the parser ever
    # sees it, so on THIS path that is what makes every declaration
    # survive; ElktParser carries a second, redundant strip for callers
    # that reach it directly. Measured: the BOM never arrives at
    # ElktParser here, so do not read this example as covering that one.
    # Both ids in order, not just a count -- dropping `a` and keeping `b`
    # is the exact shape of the bug.
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
