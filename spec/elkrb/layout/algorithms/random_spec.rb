# frozen_string_literal: true

require "spec_helper"

RSpec.describe "seeded random layouts" do
  let(:graph_json) do
    {
      id: "r",
      children: (0...5).map do |i|
        { id: "n#{i}", width: 30, height: 30 }
      end,
      edges: [],
    }.to_json
  end

  it "lays out the same random graph identically twice" do
    expect do
      Elkrb.layout(JSON.parse(graph_json), algorithm: "random")
    end.to be_deterministic
  end

  it "changes a random layout when the graph seed changes" do
    default = Elkrb.layout(JSON.parse(graph_json), algorithm: "random")
    seeded = JSON.parse(graph_json)
    seeded["layoutOptions"] = { "elk.randomSeed" => 2 }

    expect(Elkrb.layout(seeded, algorithm: "random")).not_to eq(default)
  end

  it "pads by 15 and anchors an edge's ends on its source, as Java ELK does" do
    graph = {
      "id" => "r", "layoutOptions" => { "elk.randomSeed" => 42 },
      "children" => [{ "id" => "a", "width" => 30, "height" => 30 },
                     { "id" => "b", "width" => 30, "height" => 30 }],
      "edges" => [{ "id" => "e", "sources" => ["a"], "targets" => ["b"] }]
    }
    laid_out = Elkrb.layout(graph, algorithm: "random")
    a = laid_out.children.first
    section = laid_out.edges.first.sections.first

    expect([a.x >= 15, a.y >= 15,
            section.start_point.x, section.start_point.y,
            section.end_point.x, section.end_point.y])
      .to eq([true, true, a.x + 30, a.y + 15, a.x + 15, a.y + 30])
  end

  it "makes force deterministic" do
    expect do
      Elkrb.layout(JSON.parse(graph_json), algorithm: "force")
    end.to be_deterministic
  end

  it "makes stress deterministic" do
    stress = JSON.parse(graph_json)
    stress["edges"] = (1...5).map do |i|
      { "id" => "e#{i}", "sources" => ["n#{i - 1}"],
        "targets" => ["n#{i}"] }
    end

    expect do
      Elkrb.layout(Marshal.load(Marshal.dump(stress)), algorithm: "stress")
    end.to be_deterministic
  end

  it "keeps layout algorithms off the process-wide random stream" do
    root = File.expand_path("../../../../lib/elkrb/layout/algorithms", __dir__)
    violations = Dir.glob("**/*.rb", base: root).sort.flat_map do |relative|
      lines = File.readlines(File.join(root, relative))
      lines.each_with_index.filter_map do |line, index|
        next unless line.gsub("rng.rand", "").match?(/\brand\b/)

        "#{relative}:#{index + 1}:#{line.strip}"
      end
    end

    expect(violations).to eq([])
  end
end
