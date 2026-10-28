# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe Elkrb::Layout::Algorithms::Stress do
  describe "Force initialization" do
    let(:path) do
      Elkrb::Graph::Graph.from_hash(
        "id" => "root",
        "children" => %w[a b c d].map do |id|
          { "id" => id, "width" => 30, "height" => 30 }
        end,
        "edges" => Array.new(3) do |i|
          {
            "id" => "e#{i}", "sources" => [%w[a b c][i]],
            "targets" => [%w[b c d][i]]
          }
        end,
      )
    end

    it "matches the ELK Force pass used to seed stress" do
      algorithm = described_class.new
      algorithm.instance_variable_set(:@graph, path)

      algorithm.send(:initialize_positions, path)

      expected = [
        [105.29442563928431, 109.46813021157331],
        [50.0, 50.0],
        [185.25720332272306, 66.43948028376938],
        [246.32229196624166, 194.517839506084],
      ]
      path.children.zip(expected).each do |node, (x, y)|
        expect(node.x).to be_within(1e-9).of(x)
        expect(node.y).to be_within(1e-9).of(y)
      end
    end

    it "uses Force padding by default and honours an explicit override" do
      default = described_class.new
      override = described_class.new(
        "elk.padding" => "[top=1,left=2,bottom=3,right=4]",
      )

      expect(default.send(:padding))
        .to eq(top: 50.0, left: 50.0, bottom: 50.0, right: 50.0)
      expect(override.send(:padding))
        .to eq(top: 1.0, left: 2.0, bottom: 3.0, right: 4.0)
    end

    it "keeps the exact prepass for small graphs and bounds large graphs" do
      algorithm = described_class.new
      pair_count = 200 * 199 / 2
      large_iterations = algorithm.send(:force_iterations, 200)

      expect(algorithm.send(:force_iterations, 4)).to eq(300)
      expect(large_iterations * pair_count)
        .to be <= described_class::FORCE_PAIR_INTERACTION_BUDGET
    end
  end

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
      result = nil
      elapsed = Benchmark.realtime do
        result = Elkrb.layout(chain_two_hundred, algorithm: "stress")
      end

      expect(elapsed).to be < 2.0
      expect(result).to have_finite_coordinates

      adjacent_lengths = result.children.each_cons(2).map do |left, right|
        Math.hypot(left.x - right.x, left.y - right.y)
      end
      expect(adjacent_lengths).to all(be_within(1e-6).of(100.0))
    end
  end

  describe "relative convergence" do
    it "stops when relative improvement falls below epsilon" do
      expect(described_class.new.send(:converged?, 100.0, 99.95, 0.001))
        .to be(true)
    end

    it "continues while relative improvement exceeds epsilon" do
      expect(described_class.new.send(:converged?, 100.0, 99.8, 0.001))
        .to be(false)
    end
  end

  describe "iterations run" do
    let(:counting_class) do
      Class.new(described_class) do
        attr_reader :iterations_run

        private

        def optimize_positions(*)
          @iterations_run = iterations_run.to_i + 1
          super
        end
      end
    end

    def chain_with(count, layout_options)
      Elkrb::Graph::Graph.from_hash(
        "id" => "r",
        "layoutOptions" => layout_options,
        "children" => Array.new(count) do |i|
          { "id" => "n#{i}", "width" => 10, "height" => 10 }
        end,
        "edges" => Array.new(count - 1) do |i|
          { "id" => "e#{i}", "sources" => ["n#{i}"],
            "targets" => ["n#{i + 1}"] }
        end,
      )
    end

    def iterations_run_with(layout_options, count: 30)
      algorithm = counting_class.new
      algorithm.layout(chain_with(count, layout_options))
      algorithm.iterations_run
    end

    # Java ELK's do/while tests the limit after an iteration has run.
    it "runs one more iteration than the limit when the limit comes first" do
      expect(iterations_run_with({ "elk.stress.iterationLimit" => 5 }))
        .to eq(6)
    end

    # A non-positive epsilon disables the relative-improvement stop, so the
    # explicit iteration limit is the only normal termination condition.
    {
      "an epsilon of zero" => { "elk.stress.epsilon" => 0 },
      "a negative epsilon" => { "elk.stress.epsilon" => -1 },
    }.each do |name, layout_options|
      it "runs to the limit with #{name}" do
        limited = layout_options.merge("elk.stress.iterationLimit" => 400)

        expect(iterations_run_with(limited)).to eq(401)
      end
    end

    it "stops before the limit when stress overflows" do
      limited = {
        "elk.stress.desiredEdgeLength" => 1e200,
        "elk.stress.iterationLimit" => 400,
      }

      expect(iterations_run_with(limited)).to be < 401
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

  describe "#calculate_stress (private)" do
    it "weights squared distance error by inverse ideal distance squared" do
      stress = described_class.new.send(
        :calculate_stress,
        [0.0, 20.0], [0.0, 0.0],
        [[0.0, 10.0], [10.0, 0.0]],
        [[Float::INFINITY, 0.01], [0.01, Float::INFINITY]],
        [[1], [0]]
      )

      expect(stress).to eq(1.0)
    end
  end

  describe "#project_line_metric (private)" do
    {
      "a connected non-line metric" => [
        [0.0, 1.0, 1.0],
        [1.0, 0.0, 1.0],
        [1.0, 1.0, 0.0],
      ],
      "a disconnected metric" => [
        [0.0, 1.0, Float::INFINITY],
        [1.0, 0.0, Float::INFINITY],
        [Float::INFINITY, Float::INFINITY, 0.0],
      ],
    }.each do |name, distances|
      it "does not project #{name}" do
        xpos = [2.0, 5.0, 11.0]
        ypos = [3.0, 7.0, 13.0]

        described_class.new.send(:project_line_metric, xpos, ypos, distances)

        expect(xpos).to eq([2.0, 5.0, 11.0])
        expect(ypos).to eq([3.0, 7.0, 13.0])
      end
    end
  end

  describe "iteration count" do
    include GraphPositions

    # One iteration against the default limit lands the nodes elsewhere, so a
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
      from_call = laid_out_positions(graph_hash, iterations: 500)
      graph_hash["layoutOptions"]["elk.stress.iterationLimit"] = 1

      expect(laid_out_positions(graph_hash, iterations: 500))
        .to eq(from_call)
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
