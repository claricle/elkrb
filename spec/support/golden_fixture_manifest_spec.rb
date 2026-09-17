# spec/support/golden_fixture_manifest_spec.rb
# frozen_string_literal: true

# Split out of golden_helper_spec.rb (see golden_comparator_pinning_spec.rb
# for the split rationale). Checks the committed golden fixture SET is
# internally consistent (inputs/expected/MANIFEST.json/case table all
# agree) -- distinct from spec/support/golden_fixtures_spec.rb, which
# tests the Rakefile's regeneration/publish machinery.
require_relative "golden_helper"

RSpec.describe "the committed golden fixture set" do
  # `rake golden:check` catches drift between the inputs and what elkjs
  # produces for them, but it needs Node and a network install, which
  # golden.yml deliberately does not have. This is the half of that guard
  # that needs neither: adding an input without regenerating its expected
  # file, without updating MANIFEST.json, or without adding a golden_spec
  # example used to leave the suite green.
  golden_dir = GoldenHelper::DEFAULT_DIR
  inputs = Dir[File.join(golden_dir, "inputs", "*.json")].map do |f|
    File.basename(f, ".json")
  end.sort

  it "has at least the 30 cases the harness was built for" do
    expect(inputs.size).to be >= 30
  end

  it "has an expected file for every input, and no orphan expected file" do
    expected = Dir[File.join(golden_dir, "expected", "*.json")].map do |f|
      File.basename(f, ".json")
    end.sort

    expect(expected).to eq(inputs)
  end

  it "lists exactly those cases in MANIFEST.json" do
    manifest = JSON.parse(File.read(File.join(golden_dir, "MANIFEST.json")))

    expect(manifest.fetch("cases").sort).to eq(inputs)
  end

  it "has a golden_spec.rb example for every case" do
    # golden_spec.rb generates one example per name in this table, so
    # asserting the table covers the inputs asserts the examples do.
    expect(GoldenCases::ALL_NAMES.sort).to eq(inputs)
  end
  describe "which rejection happened" do
    let(:elkjs) do
      "java.lang.IllegalArgumentException: Passed edge is not 'simple'."
    end

    # Deriving the condition from elkjs's wording asks only whether a term
    # APPEARS. Both of these were measured against that version: the first
    # passed though it says the opposite, the second failed though it is the
    # settled correct message from card 12.
    # Drives the CASE TABLE's own pattern, not a literal written here. An
    # earlier version of this example passed a hand-written /hyperedge/i and
    # so proved nothing about what the harness actually uses -- and that
    # pattern named only the SUBJECT, so "hyperedge accepted" satisfied it.
    it "rejects a message that names the subject but states the opposite" do
      expect(
        GoldenComparator.same_error_condition?(
          elkjs, "hyperedge accepted; endpoint lookup failed",
          expected: GoldenCases.expected_error_for("hyperedge")
        ),
      ).to be(false)
    end

    it "accepts elkrb's own wording for the same condition" do
      expect(
        GoldenComparator.same_error_condition?(
          elkjs, "layered does not support hyperedges (edge e1)",
          expected: GoldenCases.expected_error_for("hyperedge")
        ),
      ).to be(true)
    end

    it "still falls back to the quoted term when a case states nothing" do
      expect(
        GoldenComparator.same_error_condition?(elkjs, "edge is not simple"),
      ).to be(true)
    end
  end
  describe "direction inheritance" do
    let(:child) { { "id" => "g", "children" => [] } }

    # ELK applies a root's direction to every nested level that does not pin
    # its own, and real elkjs output for a DOWN root omits a local direction
    # on the child. Reading only the level's own options defaulted such a
    # child to RIGHT and grouped it on x, so two collapsed y-layers with a
    # rerouted section compared equal.
    it "groups a child on the parent's axis when it pins none of its own" do
      expect(GoldenComparator.layer_axes(child).first).to eq(:x)
      expect(GoldenComparator.layer_axes(child, "DOWN").first).to eq(:y)
    end

    it "lets a child override the inherited direction" do
      pinned = child.merge("layoutOptions" => { "elk.direction" => "RIGHT" })

      expect(GoldenComparator.layer_axes(pinned, "DOWN").first).to eq(:x)
    end
  end
end
