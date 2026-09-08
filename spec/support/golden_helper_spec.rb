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

  it "threads an inherited direction into a nested compound's own check" do
    # The nested child "p" pins no elk.direction of its own -- it must
    # inherit DOWN from the root to group its own children by y. Each node
    # keeps a UNIQUE x (so an x-based grouping puts each one alone in its
    # own bucket, hiding any y-only difference instead of exposing it via
    # cross-axis tie-breaking within a shared bucket): dropping the
    # `inherited` argument on the recursive diff_layer_membership call
    # falls back to the RIGHT default, groups by x, and this real y-layer
    # reversal becomes invisible -- verified directly, see the commit this
    # comment shipped in.
    expected = { "id" => "root",
                 "layoutOptions" => { "elk.direction" => "DOWN" },
                 "children" => [
                   { "id" => "p", "children" => [
                     { "id" => "a", "x" => 0.0, "y" => 0.0 },
                     { "id" => "b", "x" => 50.0, "y" => 50.0 },
                     { "id" => "c", "x" => 100.0, "y" => 100.0 },
                   ] },
                 ] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["children"][0]["children"][0]["y"] = 100.0
    actual["children"][0]["children"][2]["y"] = 0.0

    diffs = described_class.diff_layer_membership(expected, actual)
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
    # Both nodes carry a MATCHING y, so the NaN x is the only thing that
    # can produce a difference. They used to carry x alone: the missing y
    # raised its own diff on each side, so stubbing the NaN check out left
    # this green. `not_to be_empty` could not tell the two apart, which is
    # why the message is named here rather than the emptiness.
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1", "x" => 10.0, "y" => 5.0 }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1", "x" => Float::NAN, "y" => 5.0 }] }

    diffs = described_class.diff_exact(expected, actual, %i[nodes])
    expect(diffs).to eq(["/children/n1/x: actual is non-finite (NaN)"])
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

  it "flags a section point that lands off the port's border" do
    # Same shapes as the border check above, but the start point sits at
    # the port's CENTRE (30+3=33) instead of its border (30+6=36) -- the
    # exact wrong-anchor mistake that check exists to catch.
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
      "startPoint" => { "x" => 33.0, "y" => 15.0 },
      "endPoint" => { "x" => 68.0, "y" => 15.0 },
      "incomingShape" => "p1",
      "outgoingShape" => "b",
    }]

    diffs = described_class.diff_structural(expected, actual)
    expect(diffs.join).to include("not on border of")
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
  # The examples below each pin one comparator rule that nothing exercised:
  # every one was measured to return no differences at all with the whole
  # suite still green, which is a comparator that has stopped comparing.

  # The mislabeled example this replaced called diff_own_numeric on a port's
  # x/y (a shape production code never uses for ports -- position goes
  # through diff_exact_position instead) and never touched diff_port_offset
  # at all. "flags a shifted port offset" above only proves a drift far
  # outside tolerance (0.0 -> 5.0) is rejected; neither example pinned the
  # 1e-6 tolerance BOUNDARY itself, which is the actual rule this method has.
  it "accepts a port offset drift within the 1e-6 tolerance" do
    diffs = described_class.diff_port_offset(
      { "offset" => 0.0 }, { "offset" => 5.0e-7 }, "root/a/ports/p"
    )

    expect(diffs).to be_empty
  end

  it "reports a port offset that drifted past the 1e-6 tolerance" do
    diffs = described_class.diff_port_offset(
      { "offset" => 0.0 }, { "offset" => 2.0e-6 }, "root/a/ports/p"
    )

    expect(diffs).to eq(["root/a/ports/p/offset: expected 0.0, got 2.0e-06"])
  end

  # Ids are unique within a level, so two items sharing one at the same level
  # means the sides cannot be matched up at all -- every id-based comparison
  # below this point is comparing an arbitrary one of the two.
  it "reports two items at one level sharing an id" do
    items = [{ "id" => "n1" }, { "id" => "n1" }, { "id" => "n2" }]

    diffs = described_class.duplicate_id_diffs(items, "root/children")

    expect(diffs).to eq(['root/children has 2 items with id "n1"'])
  end

  # Positional matching is only sound at equal counts. Without this the
  # shorter side is compared against the wrong items and the extras vanish.
  it "reports a differing count of id-less items" do
    diffs = described_class.diff_unnamed_items([{}, {}], [{}], "root/labels")

    expect(diffs).to eq(["root/labels: expected 2 id-less item(s), got 1"])
  end

  it "reports a bend point that moved" do
    expected = [{ "x" => 1.0, "y" => 1.0 }]
    actual = [{ "x" => 1.0, "y" => 40.0 }]

    diffs = described_class.diff_bend_points(expected, actual, "e1/bends")

    expect(diffs).not_to be_empty
  end

  it "reports a differing number of bend points" do
    diffs = described_class.diff_bend_points(
      [{ "x" => 1.0, "y" => 1.0 }], [], "e1/bends"
    )

    expect(diffs).to eq(["e1/bends: expected 1 bend points, got 0"])
  end

  # A dimension is compared to the pixel, not to 1e-6 like a position: elkjs
  # and elkrb round sizes differently, and a 1px band is the agreed
  # tolerance. Anything past it is a real disagreement.
  it "reports a size that differs by more than a pixel" do
    diffs = described_class.diff_strict_dimension(
      { "width" => 30.0 }, { "width" => 44.0 }, "root/a", "width"
    )

    expect(diffs).to eq(["root/a/width: expected 30.0, got 44.0 (>1px)"])
  end

  it "accepts a size that differs by less than a pixel" do
    diffs = described_class.diff_strict_dimension(
      { "width" => 30.0 }, { "width" => 30.5 }, "root/a", "width"
    )

    expect(diffs).to be_empty
  end

  # duplicate_id_diffs itself is a pure function with its own unit spec, but
  # every place structural comparison actually WIRES it in can be deleted
  # with the whole golden suite staying green -- these pin each call site,
  # not the helper.
  it "flags an ordinary graph size mismatch, not just a non-finite one" do
    expected = { "id" => "root", "width" => 100.0, "height" => 100.0 }
    actual = { "id" => "root", "width" => 130.0, "height" => 100.0 }

    diffs = described_class.diff_structural(expected, actual)

    expect(diffs).to include("graph/width: expected 100.0, got 130.0 (>1px)")
  end

  it "flags two children sharing an id" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "a", "x" => 0.0, "y" => 0.0 },
                                { "id" => "a", "x" => 0.0, "y" => 0.0 }] }
    actual = Marshal.load(Marshal.dump(expected))

    diffs = described_class.diff_structural(expected, actual)

    expect(diffs.join).to include("children: actual has 2 items with id")
  end

  it "flags two edges sharing an id" do
    graph = { "id" => "root",
              "children" => [{ "id" => "a", "x" => 0.0, "y" => 0.0 },
                             { "id" => "b", "x" => 0.0, "y" => 50.0 }],
              "edges" => [
                { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
                { "id" => "e1", "sources" => ["a"], "targets" => ["b"] },
              ] }

    diffs = described_class.diff_structural(graph, graph)

    expect(diffs.join).to include("edges: actual has 2 items with id")
  end

  it "flags a port id colliding with a node id in the combined namespace" do
    # The comparator merges node and port ids into one lookup because an
    # edge endpoint can name either -- so a port sharing its id with a
    # sibling node collapses the same way two nodes sharing an id would.
    graph = { "id" => "root",
              "children" => [
                { "id" => "a", "x" => 0.0, "y" => 0.0,
                  "ports" => [{ "id" => "b", "x" => 0.0, "y" => 0.0 }] },
                { "id" => "b", "x" => 0.0, "y" => 50.0 },
              ] }

    diffs = described_class.diff_structural(graph, graph)

    expect(diffs.join).to include("(nodes+ports): actual has 2 items with id")
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

  # The three below all annotate BOTH sides, so the golden's own shapes
  # are non-empty and the set comparison is what decides. The example
  # above annotates only the actual side, which exercises the membership
  # check instead -- different arm, and it used to be the only one tested.
  def annotate_first_section(graph, incoming, outgoing)
    copy = Marshal.load(Marshal.dump(graph))
    section = copy["edges"].find do |e|
      e["sources"] == ["a"] && e["targets"] == ["b"]
    end["sections"].first
    section["incomingShape"] = incoming
    section["outgoingShape"] = outgoing
    copy
  end

  def shape_diffs(expected, actual)
    described_class.diff_exact(expected, actual,
                               %i[nodes sections labels ports graph])
  end

  it "accepts a section whose shapes are reversed against the golden" do
    # Cycle breaking reverses a section's own annotations without
    # rewiring the edge, which is why edge_endpoint_ids unions sources
    # and targets. A key-by-key comparison reported this as two diffs.
    base = golden_expected("force_tri")

    expect(shape_diffs(annotate_first_section(base, "a", "b"),
                       annotate_first_section(base, "b", "a"))).to be_empty
  end

  it "rejects a section that names a different node in place of one" do
    # Both "a" and "a" ARE endpoints of this edge, so the membership
    # check cannot see this -- only the set comparison can.
    base = golden_expected("force_tri")
    diffs = shape_diffs(annotate_first_section(base, "a", "b"),
                        annotate_first_section(base, "a", "a"))

    expect(diffs.join).to include('expected shapes ["a", "b"], got ["a", "a"]')
  end

  it "rejects a section that dropped one of the golden's shapes" do
    base = golden_expected("force_tri")
    diffs = shape_diffs(annotate_first_section(base, "a", "b"),
                        annotate_first_section(base, "a", nil))

    expect(diffs.join).to include('expected shapes ["a", "b"], got ["a"]')
  end

  # Every other id in the harness is matched inside a children/edges
  # collection, and the root sits in neither -- renaming it produced no
  # difference in any of the three paths below.
  # "Near EITHER endpoint" is satisfied by a section that never leaves its
  # source, so an edge could be disconnected and still match.
  it "rejects a section whose end point has collapsed onto its start " \
     "(structural tier)" do
    expected = golden_expected("force_tri")
    collapsed = Marshal.load(Marshal.dump(expected))
    section = collapsed["edges"][0]["sections"][0]
    section["endPoint"] = section["startPoint"].dup

    expect(described_class.diff_structural(expected, collapsed).join)
      .to include("/end:")
  end

  # The annotation is what the border check MEASURES AGAINST, so trusting
  # the actual result's own annotation reopens the collapse above.
  # force_tri's golden carries no shapes at all, so `diff_section_shapes`
  # lets one appear, and "a" is a real endpoint of this edge.
  it "rejects a collapsed section that annotates its way back to the source " \
     "(structural tier)" do
    expected = golden_expected("force_tri")
    collapsed = Marshal.load(Marshal.dump(expected))
    section = collapsed["edges"][0]["sections"][0]
    section["endPoint"] = section["startPoint"].dup
    section["outgoingShape"] = collapsed["edges"][0]["sources"][0]

    expect(described_class.diff_structural(expected, collapsed).join)
      .to include("are not where the golden anchors this edge")
  end

  # The shapes are checked as a PAIR in either orientation, because
  # `diff_section_shapes` documents ELK reversing a section's own shapes
  # for cycle breaking without rewiring the edge. Checking each end
  # against the golden's own end rejected that legitimate reversal.
  it "accepts a section reversed end for end, points and shapes together " \
     "(structural tier)" do
    expected = {
      "id" => "root",
      "children" => [0, 30].zip(%w[a b]).map do |x, id|
        { "id" => id, "x" => x, "y" => 0, "width" => 10, "height" => 10 }
      end,
      "edges" => [{ "id" => "e", "sources" => ["a"], "targets" => ["b"],
                    "sections" => [{ "startPoint" => { "x" => 10, "y" => 5 },
                                     "endPoint" => { "x" => 30, "y" => 5 },
                                     "incomingShape" => "a",
                                     "outgoingShape" => "b" }] }],
    }
    reversed = Marshal.load(Marshal.dump(expected))
    section = reversed["edges"][0]["sections"][0]
    section["startPoint"], section["endPoint"] =
      section["endPoint"], section["startPoint"]
    section["incomingShape"], section["outgoingShape"] =
      section["outgoingShape"], section["incomingShape"]

    expect(described_class.diff_structural(expected, reversed)).to be_empty
  end

  # The counterweight: a reversal needs BOTH ends named. Allowing it with
  # one end unnamed let the collapse back in, because the unnamed end
  # matched whatever the other orientation wanted.
  it "rejects a collapsed section that annotates BOTH ends to the source " \
     "(structural tier)" do
    expected = golden_expected("force_tri")
    collapsed = Marshal.load(Marshal.dump(expected))
    edge = collapsed["edges"][0]
    section = edge["sections"][0]
    section["endPoint"] = section["startPoint"].dup
    section["incomingShape"] = edge["sources"][0]
    section["outgoingShape"] = edge["sources"][0]

    expect(described_class.diff_structural(expected, collapsed).join)
      .to include("are not where the golden anchors this edge")
  end

  # The counterweight: an annotation that agrees with the golden is still
  # accepted, so the guard above rejects a MISPLACED shape and not the
  # presence of one.
  it "still accepts a section annotated where the golden anchors it" do
    expected = golden_expected("force_tri")
    annotated = Marshal.load(Marshal.dump(expected))
    edge = annotated["edges"][0]
    edge["sections"].first["incomingShape"] = edge["sources"][0]
    edge["sections"].last["outgoingShape"] = edge["targets"][0]

    expect(described_class.diff_structural(expected, annotated)).to be_empty
  end

  # An explicit JSON `null` is PRESENT, so it is not the omission the
  # leniency above exists for. elkrb omits the key outright -- laying out
  # an unsized node gives a child whose keys are ["id", "x", "y"] -- so
  # nothing legitimate produces a null here.
  it "rejects an explicit null dimension in the structural tier" do
    expected = golden_expected("sizeless")
    nulled = Marshal.load(Marshal.dump(expected))
    nulled["children"].find { |n| n["id"] == "a" }["width"] = nil

    expect(described_class.diff_structural(expected, nulled).join)
      .to include("missing or not numeric")
  end

  # The counterweight to the example above, and the reason a plain
  # "start must differ from end" rule is wrong: radial_star5's four
  # committed goldens really are degenerate, so such a rule would reject
  # real elkjs output. Both must hold, or the fix is fitted to one case.
  it "still accepts radial_star5's legitimately degenerate sections" do
    expected = golden_expected("radial_star5")
    sections = expected["edges"].flat_map { |e| e["sections"] }

    expect(sections.map { |sec| sec["startPoint"] == sec["endPoint"] })
      .to all(be(true))
    expect(described_class.diff_structural(expected, expected)).to be_empty
  end

  # `spec/support/invariants/omit_size_for_unsized_input.rb` REQUIRES an
  # unsized input node to come back with no width/height, so a strict
  # "the key must be there" rule made the structural tier reject the very
  # output the rest of the suite demands -- and the exact tier, which
  # coerces an absent dimension to 0.0, accepted the same graph.
  it "accepts an unsized leaf whose zero dimensions are OMITTED " \
     "(structural tier)" do
    expected = golden_expected("sizeless")
    unsized = Marshal.load(Marshal.dump(expected))
    leaf = unsized["children"].find { |n| n["id"] == "a" }
    expect([leaf["width"], leaf["height"]]).to eq([0, 0])
    leaf.delete("width")
    leaf.delete("height")

    expect(described_class.diff_exact(expected, unsized, %i[nodes])).to be_empty
    expect(described_class.diff_structural(expected, unsized)).to be_empty
  end

  # Absence is forgiven; a present-but-broken value is not. Without this
  # the leniency above could have been written as "coerce anything",
  # which would swallow a NaN width as 0.0.
  it "still rejects a NaN width in the structural tier" do
    expected = golden_expected("sizeless")
    broken = Marshal.load(Marshal.dump(expected))
    broken["children"].find { |n| n["id"] == "a" }["width"] = Float::NAN

    expect(described_class.diff_structural(expected, broken).join)
      .to include("non-finite")
  end

  it "rejects a renamed root graph id in every tier" do
    expected = golden_expected("force_tri")
    renamed = Marshal.load(Marshal.dump(expected))
    renamed["id"] = "not-root"

    expect(shape_diffs(expected, renamed).join).to include("graph/id")
    expect(described_class.diff_structural(expected, renamed).join)
      .to include("graph/id")
    # The smoke tier was the one this example named and did not check.
    # It collected ids from `children` down, so the root's own id reached
    # neither list and a renamed root matched.
    expect(described_class.diff_smoke(expected, renamed).join)
      .to include("node ids differ")
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
