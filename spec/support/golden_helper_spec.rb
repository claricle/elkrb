# spec/support/golden_helper_spec.rb
# frozen_string_literal: true

require "tmpdir"
require_relative "golden_helper"

RSpec.describe "match_elkjs_golden" do
  around do |example|
    Dir.mktmpdir do |dir|
      @golden_dir = dir
      FileUtils.mkdir_p(File.join(dir, "expected"))
      File.write(
        File.join(dir, "expected", "synthetic.json"),
        JSON.generate({ "id" => "root",
                         "children" => [{ "id" => "n1", "x" => 10.0, "y" => 0.0 }] }),
      )
      example.run
    end
  end

  let(:actual) do
    { "id" => "root", "children" => [{ "id" => "n1", "x" => 10.5, "y" => 0.0 }] }
  end

  it "fails at exact tier on a 0.5px delta" do
    matcher = match_elkjs_golden("synthetic", tier: :exact, dir: @golden_dir)
    expect(matcher.matches?(actual)).to be false
  end

  it "passes at structural tier despite the same delta" do
    matcher = match_elkjs_golden("synthetic", tier: :structural, dir: @golden_dir)
    expect(matcher.matches?(actual)).to be true
  end
end

RSpec.describe GoldenComparator do
  it "reaches a nested compound's inner edge with fields: [:sections] alone" do
    expected = {
      "id" => "root",
      "children" => [{ "id" => "p", "children" => [{ "id" => "c1" }],
                        "edges" => [{ "id" => "ie1", "sources" => ["c1"], "targets" => ["c1"],
                                      "sections" => [{ "id" => "s0",
                                                        "startPoint" => { "x" => 1.0, "y" => 1.0 } }] }] }],
    }
    actual = Marshal.load(Marshal.dump(expected))
    actual["children"][0]["edges"][0]["sections"][0]["startPoint"]["x"] = 99.0

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs).not_to be_empty
  end

  it "does not require :labels to also select :sections to reach an edge label" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1", "labels" => [{ "id" => "l1", "x" => 0.0 }] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["labels"][0]["x"] = 5.0

    diffs = described_class.diff_exact(expected, actual, %i[labels])
    expect(diffs).not_to be_empty
  end

  it "does not compare port labels when :ports is selected without :labels" do
    expected = { "id" => "root", "children" => [
      { "id" => "n1", "ports" => [{ "id" => "p1", "labels" => [{ "id" => "l1", "x" => 0.0 }] }] },
    ] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["children"][0]["ports"][0]["labels"][0]["x"] = 5.0

    diffs = described_class.diff_exact(expected, actual, %i[ports])
    expect(diffs).to be_empty
  end

  it "detects a same-layer top/bottom swap that alphabetical id order would miss" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "a", "x" => 0.0, "y" => 0.0 },
                                { "id" => "b", "x" => 0.0, "y" => 50.0 }] }
    swapped = { "id" => "root",
                "children" => [{ "id" => "a", "x" => 0.0, "y" => 50.0 },
                               { "id" => "b", "x" => 0.0, "y" => 0.0 }] }

    diffs = described_class.diff_layer_membership(expected, swapped)
    expect(diffs).not_to be_empty
  end

  it "recurses layer-membership checks into a matched compound child" do
    expected = { "id" => "root", "children" => [
      { "id" => "p", "children" => [{ "id" => "x", "x" => 0.0 }, { "id" => "y", "x" => 50.0 }] },
    ] }
    actual = { "id" => "root", "children" => [
      { "id" => "p", "children" => [{ "id" => "x", "x" => 0.0 }, { "id" => "y", "x" => 0.0 }] },
    ] }

    diffs = described_class.diff_layer_membership(expected, actual)
    expect(diffs).not_to be_empty
  end

  it "flags a missing node position at smoke tier" do
    expected = { "id" => "root", "children" => [{ "id" => "n1" }] }
    actual = { "id" => "root", "children" => [{ "id" => "n1" }] } # no x/y at all

    diffs = described_class.diff_smoke(expected, actual)
    expect(diffs).not_to be_empty
  end

  it "does not require the root's own position at any tier" do
    expected = { "id" => "root", "children" => [{ "id" => "n1", "x" => 0.0, "y" => 0.0 }] }
    actual = { "id" => "root", "children" => [{ "id" => "n1", "x" => 0.0, "y" => 0.0 }] } # no root x/y

    expect(described_class.diff_smoke(expected, actual)).to be_empty
    expect(described_class.diff_structural(expected, actual)).to be_empty
    expect(described_class.diff_exact(expected, actual, %i[graph])).to be_empty
  end

  it "flags a NaN actual value instead of silently treating it as a match (exact tier)" do
    expected = { "id" => "root", "children" => [{ "id" => "n1", "x" => 10.0 }] }
    actual = { "id" => "root", "children" => [{ "id" => "n1", "x" => Float::NAN }] }

    diffs = described_class.diff_exact(expected, actual, %i[nodes])
    expect(diffs).not_to be_empty
  end

  it "flags a NaN root dimension instead of silently treating it as a match (structural tier)" do
    expected = { "id" => "root", "width" => 100.0, "height" => 100.0 }
    actual = { "id" => "root", "width" => Float::NAN, "height" => 100.0 }

    diffs = described_class.diff_graph_size(expected, actual)
    expect(diffs).not_to be_empty
  end

  it "reports an unexpected extra actual node symmetrically (exact tier)" do
    expected = { "id" => "root", "children" => [{ "id" => "n1" }] }
    actual = { "id" => "root", "children" => [{ "id" => "n1" }, { "id" => "n2" }] }

    diffs = described_class.diff_exact(expected, actual, %i[nodes])
    expect(diffs.join).to include("unexpected in actual")
  end

  it "reports an unexpected extra actual edge symmetrically (structural tier)" do
    node = { "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 10.0, "height" => 10.0 }
    expected = { "id" => "root", "children" => [node], "edges" => [] }
    actual = { "id" => "root", "children" => [node],
               "edges" => [{ "id" => "e1",
                              "sections" => [{ "startPoint" => { "x" => 5.0, "y" => 5.0 },
                                               "endPoint" => { "x" => 5.0, "y" => 5.0 } }] }] }

    diffs = described_class.diff_structural(expected, actual)
    expect(diffs.join).to include("unexpected in actual")
  end

  it "compares a port endpoint to its own border, like a node, not a centre point" do
    # Confirmed against the real committed `ports_simple` golden: elkjs
    # anchors the edge at the port's right BORDER (node.x + port.x +
    # port.width = 12+30+6 = 48), not its centre (12+30+3 = 45).
    node = { "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 30.0, "height" => 30.0,
             "ports" => [{ "id" => "p1", "x" => 30.0, "y" => 12.0, "width" => 6.0, "height" => 6.0 }] }
    other = { "id" => "b", "x" => 68.0, "y" => 0.0, "width" => 30.0, "height" => 30.0 }
    expected = { "id" => "root", "children" => [node, other],
                 "edges" => [{ "id" => "e1", "sources" => ["p1"], "targets" => ["b"] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["sections"] = [{ "id" => "s0",
                                         "startPoint" => { "x" => 36.0, "y" => 15.0 },
                                         "endPoint" => { "x" => 68.0, "y" => 15.0 },
                                         "incomingShape" => "p1", "outgoingShape" => "b" }]

    diffs = described_class.diff_structural(expected, actual)
    expect(diffs).to be_empty
  end

  it "does not miss a layered-graph check when elk.algorithm is the fully-qualified id" do
    expected = { "id" => "root", "layoutOptions" => { "elk.algorithm" => "org.eclipse.elk.layered" },
                 "children" => [{ "id" => "a", "x" => 0.0, "y" => 0.0 }, { "id" => "b", "x" => 0.0, "y" => 50.0 }] }
    collapsed = { "id" => "root", "layoutOptions" => { "elk.algorithm" => "org.eclipse.elk.layered" },
                  "children" => [{ "id" => "a", "x" => 0.0, "y" => 50.0 }, { "id" => "b", "x" => 0.0, "y" => 0.0 }] }

    diffs = described_class.diff_layer_membership(expected, collapsed)
    expect(diffs).not_to be_empty
  end
end

RSpec.describe "every committed golden self-matches at its assigned tier" do
  # Kept in sync with golden_spec.rb's own per-case tier (`hyperedge` is
  # the sole error-case golden, excluded here — its "match" is a
  # different code path in the matcher, exercised in golden_spec.rb
  # directly). A golden that fails this only means the COMPARATOR
  # disagrees with reality, not that elkrb is wrong about anything — this
  # caught a real bug once already (structural tier's port-anchor check
  # rejected `ports_simple`'s own real elkjs data before that check was
  # fixed to use the port's border instead of its centre).
  TIER_BY_CASE = {
    "chain2" => :exact, "chain3" => :exact, "fan_out" => :structural, "fan_in" => :structural,
    "diamond" => :structural, "cycle3" => :structural, "self_loop" => :structural,
    "long_edge" => :structural, "ports_simple" => :structural, "labeled_node" => :exact,
    "labeled_node_placement" => :exact, "compound_chain" => :exact, "compound_nested" => :structural,
    "direction_down" => :exact, "spacing_override" => :exact, "sizeless" => :exact,
    "two_components" => :structural, "box3" => :exact, "box_mixed" => :exact, "box_aspect" => :exact,
    "fixed2" => :exact, "mrtree3" => :exact, "mrtree7" => :structural, "radial_star5" => :structural,
    "rect6" => :structural, "force_tri" => :structural, "stress_path4" => :structural,
    "random3" => :structural, "spore_overlap4" => :structural,
  }.freeze

  TIER_BY_CASE.each do |name, tier|
    it "#{name} (#{tier})" do
      expected = golden_expected(name)
      diffs =
        case tier
        when :exact then GoldenComparator.diff_exact(expected, expected, %i[nodes sections labels ports graph])
        when :structural then GoldenComparator.diff_structural(expected, expected)
        end

      expect(diffs).to be_empty
    end
  end
end
