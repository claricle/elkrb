# spec/support/golden_comparator_pinning_spec.rb
# frozen_string_literal: true

# Split out of golden_helper_spec.rb (module-boundary split, matching
# 4bef14b's precedent for the source file) once that file crossed 1000
# lines. Unit-level pins on GoldenComparator using hand-built hashes --
# distinct from golden_comparator_corruption_spec.rb, which corrupts real
# committed goldens.
require_relative "golden_comparator"

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

  # `diff_edge_endpoints` (sources/targets rewiring, section shape
  # annotations) used to run unconditionally inside `diff_edges`, so a
  # caller selecting `fields: %i[labels]` alone -- to check label content,
  # nothing else -- still got a rewiring diff it never asked for. It is
  # gated behind `:sections` now, the same selector `diff_sections`/
  # `diff_edge_routing` already answer to.
  it "does not report a rewired edge's endpoints when only :labels is " \
     "selected" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1", "sources" => ["a"],
                               "targets" => ["b"],
                               "labels" => [{ "id" => "l1", "x" => 0.0,
                                              "y" => 0.0 }] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["sources"] = ["c"]

    diffs = described_class.diff_exact(expected, actual, %i[labels])
    expect(diffs).to be_empty
  end

  it "still reports a rewired edge's endpoints when :sections is selected" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1", "sources" => ["a"],
                               "targets" => ["b"] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["sources"] = ["c"]

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs.join).to include("endpoints changed")
  end

  # `section_index_by_id` maps a section id to its array position for
  # `incomingSections`/`outgoingSections` resolution; a plain `to_h` from
  # an Array silently keeps only the LAST section with a repeated id, so a
  # genuinely duplicated section id resolved every ref naming an earlier
  # occurrence to the wrong position instead of being reported as the
  # duplicate it is -- the same failure mode `duplicate_id_diffs` already
  # guards everywhere else this comparator indexes an Array by id.
  it "flags a duplicate section id instead of silently resolving refs to " \
     "the wrong position" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1",
                               "sections" => [
                                 { "id" => "dup",
                                   "startPoint" => { "x" => 0.0, "y" => 0.0 } },
                                 { "id" => "dup",
                                   "startPoint" => { "x" => 5.0, "y" => 0.0 } },
                               ] }] }
    actual = Marshal.load(Marshal.dump(expected))

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs.join).to include('has 2 items with id "dup"')
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

  # diff_labels used to check only geometry, so a layout regression that
  # corrupted label CONTENT while leaving position/size untouched passed
  # the exact tier silently -- measured, changing only "text" returned no
  # differences before this pin existed.
  it "flags a label whose text differs even though its geometry matches" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "a",
                                  "labels" => [{ "id" => "l1", "text" => "hi",
                                                 "x" => 0.0, "y" => 0.0 }] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["children"][0]["labels"][0]["text"] = "bye"

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

  # elkjs may omit `index` on a port entirely; elkrb's port constraint
  # processor always assigns one starting at 0, so a missing `index` and
  # an explicit `0` must be treated as equal (the same missing-as-zero
  # convention `diff_port_offset`, below, already uses) rather than
  # flagged as a diff.
  it "does not flag a port missing index against an explicit index of 0" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1",
                                  "ports" => [{ "id" => "p1", "x" => 0.0,
                                                "y" => 0.0 }] }] }
    actual = { "id" => "root",
               "children" => [{ "id" => "n1",
                                "ports" => [{ "id" => "p1", "x" => 0.0,
                                              "y" => 0.0, "index" => 0 }] }] }
    diffs = described_class.diff_exact(expected, actual, %i[ports])
    expect(diffs).to be_empty
  end

  it "flags a port missing index against an explicit index of 1" do
    expected = { "id" => "root",
                 "children" => [{ "id" => "n1",
                                  "ports" => [{ "id" => "p1" }] }] }
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

  it "flags a changed junctionPoints on an edge" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1",
                               "junctionPoints" => [{ "x" => 1.0,
                                                      "y" => 1.0 }] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["junctionPoints"][0]["x"] = 9.0

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs.join).to include("/junctionPoints")
  end

  it "flags a changed container on an edge" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1", "container" => "n1" }] }
    actual = { "id" => "root", "children" => [],
               "edges" => [{ "id" => "e1", "container" => "n2" }] }

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs.join).to include("/container:")
  end

  it "flags a changed incomingSections on a multi-section edge" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1",
                               "sections" => [
                                 { "id" => "e1_s0",
                                   "outgoingSections" => ["e1_s1"] },
                                 { "id" => "e1_s1",
                                   "incomingSections" => ["e1_s0"] },
                               ] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["sections"][1]["incomingSections"] = ["e1_s2"]

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs.join).to include("/incomingSections:")
  end

  # The example above changes only `incomingSections` -- removing the
  # separate `outgoingSections` comparison in `diff_section_routing_refs`
  # would leave it green. Mirrors it exactly but on the OTHER field.
  it "flags a changed outgoingSections on a multi-section edge" do
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1",
                               "sections" => [
                                 { "id" => "e1_s0",
                                   "outgoingSections" => ["e1_s1"] },
                                 { "id" => "e1_s1",
                                   "incomingSections" => ["e1_s0"] },
                               ] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["sections"][0]["outgoingSections"] = ["e1_s2"]

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs.join).to include("/outgoingSections:")
  end

  # elkjs and elkrb mint different id strings for the same positionally
  # matched section ("e_s0" vs "e_section_0") -- `diff_section_refs` used
  # to compare `incomingSections`/`outgoingSections` as raw id strings, so
  # a topologically identical two-section edge under the two naming
  # schemes was flagged as changed even though position 0 feeds position 1
  # on both sides. Refs are translated to their own side's POSITION before
  # comparing, so this must report nothing.
  it "does not flag equivalent incoming/outgoingSections that merely use " \
     "different id schemes" do
    point = { "x" => 0.0, "y" => 0.0 }
    expected = { "id" => "root", "children" => [],
                 "edges" => [{ "id" => "e1",
                               "sections" => [
                                 { "id" => "e_s0", "startPoint" => point,
                                   "endPoint" => point,
                                   "outgoingSections" => ["e_s1"] },
                                 { "id" => "e_s1", "startPoint" => point,
                                   "endPoint" => point,
                                   "incomingSections" => ["e_s0"] },
                               ] }] }
    actual = { "id" => "root", "children" => [],
               "edges" => [{ "id" => "e1",
                             "sections" => [
                               { "id" => "e_section_0", "startPoint" => point,
                                 "endPoint" => point,
                                 "outgoingSections" => ["e_section_1"] },
                               { "id" => "e_section_1", "startPoint" => point,
                                 "endPoint" => point,
                                 "incomingSections" => ["e_section_0"] },
                             ] }] }

    diffs = described_class.diff_exact(expected, actual, %i[sections])
    expect(diffs).to eq([])
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

  # check_edge_ends only anchors the FIRST section's start and the LAST
  # section's end to a node border -- the internal joint between two
  # sections is never otherwise checked, so a mid-edge disconnect with
  # both outer anchors intact used to pass silently. Both outer anchors
  # here stay exactly where they were (10,5 on a's border, 20,5 on b's
  # border); only the internal joint (section 0's endPoint vs section 1's
  # startPoint) is moved apart.
  it "flags a multi-section edge whose internal joint does not connect" do
    a = { "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 10.0,
          "height" => 10.0 }
    b = { "id" => "b", "x" => 20.0, "y" => 0.0, "width" => 10.0,
          "height" => 10.0 }
    expected = { "id" => "root", "children" => [a, b],
                 "edges" => [{ "id" => "e1", "sources" => ["a"],
                               "targets" => ["b"],
                               "sections" => [
                                 { "startPoint" => { "x" => 10.0, "y" => 5.0 },
                                   "endPoint" => { "x" => 15.0, "y" => 5.0 },
                                   "incomingShape" => "a" },
                                 { "startPoint" => { "x" => 15.0, "y" => 5.0 },
                                   "endPoint" => { "x" => 20.0, "y" => 5.0 },
                                   "outgoingShape" => "b" },
                               ] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["sections"][1]["startPoint"] =
      { "x" => 30.0, "y" => 5.0 }

    diffs = described_class.diff_structural(expected, actual)
    expect(diffs.join).to include("sections[0->1]")
  end

  # The example above separates only x -- y stays 5.0 on both sides of
  # the mutation, so it says nothing about whether `diff_joint_axis`'s y
  # check does anything at all. Mirrors it exactly but moves y instead,
  # leaving x untouched.
  it "flags a multi-section edge whose internal joint separates only " \
     "on the y axis" do
    a = { "id" => "a", "x" => 0.0, "y" => 0.0, "width" => 10.0,
          "height" => 10.0 }
    b = { "id" => "b", "x" => 20.0, "y" => 0.0, "width" => 10.0,
          "height" => 10.0 }
    expected = { "id" => "root", "children" => [a, b],
                 "edges" => [{ "id" => "e1", "sources" => ["a"],
                               "targets" => ["b"],
                               "sections" => [
                                 { "startPoint" => { "x" => 10.0, "y" => 5.0 },
                                   "endPoint" => { "x" => 15.0, "y" => 5.0 },
                                   "incomingShape" => "a" },
                                 { "startPoint" => { "x" => 15.0, "y" => 5.0 },
                                   "endPoint" => { "x" => 20.0, "y" => 5.0 },
                                   "outgoingShape" => "b" },
                               ] }] }
    actual = Marshal.load(Marshal.dump(expected))
    actual["edges"][0]["sections"][1]["startPoint"] =
      { "x" => 15.0, "y" => 30.0 }

    diffs = described_class.diff_structural(expected, actual)
    expect(diffs.join).to include("sections[0->1]/y")
  end

  # A branched/rejoined edge's sections are not one linear chain -- array
  # adjacency alone would compare two SIBLING branches that never connect
  # (measured, see `continuity_joints`'s own comment). s1 and s2 are both
  # fed by s0 via `outgoingSections`, so array position 1 and 2 are
  # siblings of a split, not a chain: the real joints are (0,1) and (0,2),
  # never (1,2). Unit-level on `continuity_joints` itself, not through
  # `diff_structural`, so this pins the joint-selection property alone,
  # without the unrelated edge-endpoint/shape-orientation checks
  # `diff_structural` also runs.
  it "builds continuity joints from outgoingSections once any section on " \
     "the edge carries one, not from array adjacency" do
    sections = [
      { "id" => "e1_s0", "outgoingSections" => %w[e1_s1 e1_s2] },
      { "id" => "e1_s1" },
      { "id" => "e1_s2" },
    ]

    expect(described_class.continuity_joints(sections))
      .to contain_exactly([0, 1], [0, 2])
  end

  # Proves the property both ways on the same split shape: a topologically
  # valid split (both branches genuinely start where s0 ends) reports no
  # break, but a REAL disconnect on the (0,2) joint -- one array adjacency
  # would never even have checked, since 0 and 2 are not adjacent -- is
  # still caught.
  it "does not flag a valid split's real joints, but still flags a " \
     "genuinely disconnected branch" do
    sections = [
      { "id" => "e1_s0", "endPoint" => { "x" => 15.0, "y" => 5.0 },
        "outgoingSections" => %w[e1_s1 e1_s2] },
      { "id" => "e1_s1", "startPoint" => { "x" => 15.0, "y" => 5.0 } },
      { "id" => "e1_s2", "startPoint" => { "x" => 15.0, "y" => 5.0 } },
    ]
    expect(described_class.check_section_continuity(sections, "path"))
      .to eq([])

    broken = Marshal.load(Marshal.dump(sections))
    broken[2]["startPoint"] = { "x" => 15.0, "y" => 40.0 }
    expect(described_class.check_section_continuity(broken, "path").join)
      .to include("sections[0->2]")
  end

  # Mirrors the outgoingSections example above, but every section names
  # only its PREDECESSOR -- before this fix, `ref_joints` read
  # `outgoingSections` alone, so a chain described entirely through
  # `incomingSections` produced ZERO joints and this whole edge's
  # continuity went unchecked, not merely under-checked.
  it "builds continuity joints from incomingSections too, not only " \
     "outgoingSections" do
    sections = [
      { "id" => "e1_s0" },
      { "id" => "e1_s1", "incomingSections" => ["e1_s0"] },
      { "id" => "e1_s2", "incomingSections" => ["e1_s0"] },
    ]

    expect(described_class.continuity_joints(sections))
      .to contain_exactly([0, 1], [0, 2])
  end

  # `ref_joints` resolves every routing-ref id THROUGH an id => index Hash
  # built from this same edge's own sections; an id naming no section on
  # the edge (a dangling ref) used to be silently dropped by a bare
  # `filter_map { index[id] }`, so the edge simply lost that joint's
  # continuity check rather than failing loudly on the dangling reference
  # itself.
  it "flags a dangling outgoingSections/incomingSections reference " \
     "instead of silently dropping it" do
    sections = [
      { "id" => "e1_s0", "outgoingSections" => ["does_not_exist"] },
      { "id" => "e1_s1", "incomingSections" => ["also_missing"] },
    ]

    diffs = described_class.check_section_continuity(sections, "path")
    expect(diffs.join).to include("outgoingSections: references unknown " \
                                  'section id "does_not_exist"')
    expect(diffs.join).to include("incomingSections: references unknown " \
                                  'section id "also_missing"')
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
