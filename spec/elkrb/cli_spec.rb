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
      stdout, _stderr, status = run_elkrb("layout", "spec/fixtures/simple_graph.json")

      expect(status.exitstatus).to eq(0)
      expect { JSON.parse(stdout) }.not_to raise_error
    end

    it "prints only JSON to stdout with --verbose" do
      pending("RC10")

      stdout, _stderr, status = run_elkrb(
        "layout", "spec/fixtures/simple_graph.json", "--verbose"
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

      stdout, stderr, status = run_elkrb("layout", "missing.json")

      expect(stdout).to eq("")
      expect(stderr).not_to eq("")
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "render" do
    windows_skip_reason = "fake_dot.rb's script needs a POSIX shell; not portable to Windows" if Gem.win_platform?

    it "never shells out to a string built from the output path", skip: windows_skip_reason do
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

          pending("RC10")

          # Accept either argv shape a real fix might land: a separate
          # "-o" token pair, or today's "-o<path>" suffix kept but built
          # via system(*argv) instead of a shell string. Either way the
          # malicious path must survive as one argv element, not get
          # split by a shell.
          expect(log_entries).to include(malicious_output).or include("-o#{malicious_output}")
          expect(File.exist?(File.join(dir, "PWNED"))).to be(false)
        end
      end
    end
  end
end
