# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "sirena consumer capture fixtures" do
  dir = "spec/fixtures/consumers/sirena"
  captured = %w[
    c4_nested class_flat er flowchart_lr flowchart_td sequence
    state user_journey
  ]
  synthetic = %w[
    synthetic_force synthetic_mrtree synthetic_sporeOverlap
    synthetic_stress
  ]
  sirena_sha = "c3820364551b3f107b6177bba8d1e2c0c6d3940b"
  spacings = {
    "elk.spacing.nodeNode" => 75.0,
    "elk.spacing.edgeNode" => 30,
    "elk.spacing.edgeEdge" => 30,
  }
  option_maps_for = {
    "synthetic_mrtree" => { "algorithm" => "mrtree",
                            "elk.direction" => "DOWN" },
    "synthetic_sporeOverlap" => { "algorithm" => "sporeOverlap",
                                  "elk.direction" => "DOWN" },
    "synthetic_stress" => { "algorithm" => "stress",
                            "elk.direction" => "DOWN" }.merge(spacings),
    "synthetic_force" => { "algorithm" => "force",
                           "elk.direction" => "DOWN" }.merge(spacings),
  }

  def option_maps(node, acc = [])
    acc << [node["id"], node["layoutOptions"]] if
      node.key?("layoutOptions")
    (node["children"] || []).each { |child| option_maps(child, acc) }
    acc
  end

  def key_anywhere?(value, key)
    case value
    when Hash
      value.key?(key) ||
        value.each_value.any? { |v| key_anywhere?(v, key) }
    when Array then value.any? { |v| key_anywhere?(v, key) }
    else false
    end
  end

  it "specs every committed fixture" do
    json = Dir[File.join(dir, "*.json")].map do |f|
      File.basename(f, ".json")
    end
    mmd = Dir[File.join(dir, "src", "*.mmd")].map do |f|
      File.basename(f, ".mmd")
    end

    expect(json.sort).to eq((captured + synthetic).sort)
    expect(mmd.sort).to eq(captured.sort)
    expect(File).to exist(File.join(dir, "README.md"))
  end

  it "records its provenance in the README" do
    readme = File.read(File.join(dir, "README.md"))

    expect(readme).to include(sirena_sha)
    expect(readme).to include("2026-08-28")
  end

  (captured + synthetic).each do |name|
    describe "#{name}.json" do
      let(:path) { File.join(dir, "#{name}.json") }
      let(:input) { JSON.parse(File.read(path)) }
      let(:result) do
        Elkrb.layout(JSON.parse(File.read(path), symbolize_names: true))
      end
      let(:output) { JSON.parse(result.to_json) }

      # Synthetic fixtures intentionally keep their sirena algorithm value as
      # metadata; LayoutEngine#layout dispatches from options[:algorithm] and
      # graph.layoutOptions["elk.algorithm"], not from this field.
      it "lays out without raising" do
        expect { result }.not_to raise_error
      end

      it "echoes every layoutOptions map it was given" do
        given = option_maps(input)

        expect(given).not_to be_empty
        expect(given.map(&:first)).to include(input["id"])
        expect(JSON.generate(option_maps(output)))
          .to eq(JSON.generate(given))
      end

      it "drops the unknown metadata key" do
        expect(key_anywhere?(input, "metadata")).to be(true)
        expect(key_anywhere?(output, "metadata")).to be(false)
      end
    end
  end

  synthetic.each do |name|
    describe "#{name}.json construction" do
      let(:document) do
        JSON.parse(File.read(File.join(dir, "#{name}.json")))
      end
      let(:base) do
        JSON.parse(File.read(File.join(dir, "flowchart_td.json")))
      end

      it "differs from flowchart_td.json only in layoutOptions" do
        body = document.except("layoutOptions")
        want = base.except("layoutOptions")

        expect(JSON.generate(body)).to eq(JSON.generate(want))
      end

      it "carries the exact sirena-generated option map" do
        expect(JSON.generate(document["layoutOptions"]))
          .to eq(JSON.generate(option_maps_for.fetch(name)))
      end
    end
  end

  describe "c4_nested.json structure" do
    let(:graph) do
      JSON.parse(File.read(File.join(dir, "c4_nested.json")))
    end

    def boundary_depth_of(node)
      nested = (node["children"] || []).select do |child|
        child.key?("layoutOptions")
      end
      return 0 if nested.empty?

      1 + nested.map { |child| boundary_depth_of(child) }.max
    end

    def boundaries(node, acc = [])
      (node["children"] || []).each do |child|
        acc << child if child.key?("layoutOptions")
        boundaries(child, acc)
      end
      acc
    end

    def owners(node, current, acc = {})
      (node["children"] || []).each do |child|
        acc[child["id"]] = current
        inner = child.key?("layoutOptions") ? child["id"] : current
        owners(child, inner, acc)
      end
      acc
    end

    it "nests boundaries two levels deep" do
      expect(boundary_depth_of(graph)).to eq(2)
    end

    it "carries elk.algorithm box on all three boundaries" do
      found = boundaries(graph)

      expect(found.map { |b| b["id"] }.sort).to eq(%w[acme billing shop])
      expect(found.map { |b| b["layoutOptions"]["elk.algorithm"] })
        .to all(eq("box"))
    end

    it "routes an edge between members of two sibling boundaries" do
      owner = owners(graph, nil)
      crossing = graph["edges"].select do |edge|
        from = owner[edge["sources"].first]
        to = owner[edge["targets"].first]
        from && to && from != to
      end

      expect(crossing.map { |e| e["id"] }).to eq(["rel_1"])
      edge = crossing.first
      expect(edge["sources"] + edge["targets"]).to eq(%w[api ledger])
      expect(boundaries(graph).map { |b| b["id"] })
        .not_to include("api", "ledger")
      expect([owner["api"], owner["ledger"]]).to eq(%w[shop billing])
      expect(owner.values_at("shop", "billing").uniq).to eq(["acme"])
    end

    it "carries a layoutOptions map on the root and every boundary" do
      expect(option_maps(graph).map(&:first).sort)
        .to eq(%w[acme billing c4 shop])
    end

    it "nests shop and billing inside acme" do
      acme = graph["children"].find { |c| c["id"] == "acme" }

      expect(acme).not_to be_nil
      expect(acme["children"].map { |c| c["id"] })
        .to include("shop", "billing")
    end
  end
end
