# spec/support/golden_comparator_corruption_spec.rb
# frozen_string_literal: true

# Split out of golden_helper_spec.rb (see golden_comparator_pinning_spec.rb
# for the split rationale). Each example here corrupts a real committed
# golden in one specific way the comparator used to accept.
require_relative "golden_helper"

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
