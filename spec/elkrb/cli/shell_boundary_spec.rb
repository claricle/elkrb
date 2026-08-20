# frozen_string_literal: true

require "spec_helper"
require "support/cli_runner"
require "json"
require "yaml"
require "tmpdir"
require "fileutils"

RSpec.describe "elkrb CLI shell boundary" do
  include CliRunner

  let(:simple_graph_path) { File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json") }

  describe "layout" do
    it "exits 0 for a JSON file with no recognized extension" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "graph.noext")
        FileUtils.cp(simple_graph_path, file)

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 0 for a YAML file with no recognized extension" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "graph.noext")
        graph = JSON.parse(File.read(simple_graph_path))
        File.write(file, graph.to_yaml)

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 1 with a stderr message for unparsable input" do
      garbage_file = File.join(CliRunner::ROOT, "spec/fixtures/corpus/garbage.txt")

      stdout, stderr, status = run_elkrb("layout", garbage_file)

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq("")
      expect(stderr).not_to eq("")
    end

    it "exits 0 for an ELKT file the sniff-then-parse fallback can read" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "graph.elkt")
        File.write(file, "node n1\nnode n2\nedge n1 -> n2\n")

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 0 for an ELKT file with only a layout option, no nodes" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "options_only.elkt")
        # "a: b" after the first colon is not valid YAML, so this falls
        # through to ElktParser, which reads it as a property line — the
        # empty-graph guard must not reject it just because it has no nodes.
        File.write(file, "custom: a: b\n")

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end
  end

  describe "batch" do
    it "exits non-zero when any file in the directory fails" do
      Dir.mktmpdir do |input_dir|
        Dir.mktmpdir do |output_dir|
          FileUtils.cp(simple_graph_path, File.join(input_dir, "good.json"))
          File.write(File.join(input_dir, "bad.json"), "not valid json")

          _stdout, _stderr, status = run_elkrb(
            "batch", input_dir, "--output-dir", output_dir, "--format", "dot"
          )

          expect(status.exitstatus).not_to eq(0)
        end
      end
    end
  end
end
