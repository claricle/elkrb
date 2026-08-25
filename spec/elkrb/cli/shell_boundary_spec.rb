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
        file = File.join(dir, "options_only.noext")
        # Valid YAML (a one-key mapping with no recognized Graph fields),
        # so from_yaml succeeds silently with an empty/hollow model. The
        # guard must still fall through to ElktParser rather than treating
        # that hollow "success" as a real (if empty) graph.
        File.write(file, "algorithm: layered\n")

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 1 for a YAML mapping with no recognized graph or ELKT content" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "garbage_mapping.noext")
        # Also valid (if pointless) YAML: succeeds silently as a hollow
        # model, same as the case above. The hyphen keeps it from matching
        # ElktParser's `key: value` property regex too (\w excludes "-"),
        # so unlike "algorithm: layered" this really is garbage all the
        # way down -- must be rejected, not returned as an empty "success".
        File.write(file, "unknown-key: value\n")

        stdout, stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("")
        expect(stderr).not_to eq("")
      end
    end

    it "keeps the children of a flow-style YAML file" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "flow.noext")
        # Flow-style YAML opens with "{" like JSON but does not parse as
        # JSON. Falling straight through to ELKT reads "id: root," and
        # "children: [" as layout options, so the graph comes back with no
        # children and no error at all.
        File.write(file, "{\n  id: root,\n  children: [\n    {id: n1, width: 30, height: 30}\n  ]\n}\n")

        stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
        expect(JSON.parse(stdout)["children"].map { |child| child["id"] }).to eq(["n1"])
      end
    end

    it "reads every declaration in a BOM-prefixed ELKT file" do
      bom_file = File.join(CliRunner::ROOT, "spec/fixtures/corpus/bom.elkt")

      stdout, _stderr, status = run_elkrb("layout", bom_file)

      expect(status.exitstatus).to eq(0)
      expect(JSON.parse(stdout)["children"].map { |child| child["id"] }).to eq(%w[a b])
    end

    it "accepts a JSON file whose only recognized field is properties" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "props.noext")
        File.write(file, '{"properties":{"note":"hello"}}')

        stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
        expect(JSON.parse(stdout)["properties"]).to eq({ "note" => "hello" })
      end
    end

    it "exits 1 for a top-level JSON sequence, not a NoMethodError" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "sequence.noext")
        # Parses without raising (Lutaml returns an Array for a top-level
        # JSON sequence), so this only fails via the type check, not the
        # InvalidFormatError rescue -- must not leak "undefined method
        # 'id' for an instance of Array" from hollow_model?.
        File.write(file, "[]")

        stdout, stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("")
        expect(stderr).to eq("Error: Unable to parse input file. Supported formats: JSON, YAML, ELKT\n")
      end
    end

    it "exits 1 for a top-level YAML sequence, not a NoMethodError" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "sequence.noext")
        File.write(file, "- id: g\n")

        stdout, stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("")
        expect(stderr).to eq("Error: Unable to parse input file. Supported formats: JSON, YAML, ELKT\n")
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
