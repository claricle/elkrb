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
    end

    # A UTF-8 BOM makes the ELKT parser drop the file's first declaration,
    # so `node a` disappears and edge e0 is left pointing at a node that is
    # no longer in the graph. Tracked as gap1-10; the ELKT parser rewrite
    # owns the fix and un-pends this.
    it "keeps every declaration of a BOM-prefixed ELKT file" do
      pending("gap1-10")

      Dir.mktmpdir do |dir|
        output = File.join(dir, "bom.json")

        _stdout, _stderr, status = run_elkrb(
          "convert", corpus_fixture("bom.elkt"), "-o", output
        )

        expect(status.exitstatus).to eq(0)
        graph = JSON.parse(File.read(output))
        ids = graph["children"].map { |child| child["id"] }
        expect(ids).to contain_exactly("a", "b")
      end
    end
  end
end
