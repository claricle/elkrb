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
