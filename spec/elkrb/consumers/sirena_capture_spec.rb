# frozen_string_literal: true

require "spec_helper"
require "json"
require "support/sirena_provenance"

RSpec.describe "sirena consumer capture fixtures" do
  dir = "spec/fixtures/consumers/sirena"
  captured = %w[
    c4_nested class_flat er flowchart_lr flowchart_td sequence
    state user_journey
  ]
  spacings = {
    "elk.spacing.nodeNode" => 75.0,
    "elk.spacing.edgeNode" => 30,
    "elk.spacing.edgeEdge" => 30,
  }
  # Option maps sirena's own build_elk_options produces for algorithms it
  # does not emit yet. They are applied to flowchart_td.json here instead
  # of being committed as four near-identical copies of that file.
  synthetic_options = {
    "mrtree" => { "algorithm" => "mrtree",
                  "elk.direction" => "DOWN" },
    "sporeOverlap" => { "algorithm" => "sporeOverlap",
                        "elk.direction" => "DOWN" },
    "stress" => { "algorithm" => "stress",
                  "elk.direction" => "DOWN" }.merge(spacings),
    "force" => { "algorithm" => "force",
                 "elk.direction" => "DOWN" }.merge(spacings),
  }

  def fixture(dir, name)
    JSON.parse(File.read(File.join(dir, "#{name}.json")))
  end

  def option_maps(node, acc = [])
    acc << [node["id"], node["layoutOptions"]] if
      node.key?("layoutOptions")
    (node["children"] || []).each { |child| option_maps(child, acc) }
    acc
  end

  # Every node in the graph, root included, that carries a boundary_type.
  def boundary_types(node, acc = {})
    type = node.dig("metadata", "boundary_type")
    acc[node["id"]] = type unless type.nil?
    (node["children"] || []).each { |child| boundary_types(child, acc) }
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

  shared_examples "a graph elkrb echoes back" do
    # A graph's own algorithm key is recorded, not obeyed -- both the
    # canonical layoutOptions["elk.algorithm"] and the layoutOptions
    # ["algorithm"] alias. c4_nested.json carries both; the rest carry
    # only the alias. Neither is read.
    # LayoutEngine.layout selects from options[:algorithm] or
    # options["algorithm"] and otherwise defaults to "layered"; it never
    # reads graph.layoutOptions. So every case sharing these examples lays
    # out as layered, whatever algorithm its option map names -- including
    # the synthetic mrtree/sporeOverlap/stress/force maps below.
    #
    # layout_engine.rb's own YARD still documents a three-step order whose
    # step 2 reads graph.layoutOptions["elk.algorithm"]. The code does not do
    # that; the doc is the stale one, tracked as the open dispatch defect.
    # Trust this comment over that doc, and re-check both if either moves.
    let(:result) do
      Elkrb.layout(JSON.parse(JSON.generate(input), symbolize_names: true))
    end
    let(:output) { JSON.parse(result.to_json) }

    it "echoes every layoutOptions map it was given" do
      given = option_maps(input)

      expect(given).not_to be_empty
      expect(given.map(&:first)).to include(input["id"])
      # Compare the generated JSON, not the parsed values. Ruby's `==`
      # says 75.0 == 75, so an `eq` on the parsed maps cannot see a
      # Float turning into an Integer -- and elk.spacing.nodeNode is a
      # Float 75.0 beside two Integer 30s precisely so this pins the
      # numeric type. Keep the string form; `eq` here is silently weaker.
      expect(JSON.generate(option_maps(output)))
        .to eq(JSON.generate(given))
    end

    it "drops the unknown metadata key" do
      expect(key_anywhere?(input, "metadata")).to be(true)
      expect(key_anywhere?(output, "metadata")).to be(false)
    end
  end

  it "specs every committed fixture" do
    json = Dir[File.join(dir, "*.json")].map do |f|
      File.basename(f, ".json")
    end
    mmd = Dir[File.join(dir, "src", "*.mmd")].map do |f|
      File.basename(f, ".mmd")
    end

    expect(json.sort).to eq(captured.sort)
    expect(mmd.sort).to eq(captured.sort)
    expect(File).to exist(File.join(dir, "README.md"))
  end

  # Asserts each row is THERE and well-formed, not that it holds one
  # particular value. A copy of the sha here would have to be edited in
  # lockstep with the README on every legitimate re-capture, which is
  # the duplication `rake fixtures:sirena` exists to avoid -- and the
  # DATE said the same thing while being pinned to 2026-08-28 anyway, so
  # re-capturing today failed this example, measured. The format is what
  # the row promises; the value is the README's to own.
  it "records its provenance in the README" do
    readme_path = File.join(dir, "README.md")

    expect(SirenaProvenance.expected_sha(readme_path)).to match(/\A\h{40}\z/)
    expect(File.read(readme_path))
      .to match(/^\|\s*captured on\s*\|\s*\d{4}-\d{2}-\d{2}\s*\|/)
  end

  captured.each do |name|
    describe "#{name}.json" do
      let(:input) { fixture(dir, name) }

      it_behaves_like "a graph elkrb echoes back"
    end
  end

  synthetic_options.each do |algorithm, options|
    describe "flowchart_td.json with the #{algorithm} option map" do
      let(:input) do
        fixture(dir, "flowchart_td").merge("layoutOptions" => options)
      end

      it_behaves_like "a graph elkrb echoes back"
    end
  end

  describe "c4_nested.json structure" do
    let(:graph) { fixture(dir, "c4_nested") }
    let(:acme) { graph["children"].find { |c| c["id"] == "acme" } }
    let(:shop) { acme["children"].find { |c| c["id"] == "shop" } }
    let(:billing) { acme["children"].find { |c| c["id"] == "billing" } }

    it "nests acme under the root and shop and billing under acme" do
      expect(graph["children"].map { |c| c["id"] }).to eq(%w[acme customer])
      expect(acme["children"].map { |c| c["id"] }).to eq(%w[shop billing])
      expect(shop["children"].map { |c| c["id"] }).to eq(%w[webapp api])
      expect(billing["children"].map { |c| c["id"] }).to eq(%w[ledger billdb])
    end

    it "marks only acme, shop and billing as boundaries" do
      expect([acme, shop, billing]
        .map { |n| n["metadata"]["boundary_type"] })
        .to eq(%w[Enterprise_Boundary System_Boundary System_Boundary])
      # Walk the WHOLE graph, root included. Naming only the boundaries
      # and their children left `customer` -- the root's other child --
      # unexamined, so a boundary_type appearing there kept this example
      # green. "only" is a claim about every node, so every node is read.
      expect(boundary_types(graph))
        .to eq("acme" => "Enterprise_Boundary",
               "shop" => "System_Boundary",
               "billing" => "System_Boundary")
    end

    it "carries elk.algorithm box on all three boundaries" do
      expect([acme, shop, billing]
        .map { |n| n["layoutOptions"]["elk.algorithm"] })
        .to all(eq("box"))
    end

    it "routes rel_1 from api in shop to ledger in billing" do
      edges = graph["edges"].to_h do |edge|
        [edge["id"], edge["sources"] + edge["targets"]]
      end

      expect(edges).to eq(
        "rel_0" => %w[customer webapp],
        "rel_1" => %w[api ledger],
        "rel_2" => %w[ledger billdb],
      )
    end

    it "carries a layoutOptions map on the root and every boundary" do
      expect(option_maps(graph).map(&:first)).to eq(%w[c4 acme shop billing])
    end
  end
end
