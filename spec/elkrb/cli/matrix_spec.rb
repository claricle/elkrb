# frozen_string_literal: true

require "spec_helper"
require "support/cli_runner"
require "support/cli_matrix"
require "support/fake_dot"
require "json"
require "yaml"
require "tmpdir"
require "fileutils"

RSpec.describe "elkrb CLI command matrix" do
  include CliRunner
  include FakeDot

  layout_flag = /--(?:algorithm|direction|edge-routing|spacing|
                    layer-spacing|padding-\w+)/x

  let(:dir) { Dir.mktmpdir }
  let(:graph) { File.join(dir, "graph.json") }
  let(:dot) { File.join(CliRunner::ROOT, "spec/fixtures/render_input.dot") }
  let(:argv) { CliMatrix.argv(graph: graph, dot: dot, dir: dir) }

  before do
    FileUtils.cp(File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json"),
                 graph)
  end

  after { FileUtils.remove_entry(dir) }

  # Result on stdout, nothing on stderr. `diagram`, `convert`, `validate`
  # and `batch` confirm on stdout; `layout`, `algorithms` and `options`
  # print their result there.
  ok_stdout = {
    "layout" => /"children"/,
    "diagram" => /Diagram created/,
    "convert" => /Converted/,
    "render" => nil,
    "validate" => /is valid/,
    "batch" => /Processed 1 file/,
    "version" => /elkrb version/,
    "algorithms" => /Available Layout Algorithms/,
    "options" => /^id\s+type\s+default\s+status\s+aliases$/,
  }

  ok_stdout.each do |command, pattern|
    it "#{command}: ok exits 0 with the result on stdout and nothing on stderr",
       skip: Gem.win_platform? && command == "render" do
      run = lambda do
        run_elkrb(*argv.fetch(command).fetch(:ok))
      end
      stdout, stderr, status =
        command == "render" ? with_fake_dot { run.call } : run.call

      expect(status.exitstatus).to eq(0), stderr
      expect(stderr).to eq("")
      expect(stdout).to match(pattern) if pattern
    end
  end

  describe "errors" do
    # A usage error and a failed command differ in who prints the first line
    # (Thor or elkrb) but not in the contract: nothing on stdout, the reason
    # and a "Try:" line on stderr, exit 1.
    {
      missing_file: /Error: .*absent/,
      unknown_algorithm: /Unknown layout algorithm: nosuch/,
      bad_flag: /Unknown switches "--bogus"/,
    }.each do |kind, message|
      CliMatrix.argv(graph: "g", dot: "d", dir: "x").each_key do |command|
        cell = CliMatrix.argv(graph: "g", dot: "d", dir: "x")
          .fetch(command).fetch(kind)
        next if cell.nil? || (command == "batch" && kind == :unknown_algorithm)

        it "#{command}: #{kind} exits 1 with the reason and a hint on stderr" do
          stdout, stderr, status = run_elkrb(*argv.fetch(command).fetch(kind))

          expect(status.exitstatus).to eq(1)
          expect(stdout).to eq("")
          expect(stderr).to match(message)
          expect(stderr.lines.last).to match(/\ATry: elkrb (help|algorithms)/)
        end
      end
    end

    # batch reports a per-file failure and then a count, so the algorithm
    # name appears in the per-file line, not the last one.
    it "batch: unknown algorithm exits 1 with the reason and a hint" do
      _stdout, stderr, status = run_elkrb(
        *argv.fetch("batch").fetch(:unknown_algorithm),
      )

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("Unknown layout algorithm: nosuch")
      expect(stderr.lines.last).to match(/\ATry: elkrb help batch/)
    end

    it "points an unknown algorithm at `elkrb algorithms`" do
      _stdout, stderr, = run_elkrb("layout", graph, "--algorithm", "nosuch")

      expect(stderr.lines.last.chomp).to eq("Try: elkrb algorithms")
    end

    it "points a bad flag at the help of the command it was given to" do
      _stdout, stderr, = run_elkrb("layout", graph, "--bogus")

      expect(stderr.lines.last.chomp).to eq("Try: elkrb help layout")
    end

    it "points an unknown command at the general help" do
      stdout, stderr, status = run_elkrb("nosuchcommand")

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq("")
      expect(stderr.lines.last.chomp).to eq("Try: elkrb help")
    end

    it "points a missing argument at the help of that command" do
      _stdout, stderr, status = run_elkrb("layout")

      expect(status.exitstatus).to eq(1)
      expect(stderr.lines.last.chomp).to eq("Try: elkrb help layout")
    end
  end

  describe "options --json" do
    let(:document) { run_elkrb_json("options", "--json").first }

    it "lists every registry option with the documented keys" do
      expect(document.keys).to eq(["options"])
      expect(document["options"].size).to eq(Elkrb::Options::Registry.all.size)
      document["options"].each do |entry|
        expect(entry.keys.sort).to eq(
          %w[algorithms aliases default id status type],
        )
      end
    end

    it "reports each option's status from the registry" do
      statuses = document["options"].to_h { |e| [e["id"], e["status"]] }

      expect(statuses).to eq(
        Elkrb::Options::Registry.all.transform_values { |e| e[:status].to_s },
      )
    end

    it "names the registered algorithms that support an option" do
      direction = document["options"].find { |e| e["id"] == "elk.direction" }

      expect(direction["algorithms"]).to eq(%w[layered mrtree])
    end

    it "narrows to the ids one algorithm supports" do
      narrowed, = run_elkrb_json("options", "layered", "--json")

      expect(narrowed["options"].map { |e| e["id"] })
        .to eq(Elkrb::Options::Registry.for_algorithm("layered"))
    end

    it "prints only JSON on stdout" do
      stdout, stderr, = run_elkrb("options", "--json")

      expect(stdout).to start_with('{"options":[')
      expect(stderr).to eq("")
    end
  end

  describe "options text" do
    it "lists one row per option, narrowed by algorithm" do
      stdout, = run_elkrb("options", "box")
      ids = stdout.lines.drop(1).map { |line| line.split.first }

      expect(ids).to eq(Elkrb::Options::Registry.for_algorithm("box"))
    end
  end

  describe "algorithms --json" do
    it "lists every registered algorithm with its supported options" do
      document, = run_elkrb_json("algorithms", "--json")
      algorithms = document.fetch("algorithms")

      expect(algorithms.map { |a| a["id"] })
        .to eq(Elkrb::Layout::AlgorithmRegistry.available_algorithms)
      algorithms.each do |entry|
        expect(entry.keys).to eq(
          %w[id name description category supports_hierarchy
             supported_options],
        )
        expect(entry["supported_options"]).to eq(
          Elkrb::Options::Registry.for_algorithm(entry["id"]),
        )
      end
    end
  end

  describe "layout --output format" do
    let(:expected) { JSON.parse(run_elkrb("layout", graph).first) }

    it "writes YAML to a .yml path" do
      path = File.join(dir, "result.yml")
      _stdout, stderr, status = run_elkrb("layout", graph, "--output", path)

      expect(status.exitstatus).to eq(0), stderr
      written = YAML.safe_load_file(path)
      expect(written.fetch("children").map { |n| n["id"] })
        .to eq(expected.fetch("children").map { |n| n["id"] })
    end

    it "writes YAML to a .YAML path, whatever the case" do
      path = File.join(dir, "result.YAML")
      run_elkrb("layout", graph, "--output", path)

      expect(File.read(path)).to start_with("---\n")
    end

    it "lets --format json win over the .yml extension" do
      path = File.join(dir, "result.yml")
      run_elkrb("layout", graph, "--output", path, "--format", "json")

      expect(JSON.parse(File.read(path))).to eq(expected)
    end

    it "lets --format yaml win over the .json extension" do
      path = File.join(dir, "result.json")
      run_elkrb("layout", graph, "--output", path, "--format", "yaml")

      expect(File.read(path)).to start_with("---\n")
    end

    it "writes JSON to any other extension" do
      path = File.join(dir, "result.txt")
      run_elkrb("layout", graph, "--output", path)

      expect(JSON.parse(File.read(path))).to eq(expected)
    end
  end

  describe "help text" do
    %w[layout diagram batch].each do |command|
      it "#{command}: shows the registry's values for --direction and " \
         "--edge-routing" do
        stdout, = run_elkrb("help", command)

        flag_ids = %w[elk.direction elk.edgeRouting]
        flag_ids.each do |id|
          values = Elkrb::Options::Registry.all.fetch(id).fetch(:values)
          expect(stdout).to include(values.join(", "))
        end
      end
    end

    it "gives layout, diagram and batch the same layout flags" do
      flags = %w[layout diagram batch].map do |command|
        run_elkrb("help", command).first.scan(layout_flag).sort
      end

      expect(flags.uniq.size).to eq(1)
      expect(flags.first.size).to eq(9)
    end
  end
end
