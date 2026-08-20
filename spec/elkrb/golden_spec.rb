# frozen_string_literal: true

RSpec.describe "elkjs golden parity" do
  it "chain2" do
    input = golden_input("chain2")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("chain2", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered ignores elk.direction and uses a 60px layer gap instead of ELK's RIGHT/20 defaults"
    expect(matched).to be(true), message
  end

  it "chain3" do
    input = golden_input("chain3")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("chain3", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered ignores elk.direction and uses a 60px layer gap instead of ELK's RIGHT/20 defaults"
    expect(matched).to be(true), message
  end

  it "fan_out" do
    input = golden_input("fan_out")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("fan_out", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered has no crossing minimisation or dummy-node routing for branching graphs"
    expect(matched).to be(true), message
  end

  it "fan_in" do
    input = golden_input("fan_in")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("fan_in", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered has no crossing minimisation or dummy-node routing for branching graphs"
    expect(matched).to be(true), message
  end

  it "diamond" do
    input = golden_input("diamond")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("diamond", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered has no crossing minimisation or dummy-node routing for branching graphs"
    expect(matched).to be(true), message
  end

  it "cycle3" do
    input = golden_input("cycle3")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("cycle3", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: cycle breaker permanently reverses edges and layered lacks crossing minimisation"
    expect(matched).to be(true), message
  end

  it "self_loop" do
    input = golden_input("self_loop")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("self_loop", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered ignores elk.direction and uses a 60px layer gap instead of ELK's RIGHT/20 defaults"
    expect(matched).to be(true), message
  end

  it "long_edge" do
    input = golden_input("long_edge")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("long_edge", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered has no crossing minimisation or dummy-node routing for long edges"
    expect(matched).to be(true), message
  end

  it "ports_simple" do
    input = golden_input("ports_simple")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("ports_simple", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered ignores elk.direction and uses a 60px layer gap instead of ELK's RIGHT/20 defaults"
    expect(matched).to be(true), message
  end

  it "labeled_node" do
    input = golden_input("labeled_node")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("labeled_node", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC8: node labels are absolute, not owner-relative"
    expect(matched).to be(true), message
  end

  it "labeled_node_placement" do
    input = golden_input("labeled_node_placement")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("labeled_node_placement", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC8: ELK node label placement keys are never read"
    expect(matched).to be(true), message
  end

  it "compound_chain" do
    input = golden_input("compound_chain")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("compound_chain", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC5: hierarchical layout sizes the parent before its children"
    expect(matched).to be(true), message
  end

  it "compound_nested" do
    input = golden_input("compound_nested")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("compound_nested", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC5: hierarchical layout sizes the parent before its children"
    expect(matched).to be(true), message
  end

  it "direction_down" do
    input = golden_input("direction_down")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("direction_down", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: elk.direction is not read by the layered algorithm"
    expect(matched).to be(true), message
  end

  it "spacing_override" do
    input = golden_input("spacing_override")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("spacing_override", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: elk.spacing.nodeNode and elk.layered.spacing.nodeNodeBetweenLayers are not read"
    expect(matched).to be(true), message
  end

  it "sizeless" do
    input = golden_input("sizeless")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("sizeless", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered ignores elk.direction and uses a 60px layer gap instead of ELK's RIGHT/20 defaults"
    expect(matched).to be(true), message
  end

  it "two_components" do
    input = golden_input("two_components")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("two_components", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered ignores elk.direction and uses a 60px layer gap instead of ELK's RIGHT/20 defaults"
    expect(matched).to be(true), message
  end

  it "box3" do
    input = golden_input("box3")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("box3", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "box_mixed" do
    input = golden_input("box_mixed")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("box_mixed", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "box_aspect" do
    input = golden_input("box_aspect")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("box_aspect", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "fixed2" do
    input = golden_input("fixed2")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("fixed2", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "mrtree3" do
    input = golden_input("mrtree3")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("mrtree3", tier: :exact)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "mrtree7" do
    input = golden_input("mrtree7")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("mrtree7", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "radial_star5" do
    input = golden_input("radial_star5")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("radial_star5", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "rect6" do
    input = golden_input("rect6")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("rect6", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "force_tri" do
    input = golden_input("force_tri")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("force_tri", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "stress_path4" do
    input = golden_input("stress_path4")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("stress_path4", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "random3" do
    input = golden_input("random3")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("random3", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "spore_overlap4" do
    input = golden_input("spore_overlap4")
    # NOT inside pending -- layout, and the matcher's own execution
    # (reading golden_expected, running GoldenComparator), both happen
    # before pending is called, so a crash in EITHER is a real failure.
    result = Elkrb.layout(input[:graph], input[:options])
    matcher = match_elkjs_golden("spore_overlap4", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC2.2: graph-level elk.algorithm pin is never read, LayoutEngine always defaults to layered"
    expect(matched).to be(true), message
  end

  it "hyperedge" do
    input = golden_input("hyperedge")
    result =
      begin
        Elkrb.layout(input[:graph], input[:options])
      rescue Elkrb::UnsupportedConfigurationException => e
        { "error" => e.message }
      end
    matcher = match_elkjs_golden("hyperedge", tier: :structural)
    matched = matcher.matches?(result)
    message = matcher.failure_message unless matched

    pending "RC7: layered silently mis-routes hyperedges instead of raising like elkjs"
    expect(matched).to be(true), message
  end
end
