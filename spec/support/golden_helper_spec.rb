# spec/support/golden_helper_spec.rb
# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "golden_cases"
require_relative "golden_helper"

RSpec.describe "match_elkjs_golden" do
  around do |example|
    Dir.mktmpdir do |dir|
      @golden_dir = dir
      FileUtils.mkdir_p(File.join(dir, "expected"))
      File.write(
        File.join(dir, "expected", "synthetic.json"),
        JSON.generate({ "id" => "root", "width" => 100.0, "height" => 100.0,
                        "children" => [{ "id" => "n1", "x" => 10.0,
                                         "y" => 0.0, "width" => 10.0,
                                         "height" => 10.0 }] }),
      )
      example.run
    end
  end

  # Both roots carry the SAME 100x100 size on purpose. Structural tier
  # normalises a node's position against its container's own span and
  # skips the check entirely when that span is zero, so a sizeless root
  # would make the structural example below green without the tolerance
  # code ever running. At 100px the 0.5px delta is 0.005 of the span,
  # comfortably inside POSITION_TOLERANCE_FRACTION, so the example still
  # passes -- now for the reason it names.
  let(:actual) do
    { "id" => "root", "width" => 100.0, "height" => 100.0,
      "children" => [{ "id" => "n1", "x" => 10.5, "y" => 0.0, "width" => 10.0,
                       "height" => 10.0 }] }
  end

  it "fails at exact tier on a 0.5px delta" do
    matcher = match_elkjs_golden("synthetic", tier: :exact, dir: @golden_dir)
    expect(matcher.matches?(actual)).to be false
  end

  it "passes at structural tier despite the same delta" do
    matcher = match_elkjs_golden("synthetic", tier: :structural,
                                              dir: @golden_dir)
    expect(matcher.matches?(actual)).to be true
  end

  # `fields:` on the matcher must actually reach `GoldenComparator.
  # diff_exact` -- excluding `:nodes` here means the 0.5px delta on `n1`
  # (the only difference between `actual` and the committed golden) is
  # never even checked, so a case that genuinely narrows its own fields
  # must pass where the unrestricted default (the example above) fails.
  it "honours a narrowed fields: at exact tier" do
    matcher = match_elkjs_golden("synthetic", tier: :exact,
                                              fields: %i[graph],
                                              dir: @golden_dir)
    expect(matcher.matches?(actual)).to be true
  end

  # `GoldenComparator.diff_structural` honours `fields` now, mirroring
  # exact tier: a root SIZE deviation is a `:graph`-tier fact
  # (`diff_graph_size`), independent of `:nodes` (`diff_node_geometry`) --
  # narrowing to `fields: %i[nodes]` must miss a root size deviation it
  # deliberately excludes, and `fields: %i[graph]` alone must still catch
  # that same deviation.
  it "honours a narrowed fields: at structural tier" do
    File.write(
      File.join(@golden_dir, "expected", "structural_fields.json"),
      JSON.generate({ "id" => "root", "width" => 100.0, "height" => 100.0,
                      "children" => [{ "id" => "n1", "x" => 0.0, "y" => 0.0,
                                       "width" => 10.0, "height" => 10.0 }] }),
    )
    oversized_root = { "id" => "root", "width" => 110.0, "height" => 100.0,
                       "children" => [{ "id" => "n1", "x" => 0.0, "y" => 0.0,
                                        "width" => 10.0, "height" => 10.0 }] }

    narrowed_to_nodes = match_elkjs_golden("structural_fields",
                                           tier: :structural,
                                           fields: %i[nodes],
                                           dir: @golden_dir)
    expect(narrowed_to_nodes.matches?(oversized_root)).to be true

    narrowed_to_graph = match_elkjs_golden("structural_fields",
                                           tier: :structural,
                                           fields: %i[graph],
                                           dir: @golden_dir)
    expect(narrowed_to_graph.matches?(oversized_root)).to be false
  end
end

RSpec.describe "GoldenHelper#matcher_kwargs" do
  include GoldenHelper

  it "omits fields: when the case table entry does not set one" do
    expect(matcher_kwargs(name: "x", tier: :exact)).to eq(tier: :exact)
  end

  it "forwards fields: when the case table entry sets one" do
    kase = { name: "x", tier: :structural, fields: %i[nodes graph] }
    expect(matcher_kwargs(kase)).to eq(tier: :structural,
                                       fields: %i[nodes graph])
  end
end

RSpec.describe "match_elkjs_golden error matching" do
  around do |example|
    Dir.mktmpdir do |dir|
      @golden_dir = dir
      FileUtils.mkdir_p(File.join(dir, "expected"))
      message = "IllegalArgumentException: Passed edge is not 'simple'."
      File.write(
        File.join(dir, "expected", "synthetic_error.json"),
        JSON.generate({ "error" => message }),
      )
      example.run
    end
  end

  # `tier:` is required by the matcher but unused on this path -- both
  # sides being error hashes routes straight to `error_diffs`.
  it "matches an actual error naming the same condition" do
    actual = {
      "error" => "Elkrb::UnsupportedConfigurationException: edge is not SIMPLE",
    }
    matcher = match_elkjs_golden("synthetic_error", tier: :exact,
                                                    dir: @golden_dir)
    expect(matcher.matches?(actual)).to be true
  end

  it "rejects an actual error naming a DIFFERENT condition" do
    actual = {
      "error" => "Elkrb::UnsupportedConfigurationException: unrelated failure",
    }
    matcher = match_elkjs_golden("synthetic_error", tier: :exact,
                                                    dir: @golden_dir)
    expect(matcher.matches?(actual)).to be false
  end
end
