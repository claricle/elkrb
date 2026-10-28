# frozen_string_literal: true

require "spec_helper"
require "support/cli_runner"
require "json"
require "tmpdir"
require "fileutils"

RSpec.describe "elkrb CLI layout flags" do
  include CliRunner

  let(:dir) { Dir.mktmpdir }
  let(:chain_path) do
    File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json")
  end
  let(:fan_out) do
    {
      id: "root",
      children: %w[a b c].map { |id| { id: id, width: 100, height: 60 } },
      edges: [{ id: "e1", sources: ["a"], targets: ["b"] },
              { id: "e2", sources: ["a"], targets: ["c"] }],
    }
  end
  let(:fan_out_path) { write_json_to(dir, "fan_out.json", fan_out) }
  let(:pinned_box_path) do
    pinned = fan_out.merge(layoutOptions: { "elk.algorithm" => "box" })
    write_json_to(dir, "pinned_box.json", pinned)
  end

  after { FileUtils.remove_entry(dir) }

  describe "layout --algorithm" do
    it "runs the algorithm the file pins when the flag is absent" do
      pinned, _err, status = run_elkrb_json("layout", pinned_box_path)
      explicit, = run_elkrb_json("layout", fan_out_path, "--algorithm", "box")
      layered, = run_elkrb_json("layout", fan_out_path)

      expect(status.exitstatus).to eq(0)
      expect(layout_coordinates(pinned)).to eq(layout_coordinates(explicit))
      expect(layout_coordinates(pinned)).not_to eq(layout_coordinates(layered))
    end

    it "lets an explicit flag beat the pin and echoes it in layoutOptions" do
      flagged, = run_elkrb_json("layout", pinned_box_path,
                                "--algorithm", "random")
      pinned, = run_elkrb_json("layout", pinned_box_path)

      expect(flagged["layoutOptions"]["elk.algorithm"]).to eq("random")
      expect(layout_coordinates(flagged)).not_to eq(layout_coordinates(pinned))
    end

    it "defaults to layered for a graph that pins nothing" do
      default, = run_elkrb_json("layout", fan_out_path)
      layered, = run_elkrb_json("layout", fan_out_path,
                                "--algorithm", "layered")

      expect(layout_coordinates(default)).to eq(layout_coordinates(layered))
    end

    it "fails with the algorithm's name for an unknown one" do
      _stdout, stderr, status = run_elkrb("layout", fan_out_path,
                                          "--algorithm", "nonexistent")

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("Unknown layout algorithm: nonexistent")
    end
  end

  describe "layout --layer-spacing" do
    it "changes the coordinates of a chain, which --spacing cannot" do
      default, = run_elkrb_json("layout", chain_path)
      layered, = run_elkrb_json("layout", chain_path, "--layer-spacing", "50")
      nodes, = run_elkrb_json("layout", chain_path, "--spacing", "50")

      expect(layout_coordinates(layered)).not_to eq(layout_coordinates(default))
      expect(layout_coordinates(nodes)).to eq(layout_coordinates(default))
    end
  end

  describe "layout --spacing" do
    it "changes coordinates on a fan-out graph and echoes the ELK id" do
      default, = run_elkrb_json("layout", fan_out_path)
      spaced, = run_elkrb_json("layout", fan_out_path, "--spacing", "50")

      expect(layout_coordinates(spaced)).not_to eq(layout_coordinates(default))
      expect(spaced["layoutOptions"]).to include("elk.spacing.nodeNode" => 50)
    end

    it "beats an alias the file already carries" do
      aliased = write_json_to(
        dir, "aliased.json",
        fan_out.merge(layoutOptions: { "spacing_node_node" => 200 })
      )
      flagged, = run_elkrb_json("layout", aliased, "--spacing", "50")
      plain, = run_elkrb_json("layout", fan_out_path, "--spacing", "50")

      expect(layout_coordinates(flagged)).to eq(layout_coordinates(plain))
    end
  end

  describe "layout padding flags" do
    it "fills the sides that were not given with 12" do
      layout, = run_elkrb_json("layout", fan_out_path, "--padding-top", "50")
      options = layout["layoutOptions"]

      expect(options["elk.padding"])
        .to eq("[top=50,left=12,bottom=12,right=12]")
      expect(layout["children"].map { |node| node["y"] }.min).to eq(50.0)
      expect(layout["children"].map { |node| node["x"] }.min).to eq(12.0)
    end

    {
      "--padding-top" => "[top=1,left=12,bottom=12,right=12]",
      "--padding-left" => "[top=12,left=1,bottom=12,right=12]",
      "--padding-bottom" => "[top=12,left=12,bottom=1,right=12]",
      "--padding-right" => "[top=12,left=12,bottom=12,right=1]",
    }.each do |flag, padding|
      it "puts #{flag} on its own side only" do
        layout, = run_elkrb_json("layout", fan_out_path, flag, "1")

        expect(layout["layoutOptions"]["elk.padding"]).to eq(padding)
      end
    end

    it "writes no padding option when no padding flag is given" do
      layout, = run_elkrb_json("layout", fan_out_path, "--spacing", "50")

      expect(layout["layoutOptions"]).not_to have_key("elk.padding")
    end
  end

  describe "layout --direction and --edge-routing" do
    it "echo in layoutOptions" do
      layout, = run_elkrb_json("layout", fan_out_path, "--direction", "RIGHT",
                               "--edge-routing", "POLYLINE")

      expect(layout["layoutOptions"]).to include(
        "elk.direction" => "RIGHT", "elk.edgeRouting" => "POLYLINE",
      )
    end

    it "applies DOWN and echoes its canonical key" do
      default, = run_elkrb_json("layout", chain_path)
      down, = run_elkrb_json("layout", chain_path, "--direction", "DOWN")

      expect(layout_coordinates(down)).not_to eq(layout_coordinates(default))
      expect(down["layoutOptions"]).to include("elk.direction" => "DOWN")
    end

    %w[layout diagram batch].each do |command|
      it "tells #{command} --help which algorithms apply --direction" do
        stdout, _err, status = run_elkrb("help", command)
        direction = stdout.split("\n").grep(/--direction/).first.to_s

        expect(status.exitstatus).to eq(0)
        expect(direction).to include("applied by layered and mrtree algorithms")
      end
    end
  end

  describe "diagram and batch" do
    let(:out) { File.join(dir, "out.json") }

    it "diagram writes its flags onto the root graph" do
      _stdout, _stderr, status = run_elkrb(
        "diagram", fan_out_path, "-o", out, "--algorithm", "box",
        "--spacing", "50", "--direction", "DOWN", "--edge-routing", "SPLINES"
      )

      expect(status.exitstatus).to eq(0)
      expect(JSON.parse(File.read(out))["layoutOptions"]).to include(
        "elk.algorithm" => "box", "elk.spacing.nodeNode" => 50,
        "elk.direction" => "DOWN", "elk.edgeRouting" => "SPLINES"
      )
    end

    it "diagram keeps the file's pin when --algorithm is absent" do
      explicit = File.join(dir, "explicit.json")
      run_elkrb("diagram", pinned_box_path, "-o", out)
      run_elkrb("diagram", fan_out_path, "-o", explicit,
                "--algorithm", "box")

      expect(layout_coordinates(JSON.parse(File.read(out))))
        .to eq(layout_coordinates(JSON.parse(File.read(explicit))))
    end

    it "batch applies --direction and --edge-routing to each file" do
      input = File.join(dir, "in")
      FileUtils.mkdir_p(input)
      FileUtils.cp(fan_out_path, input)
      out_dir = File.join(dir, "batch_out")
      _stdout, _stderr, status = run_elkrb(
        "batch", input, "--output-dir", out_dir, "--format", "json",
        "--direction", "RIGHT", "--edge-routing", "POLYLINE"
      )

      expect(status.exitstatus).to eq(0)
      written = JSON.parse(File.read(File.join(out_dir, "fan_out.json")))
      expect(written["layoutOptions"]).to include(
        "elk.direction" => "RIGHT", "elk.edgeRouting" => "POLYLINE",
      )
    end
  end

  describe "option warnings" do
    let(:warned_path) do
      options = { "elk.hierarchyHandling" => "INCLUDE_CHILDREN",
                  "elk.spacing.edgeNode" => 5,
                  "elk.edgeRouting" => "ORTHOGONAL",
                  "foo.bar" => 1 }
      write_json_to(dir, "warned.json", fan_out.merge(layoutOptions: options))
    end

    it "warns once for a partial key and once for an accepted key" do
      _stdout, stderr, status = run_elkrb("layout", warned_path)
      warnings = stderr.lines.grep(/WARN/)

      expect(status.exitstatus).to eq(0)
      expect(warnings.size).to eq(2)
      expect(warnings.grep(/elk\.hierarchyHandling is partially/).size)
        .to eq(1)
      expect(warnings.grep(/elk\.spacing\.edgeNode is accepted/).size)
        .to eq(1)
    end

    it "keeps stdout a single JSON document" do
      stdout, = run_elkrb("layout", warned_path)

      expect { JSON.parse(stdout) }.not_to raise_error
    end
  end
end
