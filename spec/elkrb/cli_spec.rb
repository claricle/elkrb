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
      stdout, _stderr, status = run_elkrb("layout",
                                          "spec/fixtures/simple_graph.json")

      expect(status.exitstatus).to eq(0)
      expect { JSON.parse(stdout) }.not_to raise_error
    end

    it "prints only JSON to stdout with --verbose" do
      stdout, _stderr, status = run_elkrb(
        "layout", "spec/fixtures/simple_graph.json", "--verbose"
      )

      expect(status.exitstatus).to eq(0)
      expect { JSON.parse(stdout) }.not_to raise_error
    end

    it "exits non-zero when FILE is missing from the command line" do
      _stdout, _stderr, status = run_elkrb("layout")

      expect(status.exitstatus).not_to eq(0)
    end

    it "reports a missing file on stderr, not stdout" do
      stdout, stderr, status = run_elkrb("layout", "missing.json")

      expect(stdout).to eq("")
      expect(stderr).not_to eq("")
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "render" do
    posix_only = "fake_dot.rb's script needs a POSIX shell; " \
                 "not portable to Windows"
    windows_skip_reason = posix_only if Gem.win_platform?

    it "never shells out to a string built from the output path",
       skip: windows_skip_reason do
      malicious_dot_file = File.join(CliRunner::ROOT, "spec/fixtures/x.dot")

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

          expect(log_entries).to include(malicious_output)
          expect(File.exist?(File.join(dir, "PWNED"))).to be(false)
        end
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
          :err, "layout", "--verbose", "-o", out,
          File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json")
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
