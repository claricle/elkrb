# spec/support/golden_helper_spec.rb
# frozen_string_literal: true

require "tmpdir"
require_relative "golden_cases"
require_relative "golden_helper"

RSpec.describe "match_elkjs_golden" do
  around do |example|
    Dir.mktmpdir do |dir|
      @golden_dir = dir
      FileUtils.mkdir_p(File.join(dir, "expected"))
      File.write(
        File.join(dir, "expected", "synthetic.json"),
        JSON.generate({ "id" => "root",
                        "children" => [{ "id" => "n1", "x" => 10.0,
                                         "y" => 0.0, "width" => 10.0,
                                         "height" => 10.0 }] }),
      )
      example.run
    end
  end

  let(:actual) do
    { "id" => "root",
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

RSpec.describe GoldenComparator do
  it "reaches a nested compound's inner edge with fields: [:sections] alone" do
    expected = {
      "id" => "root",
      "children" => [{ "id" => "p", "children" => [{ "id" => "c1" }],
                       "edges" => [{ "id" => "ie1", "sources" => ["c1"],
                                     "targets" => ["c1"],
                                     "sections" => [{ "id" => "s0",
                                                      "startPoint" => {
                                                        "x" => 1.0, "y" => 1.0
                                                      } }] }] }],
    }
    actual = Marshal.load(Marshal.dump(expected))
    actual["children"][0]["edges"][0]["sections"][0]["startPoint"]["x"] = 99.0

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs).not_to be_empty
  end

  it "does not require :labels to also select :sections to reach an edge " \
     "label" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1",
                               "labels" => [{ "id" => "l1", "x" => 0.0 }] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["labels"][0]["x"] = 5.0

    diffs = described_class.diff_exact(expected, actual, %i[labels])
    expect(diffs).not_to be_empty
  end

  it "does not compare port labels when :ports is selected without :labels" do
    # The port carries x/y because exact tier requires a real position on
    # both sides for anything below the root; the label's own x is what
    # this example is about.
    expected = { "id" => "root", "children" => [
      { "id" => "n1",
        "ports" => [{ "id" => "p1", "x" => 0.0, "y" => 0.0,
                      "labels" => [{ "id" => "l1", "x" => 0.0 }] }] },
    ] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["children"][0]["ports"][0]["labels"][0]["x"] = 5.0

    diffs = described_class.diff_exact(expected, actual, %i[ports])
    expect(diffs).to be_empty
  end

  it "flags a changed port side" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1",
                                  "ports" => [{ "id" => "p1",
                                                "side" => "EAST" }] }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1",
                                "ports" => [{ "id" => "p1",
                                              "side" => "WEST" }] }] }
    diffs = described_class.diff_exact(expected, actual, %i[ports])
    expect(diffs.join).to include("/side:")
  end

  it "flags a bumped port index" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1",
                                  "ports" => [{ "id" => "p1",
                                                "index" => 0 }] }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1",
                                "ports" => [{ "id" => "p1", "index" => 1 }] }] }
    diffs = described_class.diff_exact(expected, actual, %i[ports])
    expect(diffs.join).to include("/index:")
  end

  it "flags a shifted port offset" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1",
                                  "ports" => [{ "id" => "p1",
                                                "offset" => 0.0 }] }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1",
                                "ports" => [{ "id" => "p1",
                                              "offset" => 5.0 }] }] }
    diffs = described_class.diff_exact(expected, actual, %i[ports])
    expect(diffs.join).to include("/offset:")
  end

  it "flags a changed port geometry (x/y/width/height)" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1",
                                  "ports" => [{ "id" => "p1", "x" => 0.0,
                                                "width" => 6.0 }] }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1",
                                "ports" => [{ "id" => "p1", "x" => 3.0,
                                              "width" => 6.0 }] }] }
    diffs = described_class.diff_exact(expected, actual, %i[ports])
    expect(diffs.join).to include("/x:")
  end

  it "flags a reversed edge even though sections/labels/ports still match " \
     "(exact tier)" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1" }, { "id" => "n2" }],
                 "edges" => [{ "id" => "e1", "sources" => ["n1"],
                               "targets" => ["n2"] }] }
    reversed = Marshal.load(Marshal.dump(expected))
    reversed["edges"][0]["sources"] = ["n2"]
    reversed["edges"][0]["targets"] = ["n1"]

    diffs = described_class.diff_exact(expected, reversed,
                                       %i[nodes sections labels ports graph])
    expect(diffs.join).to include("endpoints changed")
  end

  it "detects a same-layer top/bottom swap that alphabetical id order would " \
     "miss" do
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
      { "id" => "p", "children" => [{ "id" => "x", "x" => 0.0 },
                                    { "id" => "y", "x" => 50.0 }] },
    ] }
    actual = { "id" => "root", "children" => [
      { "id" => "p", "children" => [{ "id" => "x", "x" => 0.0 },
                                    { "id" => "y", "x" => 0.0 }] },
    ] }

    diffs = described_class.diff_layer_membership(expected, actual)
    expect(diffs).not_to be_empty
  end

  it "flags a missing node position at smoke tier" do
    expected = { "id" => "root", "children" => [{ "id" => "n1" }] }
    # no x/y at all
    actual = { "id" => "root", "children" => [{ "id" => "n1" }] }

    diffs = described_class.diff_smoke(expected, actual)
    expect(diffs).not_to be_empty
  end

  it "does not require the root's own position at any tier" do
    node = { "id" => "n1", "x" => 0.0, "y" => 0.0, "width" => 10.0,
             "height" => 10.0 }
    expected = { "id" => "root", "children" => [node] }
    actual = { "id" => "root", "children" => [node] } # no root x/y

    expect(described_class.diff_smoke(expected, actual)).to be_empty
    expect(described_class.diff_structural(expected, actual)).to be_empty
    expect(described_class.diff_exact(expected, actual, %i[graph])).to be_empty
  end

  it "flags a NaN actual value instead of silently treating it as a match " \
     "(exact tier)" do
    expected = { "id" => "root", "children" => [{ "id" => "n1", "x" => 10.0 }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1", "x" => Float::NAN }] }

    diffs = described_class.diff_exact(expected, actual, %i[nodes])
    expect(diffs).not_to be_empty
  end

  it "flags a NaN root dimension instead of silently treating it as a match " \
     "(structural tier)" do
    expected = { "id" => "root", "width" => 100.0, "height" => 100.0 }
    actual = { "id" => "root", "width" => Float::NAN, "height" => 100.0 }

    diffs = described_class.diff_graph_size(expected, actual)
    expect(diffs).not_to be_empty
  end

  it "still flags a missing child position when the container box is " \
     "zero-width" do
    e_node = { "id" => "n1", "x" => 5.0, "y" => 0.0, "width" => 10.0,
               "height" => 10.0 }
    # no x at all
    a_node = { "id" => "n1", "y" => 0.0, "width" => 10.0, "height" => 10.0 }

    diffs = described_class.diff_normalised_position(
      { node: e_node, width: 0.0, height: 100.0 },
      { node: a_node, width: 0.0, height: 100.0 },
      "/n1",
    )
    expect(diffs.join).to include("missing")
  end

  it "reports an unexpected extra actual node symmetrically (exact tier)" do
    expected = { "id" => "root", "children" => [{ "id" => "n1" }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1" }, { "id" => "n2" }] }

    diffs = described_class.diff_exact(expected, actual, %i[nodes])
    expect(diffs.join).to include("unexpected in actual")
  end

  it "reports an unexpected extra actual edge symmetrically (structural " \
     "tier)" do
    node = { "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 10.0,
             "height" => 10.0 }
    expected = { "id" => "root", "children" => [node], "edges" => [] }
    actual = { "id" => "root", "children" => [node],
               "edges" => [{ "id" => "e1",
                             "sections" => [{
                               "startPoint" => { "x" => 5.0, "y" => 5.0 },
                               "endPoint" => { "x" => 5.0, "y" => 5.0 },
                             }] }] }

    diffs = described_class.diff_structural(expected, actual)
    expect(diffs.join).to include("unexpected in actual")
  end

  it "reports a node missing from actual symmetrically (structural tier)" do
    kept = { "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 10.0,
             "height" => 10.0 }
    dropped = { "id" => "b", "x" => 20.0, "y" => 0.0, "width" => 10.0,
                "height" => 10.0 }
    expected = { "id" => "root", "width" => 30.0, "height" => 10.0,
                 "children" => [kept, dropped] }
    actual = { "id" => "root", "width" => 30.0, "height" => 10.0,
               "children" => [kept] }

    diffs = described_class.diff_structural(expected, actual)
    expect(diffs.join).to include("missing from actual")
  end

  it "reports a structurally rewired edge (structural tier)" do
    a = { "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 10.0,
          "height" => 10.0 }
    b = { "id" => "b", "x" => 20.0, "y" => 0.0, "width" => 10.0,
          "height" => 10.0 }
    expected = { "id" => "root", "children" => [a, b],
                 "edges" => [{ "id" => "e1", "sources" => ["a"],
                               "targets" => ["b"],
                               "sections" => [{
                                 "startPoint" => { "x" => 10.0, "y" => 5.0 },
                                 "endPoint" => { "x" => 20.0, "y" => 5.0 },
                                 "incomingShape" => "a",
                                 "outgoingShape" => "b",
                               }] }] }
    rewired = Marshal.load(Marshal.dump(expected))
    rewired["edges"][0]["sources"] = ["b"]
    rewired["edges"][0]["targets"] = ["a"]

    diffs = described_class.diff_structural(expected, rewired)
    expect(diffs.join).to include("endpoints changed")
  end

  it "compares a port endpoint to its own border, like a node, not a centre " \
     "point" do
    # Confirmed against the real committed `ports_simple` golden: elkjs
    # anchors the edge at the port's right BORDER (node.x + port.x +
    # port.width = 12+30+6 = 48), not its centre (12+30+3 = 45).
    node = { "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 30.0,
             "height" => 30.0,
             "ports" => [{ "id" => "p1", "x" => 30.0, "y" => 12.0,
                           "width" => 6.0, "height" => 6.0 }] }
    other = { "id" => "b", "x" => 68.0, "y" => 0.0, "width" => 30.0,
              "height" => 30.0 }
    expected = { "id" => "root", "children" => [node, other],
                 "edges" => [{ "id" => "e1", "sources" => ["p1"],
                               "targets" => ["b"] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["sections"] = [{
      "id" => "s0",
      "startPoint" => { "x" => 36.0, "y" => 15.0 },
      "endPoint" => { "x" => 68.0, "y" => 15.0 },
      "incomingShape" => "p1",
      "outgoingShape" => "b",
    }]

    diffs = described_class.diff_structural(expected, actual)
    expect(diffs).to be_empty
  end

  it "does not miss a layered-graph check when elk.algorithm is the " \
     "fully-qualified id" do
    options = { "elk.algorithm" => "org.eclipse.elk.layered" }
    expected = { "id" => "root", "layoutOptions" => options,
                 "children" => [{ "id" => "a", "x" => 0.0, "y" => 0.0 },
                                { "id" => "b", "x" => 0.0, "y" => 50.0 }] }
    collapsed = { "id" => "root", "layoutOptions" => options,
                  "children" => [{ "id" => "a", "x" => 0.0, "y" => 50.0 },
                                 { "id" => "b", "x" => 0.0, "y" => 0.0 }] }

    diffs = described_class.diff_layer_membership(expected, collapsed)
    expect(diffs).not_to be_empty
  end
end

RSpec.describe "every committed golden self-matches at its assigned tier" do
  # Driven by the same shared table golden_spec.rb generates its examples
  # from, so a case can never have an example there and no self-match here
  # (`hyperedge` is the sole error-case golden and is excluded from that
  # table — its "match" is a different code path in the matcher, exercised
  # in golden_spec.rb directly). A golden that fails this only means the
  # COMPARATOR disagrees with reality, not that elkrb is wrong about
  # anything — this caught a real bug once already (structural tier's
  # port-anchor check rejected `ports_simple`'s own real elkjs data before
  # that check was fixed to use the port's border instead of its centre).
  GoldenCases::TIER_BY_CASE.each do |name, tier|
    it "#{name} (#{tier})" do
      expected = golden_expected(name)
      diffs =
        case tier
        when :exact then GoldenComparator.diff_exact(expected, expected,
                                                     %i[nodes sections labels
                                                        ports graph])
        when :structural then GoldenComparator.diff_structural(expected,
                                                               expected)
        end

      expect(diffs).to be_empty
    end
  end
end

RSpec.describe "every committed golden's perturbed copy is caught" do
  # The self-match examples above prove the comparator accepts a CORRECT
  # copy; they are tautological about whether it can also REJECT a wrong
  # one (comparing an object with itself proves nothing about that). One
  # mutation per case, chosen to exercise the property most relevant to
  # its tier: exact tier gets a node shifted past the 1e-6 tolerance;
  # structural tier gets an edge deleted if the case has one (exercises
  # the symmetric "missing from actual" check), otherwise a node shifted
  # past `POSITION_TOLERANCE_FRACTION` of the graph's own size (exercises
  # `diff_node_geometry` on an edge-less case like `rect6`/
  # `spore_overlap4`).
  GoldenCases::TIER_BY_CASE.each do |name, tier|
    it "#{name} (#{tier})" do
      expected = golden_expected(name)
      mutated = Marshal.load(Marshal.dump(expected))

      case tier
      when :exact
        mutated["children"].first["x"] =
          numeric_or_zero(mutated["children"].first, "x") + 2.0
        diffs = GoldenComparator.diff_exact(expected, mutated,
                                            %i[nodes sections labels
                                               ports graph])
      when :structural
        if mutated["edges"]&.any?
          mutated["edges"].shift
        else
          node = mutated["children"].first
          node["x"] =
            numeric_or_zero(node,
                            "x") + (numeric_or_zero(mutated, "width") * 0.5)
        end
        diffs = GoldenComparator.diff_structural(expected, mutated)
      end

      expect(diffs).not_to be_empty
    end
  end

  def numeric_or_zero(hash, key)
    (hash[key] || 0.0).to_f
  end
end

RSpec.describe GoldenComparator, "rejecting a corrupted actual result" do
  # Every example here takes a REAL committed golden, corrupts the copy
  # standing in for elkrb's output in one specific way, and asserts the
  # comparator now reports it. Each corruption is one the comparator used
  # to accept.

  it "rejects a section shape naming a node that is not the edge's endpoint " \
     "(structural tier)" do
    # force_tri is a case elkjs leaves with NO incomingShape/outgoingShape,
    # so there is nothing on the golden side to compare against. The `a ->
    # b` edge below claims both its ends belong to unrelated node `c` and
    # routes to c's border, which used to satisfy every structural check.
    expected = golden_expected("force_tri")
    corrupted = Marshal.load(Marshal.dump(expected))
    edge = corrupted["edges"].find do |e|
      e["sources"] == ["a"] && e["targets"] == ["b"]
    end
    c = corrupted["children"].find { |n| n["id"] == "c" }
    edge["sections"].first["incomingShape"] = "c"
    edge["sections"].last["outgoingShape"] = "c"
    edge["sections"].first["startPoint"] = { "x" => c["x"], "y" => c["y"] }
    edge["sections"].last["endPoint"] = { "x" => c["x"], "y" => c["y"] }

    diffs = described_class.diff_structural(expected, corrupted)
    expect(diffs.join).to include("is not an endpoint of this edge")
  end

  it "rejects the same rerouted shape at exact tier" do
    expected = golden_expected("force_tri")
    corrupted = Marshal.load(Marshal.dump(expected))
    edge = corrupted["edges"].find do |e|
      e["sources"] == ["a"] && e["targets"] == ["b"]
    end
    edge["sections"].first["incomingShape"] = "c"

    diffs = described_class.diff_exact(expected, corrupted,
                                       %i[nodes sections labels ports graph])
    expect(diffs.join).to include("is not an endpoint of this edge")
  end

  it "accepts a section shape that names the edge's own endpoint" do
    expected = golden_expected("force_tri")
    annotated = Marshal.load(Marshal.dump(expected))
    edge = annotated["edges"].find do |e|
      e["sources"] == ["a"] && e["targets"] == ["b"]
    end
    edge["sections"].first["incomingShape"] = "a"
    edge["sections"].last["outgoingShape"] = "b"

    expect(described_class.diff_exact(expected, annotated,
                                      %i[nodes sections labels
                                         ports graph])).to be_empty
  end

  it "rejects a label that lost its coordinates entirely (exact tier)" do
    # labeled_node's label really does sit at (0,0) in the golden, so
    # coercing a missing coordinate to 0.0 made deleting it a no-op.
    expected = golden_expected("labeled_node")
    corrupted = Marshal.load(Marshal.dump(expected))
    label = corrupted["children"].find { |n| n["id"] == "a" }["labels"].first
    label.delete("x")
    label.delete("y")

    diffs = described_class.diff_exact(expected, corrupted,
                                       %i[nodes sections labels ports graph])
    expect(diffs.join).to include("actual is missing or not numeric")
  end

  # Synthetic rather than a committed golden: elkjs pads every case, so
  # no golden node actually sits at x=0 today. A node that DOES belong at
  # the origin is where the old coercion hid an unplaced node completely,
  # and a later slice adding an unpadded case would have hit it.
  it "rejects a node that has no position where the golden puts it at the " \
     "origin" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1", "x" => 0.0, "y" => 0.0 }] }
    corrupted = { "id" => "root", "children" => [{ "id" => "n1" }] }

    diffs = described_class.diff_exact(expected, corrupted, %i[nodes])
    expect(diffs.join).to include("actual is missing or not numeric")
  end

  it "still treats a missing width as zero, the elkjs quirk the rule exists " \
     "for" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1", "x" => 0.0, "y" => 0.0,
                                  "width" => 0, "height" => 0 }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1", "x" => 0.0, "y" => 0.0 }] }

    expect(described_class.diff_exact(expected, actual, %i[nodes])).to be_empty
  end
end

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
end
