# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe Elkrb::Layout::Algorithms::Stress do
  describe "layout quality" do
    let(:chain_thirty) do
      {
        "id" => "r",
        "children" => Array.new(30) do |i|
          { "id" => "n#{i}", "width" => 30, "height" => 30 }
        end,
        "edges" => Array.new(29) do |i|
          { "id" => "e#{i}", "sources" => ["n#{i}"],
            "targets" => ["n#{i + 1}"] }
        end,
      }
    end

    let(:chain_two_hundred) do
      {
        "id" => "r",
        # Isolate the all-pairs distance construction whose cubic cost this
        # regression protects against.
        "layoutOptions" => { "elk.stress.iterationLimit" => 1 },
        "children" => Array.new(200) do |i|
          { "id" => "n#{i}", "width" => 10, "height" => 10 }
        end,
        "edges" => Array.new(199) do |i|
          { "id" => "e#{i}", "sources" => ["n#{i}"],
            "targets" => ["n#{i + 1}"] }
        end,
      }
    end

    it "keeps adjacent chain nodes near the desired edge length" do
      result = Elkrb.layout(chain_thirty, algorithm: "stress")
      by_id = result.children.to_h { |node| [node.id, node] }
      distances = Array.new(29) do |i|
        left = by_id.fetch("n#{i}")
        right = by_id.fetch("n#{i + 1}")
        Math.hypot(left.x - right.x, left.y - right.y)
      end

      expect(distances).to all(be_within(10.0).of(100.0))
      expect(result).to have_no_overlapping_siblings
    end

    it "lays out a 200-node chain in under two seconds" do
      elapsed = Benchmark.realtime do
        Elkrb.layout(chain_two_hundred, algorithm: "stress")
      end

      expect(elapsed).to be < 2.0
    end
  end

  describe "#calculate_distances (private)" do
    it "resolves port-id edge endpoints to their owning node's row/column" do
      node_a = Elkrb::Graph::Node.new(
        id: "a", width: 10, height: 10,
        ports: [Elkrb::Graph::Port.new(id: "a_out")]
      )
      node_b = Elkrb::Graph::Node.new(
        id: "b", width: 10, height: 10,
        ports: [Elkrb::Graph::Port.new(id: "b_in")]
      )
      node_c = Elkrb::Graph::Node.new(id: "c", width: 10, height: 10)
      graph = Elkrb::Graph::Graph.new(children: [node_a, node_b, node_c])
      graph.edges = [
        Elkrb::Graph::Edge.new(id: "e", sources: ["a_out"], targets: ["b_in"]),
      ]

      distances = described_class.new.send(:calculate_distances, graph)

      expect(distances[0][1]).to eq(100.0)
      expect(distances[1][0]).to eq(100.0)
      expect(distances[0][2]).to eq(Float::INFINITY)
    end

    it "ignores a nested edge whose ids alias this level's ports" do
      # "x" and "y" name c's children AND a's and b's ports. Reading
      # c's own edge through the parent index made a and b look
      # adjacent.
      graph = Elkrb::Graph::Graph.from_hash(
        "id" => "r",
        "children" => [
          {
            "id" => "a", "width" => 10, "height" => 10,
            "ports" => [{ "id" => "x" }]
          },
          {
            "id" => "b", "width" => 10, "height" => 10,
            "ports" => [{ "id" => "y" }]
          },
          {
            "id" => "c", "width" => 10, "height" => 10,
            "children" => [
              { "id" => "x", "width" => 5, "height" => 5 },
              { "id" => "y", "width" => 5, "height" => 5 },
            ],
            "edges" => [
              { "id" => "inner", "sources" => ["x"], "targets" => ["y"] },
            ]
          },
        ],
        "edges" => [],
      )

      distances = described_class.new.send(:calculate_distances, graph)

      expect(distances[0][1]).to eq(Float::INFINITY)
    end
  end

  describe "iteration count" do
    include GraphPositions

    # One iteration against the 500 default lands the nodes elsewhere, so a
    # changed layout proves the option was read.
    let(:graph_hash) do
      {
        "id" => "r",
        "layoutOptions" => { "elk.algorithm" => "stress" },
        "children" => (0..4).map do |i|
          { "id" => "n#{i}", "width" => 20, "height" => 20 }
        end,
        "edges" => [
          { "id" => "e", "sources" => ["n0"], "targets" => ["n1"] },
          { "id" => "f", "sources" => ["n1"], "targets" => ["n2"] },
        ],
      }
    end
    let!(:default_positions) { laid_out_positions(graph_hash) }

    # The other direction of the two examples below: a fix that dropped the
    # call's own key would pass them and break every caller that sets it.
    [:iterations, "iterations"].each do |key|
      it "is read from the call's #{key.inspect} key" do
        expect(laid_out_positions(graph_hash, key => 1))
          .not_to eq(default_positions)
      end
    end

    it "falls through an empty String key to the Symbol key" do
      expect(laid_out_positions(graph_hash, "iterations" => nil, iterations: 1))
        .to eq(laid_out_positions(graph_hash, iterations: 1))
    end

    it "is read from elk.stress.iterationLimit in the graph" do
      one_iteration = laid_out_positions(graph_hash, iterations: 1)
      graph_hash["layoutOptions"]["elk.stress.iterationLimit"] = 1

      expect(laid_out_positions(graph_hash)).to eq(one_iteration)
    end

    it "is read from elk.stress.iterationLimit in the call" do
      expect(laid_out_positions(graph_hash, "elk.stress.iterationLimit" => 1))
        .to eq(laid_out_positions(graph_hash, iterations: 1))
    end

    [false, nil].each do |absent|
      it "treats #{absent.inspect} under the legacy key as not given" do
        graph_hash["layoutOptions"]["elk.stress.iterationLimit"] = 1

        expect(laid_out_positions(graph_hash, iterations: absent))
          .to eq(laid_out_positions(graph_hash, iterations: 1))
      end
    end

    it "lets the call's legacy iterations key beat the graph's limit" do
      graph_hash["layoutOptions"]["elk.stress.iterationLimit"] = 1

      expect(laid_out_positions(graph_hash, iterations: 500))
        .to eq(default_positions)
    end

    bad_limits = ["abc", "0x10", "", [1]]
    legacy_keys = [:iterations, "iterations"]
    limit_error = /elk\.stress\.iterationLimit/

    bad_limits.each do |bad|
      legacy_keys.each do |key|
        it "rejects #{bad.inspect} under the call's #{key.inspect} key" do
          expect { laid_out_positions(graph_hash, key => bad) }
            .to raise_error(Elkrb::ValidationError, limit_error)
        end
      end

      it "rejects #{bad.inspect} as the graph's elk.stress.iterationLimit" do
        graph_hash["layoutOptions"]["elk.stress.iterationLimit"] = bad

        expect { laid_out_positions(graph_hash) }
          .to raise_error(Elkrb::ValidationError, limit_error)
      end
    end

    it "does not follow force's elk.force.iterations in the graph" do
      graph_hash["layoutOptions"]["elk.force.iterations"] = 1

      expect(laid_out_positions(graph_hash)).to eq(default_positions)
    end

    it "does not follow force's elk.force.iterations in the call" do
      expect(laid_out_positions(graph_hash, "elk.force.iterations": 1))
        .to eq(default_positions)
    end
  end
end
