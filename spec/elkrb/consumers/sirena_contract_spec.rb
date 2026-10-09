# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe "sirena consumer contract" do
  include CrossLevelEdgeHelpers
  include SirenaContract

  let(:down) { { "algorithm" => "layered", "elk.direction" => "DOWN" } }

  def warnings_naming(key, &)
    capture_elkrb_warnings(&).lines.grep(/\b#{Regexp.escape(key)}\b/)
  end

  describe "registry status" do
    SirenaContract::KEYS.each do |key, row|
      it "#{key} is #{row[:status]} (slice #{row[:slice]})" do
        expect(Elkrb::Options::Registry.status(key)).to eq(row[:status])
      end
    end
  end

  describe "honoured keys change the output as promised" do
    it "elk.direction flips the layer axis between DOWN and RIGHT" do
      axis = lambda do |direction, coordinate|
        graph = layout_consumer(
          "flowchart_td", down.merge("elk.direction" => direction)
        )
        positions = positions_by_id(graph)
        %w[Start Process Decision].map { |id| positions[id][coordinate] }
      end

      down_layers = axis.call("DOWN", 1)
      right_layers = axis.call("RIGHT", 0)

      expect(down_layers).to eq(down_layers.sort.uniq)
      expect(right_layers).to eq(right_layers.sort.uniq)
    end

    it "elk.spacing.nodeNode moves sibling nodes apart by the delta" do
      gap = lambda do |spacing|
        positions = positions_by_id(
          layout_consumer("flowchart_td",
                          down.merge("elk.spacing.nodeNode" => spacing)),
        )
        positions["Failure"][0] - positions["Success"][0]
      end

      expect(gap.call(80) - gap.call(50)).to eq(30)
    end

    it "elk.spacing.nodeNode given as the C4 String equals the Integer" do
      options = down.merge("elk.spacing.nodeNode" => "60")
      as_string = positions_by_id(layout_consumer("flowchart_td", options))
      as_number = positions_by_id(
        layout_consumer("flowchart_td",
                        options.merge("elk.spacing.nodeNode" => 60)),
      )

      expect(as_string).to eq(as_number)
    end

    it "elk.layered.spacing.nodeNodeBetweenLayers moves a layer by the delta" do
      drop = lambda do |spacing|
        positions = positions_by_id(
          layout_consumer(
            "flowchart_td",
            down.merge("elk.layered.spacing.nodeNodeBetweenLayers" => spacing),
          ),
        )
        positions["Success"][1] - positions["Decision"][1]
      end

      expect(drop.call(90) - drop.call(50)).to eq(40)
    end

    it "algorithm box puts nodes in the box packing, not the layered ones" do
      layered = positions_by_id(layout_consumer("flowchart_td", down))
      boxed = positions_by_id(
        layout_consumer("flowchart_td", down.merge("algorithm" => "box")),
      )

      expect(boxed.values.first).to eq([15.0, 15.0])
      expect(layered.values.first).not_to eq([15.0, 15.0])
      expect(boxed).not_to eq(layered)
    end

    it "elk.edgeRouting ORTHOGONAL yields bend points, POLYLINE none" do
      orthogonal = layout_consumer(
        "flowchart_td", down.merge("elk.edgeRouting" => "ORTHOGONAL")
      )
      polyline = layout_consumer(
        "flowchart_td", down.merge("elk.edgeRouting" => "POLYLINE")
      )

      expect(bend_point_count(orthogonal)).to be_positive
      expect(bend_point_count(polyline)).to eq(0)
    end

    it "elk.padding as the C4 String puts children at the padded origin" do
      origin = lambda do |padding|
        hash = consumer_hash("c4_nested")
        hash["children"][0]["layoutOptions"]["elk.padding"] =
          "[top=#{padding},left=#{padding},bottom=#{padding},right=#{padding}]"
        shop = child_by_id(layout_hash(hash).children.first, "shop")
        [shop.x, shop.y]
      end

      expect(origin.call(40)).to eq([40.0, 40.0])
      expect(origin.call(10)).to eq([10.0, 10.0])
    end

    it "elk.algorithm box on a boundary packs it, the root stays layered" do
      graph = layout_hash(consumer_hash("c4_nested"))
      acme = child_by_id(graph, "acme")
      shop = child_by_id(acme, "shop")
      billing = child_by_id(acme, "billing")
      customer = child_by_id(graph, "customer")

      expect([billing.x, billing.y]).to eq([shop.x + shop.width + 60, shop.y])
      expect(customer.y).to be < acme.y
      expect(customer.x).to be < acme.x + acme.width
    end

    it "elk.algorithm layered on that boundary stacks the children instead" do
      hash = consumer_hash("c4_nested")
      hash["children"][0]["layoutOptions"]["elk.algorithm"] = "layered"
      acme = child_by_id(layout_hash(hash), "acme")

      expect(child_by_id(acme, "billing").y)
        .to be > child_by_id(acme, "shop").y
    end

    it "elk.layered.crossingMinimization.strategy changes the crossing count" do
      crossings = lambda do |strategy|
        options = down.merge(
          "elk.layered.crossingMinimization.strategy" => strategy,
        )
        crossing_count(layout_hash(reversed_bipartite_hash(options)))
      end

      expect(crossings.call("NONE")).not_to eq(crossings.call("LAYER_SWEEP"))
    end

    it "elk.layered.considerModelOrder.strategy changes the crossing count" do
      crossings = lambda do |strategy|
        options = down.merge(
          "elk.layered.considerModelOrder.strategy" => strategy,
        )
        crossing_count(layout_hash(reversed_bipartite_hash(options)))
      end

      expect(crossings.call("NODES_AND_EDGES"))
        .not_to eq(crossings.call("NONE"))
    end
  end

  describe "accepted keys warn once and change nothing" do
    SirenaContract::ACCEPTED_PROBES.each do |key, (algorithm, value)|
      it "#{key} warns exactly once and leaves the output byte-identical" do
        base = { "algorithm" => algorithm }
        plain = echo_free_json(layout_consumer("flowchart_td", base))
        probed = nil
        warnings = warnings_naming(key) do
          probed = layout_consumer("flowchart_td", base.merge(key => value))
        end

        expect(warnings.size).to eq(1)
        expect(warnings.first).to include("accepted but not honoured")
        expect(echo_free_json(probed)).to eq(plain)
      end
    end
  end

  describe "partial keys that layered reads" do
    SirenaContract::PARTIAL_READ_BY_LAYERED.each do |key, value|
      it "#{key} does not warn when layered lays the graph out" do
        warnings = warnings_naming(key) do
          layout_consumer("flowchart_td",
                          { "algorithm" => "layered", key => value })
        end

        expect(warnings).to be_empty
      end
    end
  end

  describe "elk.hierarchyHandling is partially honoured" do
    let(:without_key) do
      hash = consumer_hash("c4_nested")
      hash["layoutOptions"].delete("elk.hierarchyHandling")
      hash
    end

    it "warns exactly once" do
      warnings = warnings_naming("elk.hierarchyHandling") do
        layout_hash(consumer_hash("c4_nested"))
      end

      expect(warnings.size).to eq(1)
      expect(warnings.first).to include("partially honoured")
    end

    it "routes every root relationship but leaves node coordinates alone" do
      with_key = layout_hash(consumer_hash("c4_nested"))
      plain = layout_hash(without_key)

      expect(with_key.edges.map { |edge| edge.sections.size }).to all(eq(1))
      expect(plain.edges.map { |edge| edge.sections.to_a.size }).to all(eq(0))
      expect(nested_coordinates(with_key)).to eq(nested_coordinates(plain))
    end
  end

  describe "algorithm names" do
    it "resolves sporeOverlap, the camelCase spelling sirena uses" do
      expect(Elkrb::Layout::AlgorithmRegistry.get("sporeOverlap"))
        .to eq(Elkrb::Layout::Algorithms::SporeOverlap)
    end
  end

  describe "the C4 fixture" do
    it "gives every root relationship one section on the member borders" do
      graph = layout_hash(consumer_hash("c4_nested"))
      rectangles = absolute_rectangles(graph)

      expect(graph.edges.size).to eq(3)
      graph.edges.each do |edge|
        expect(edge.sections.size).to eq(1)
        section = edge.sections.first
        expect(point_on_border?(section.start_point,
                                rectangles.fetch(edge.sources.first)))
          .to be(true), "#{edge.id} start is off #{edge.sources.first}"
        expect(point_on_border?(section.end_point,
                                rectangles.fetch(edge.targets.first)))
          .to be(true), "#{edge.id} end is off #{edge.targets.first}"
      end
    end
  end
end
