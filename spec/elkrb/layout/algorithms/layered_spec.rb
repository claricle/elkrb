# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::LayeredAlgorithm do
  describe "S25b long-edge dummies" do
    def long_edge_graph(ids)
      {
        id: "root",
        children: ids.map { |id| { id: id, width: 100, height: 60 } },
        edges: ids.each_cons(2).with_index.map do |(source, target), index|
          { id: "chain_#{index}", sources: [source], targets: [target] }
        end + [{ id: "long", sources: [ids.first], targets: [ids.last] }],
      }
    end

    # ELK's long edge runs straight along its dummy's lane: it leaves its
    # node into the first gap, runs the lane, and drops into the last gap --
    # two bends per gap it turns in, never one at the centre.
    it "routes a two-layer edge around the intervening node" do
      result = Elkrb.layout(long_edge_graph(%w[a b c]), algorithm: "layered")
      section = result.edges.find { |edge| edge.id == "long" }.sections.first
      obstacle = result.children.find { |node| node.id == "b" }

      expect(section.bend_points.length).to eq(4)
      expect(route_interior_crossings(section, obstacle)).to be_empty
    end

    it "pads the graph from the lane when the lane is outermost" do
      result = Elkrb.layout(long_edge_graph(%w[a b c]), algorithm: "layered")
      section = result.edges.find { |edge| edge.id == "long" }.sections.first
      top = result.children.map(&:y).min

      expect(section.bend_points.map(&:y).min).to be < top
      expect(section.bend_points.map(&:y).min).to eq(12.0)
    end

    it "visits a reversed edge's bends from its own start" do
      result = Elkrb.layout(
        long_edge_graph(%w[a b c]).tap do |graph|
          graph[:edges].last.merge!(sources: ["c"], targets: ["a"])
        end,
        algorithm: "layered",
      )
      section = result.edges.find { |edge| edge.id == "long" }.sections.first
      bend_x = section.bend_points.map(&:x)

      expect(bend_x).to eq(bend_x.sort.reverse)
    end

    it "runs two intermediate layers along one lane" do
      result = Elkrb.layout(
        long_edge_graph(%w[a b c d]), algorithm: "layered"
      )
      section = result.edges.find { |edge| edge.id == "long" }.sections.first

      lane = section.bend_points.map(&:y).min
      expect(section.bend_points.map(&:y).count(lane)).to eq(2)
      expect(section.bend_points.length).to eq(4)
    end

    it "never exposes dummy ids as graph children or JSON" do
      input_ids = %w[a b c]
      result = Elkrb.layout(long_edge_graph(input_ids), algorithm: "layered")

      expect(result.children.map(&:id)).to eq(input_ids)
      expect(result.to_json).not_to include("__elkrb_dummy")
    end
  end

  describe "S25a crossing minimization" do
    let(:crossing_graph) do
      {
        id: "root",
        children: %w[a b c d].map do |id|
          { id: id, width: 100, height: 60 }
        end,
        edges: [
          { id: "1", sources: ["a"], targets: ["d"] },
          { id: "2", sources: ["b"], targets: ["c"] },
        ],
      }
    end

    it "removes crossings with the default layer sweep" do
      result = Elkrb.layout(crossing_graph, algorithm: "layered")

      expect(LayeredCrossings.count(result)).to eq(0)
    end

    context "with a graph whose creation order the sweep improves" do
      let(:sweep_graph) do
        {
          id: "root",
          children: %w[a d c e b f].map do |id|
            { id: id, width: 100, height: 60 }
          end,
          edges: %w[a-e b-e a-c a-d b-d a-f].map do |pair|
            source, target = pair.split("-")
            { id: pair, sources: [source], targets: [target] }
          end,
        }
      end

      def ids_by_height(result, ids)
        result.children.select { |node| ids.include?(node.id) }
          .sort_by(&:y).map(&:id)
      end

      def layout_with(strategy)
        Elkrb.layout(
          sweep_graph,
          algorithm: "layered",
          "elk.layered.crossingMinimization.strategy" => strategy,
        )
      end

      it "leaves the orders elkjs leaves when crossing minimization is NONE" do
        result = layout_with("NONE")

        expect(ids_by_height(result, %w[a b])).to eq(%w[b a])
        expect(ids_by_height(result, %w[c d e f])).to eq(%w[e c d f])
        expect(LayeredCrossings.count(result)).to eq(2)
      end

      it "sweeps the same graph to fewer crossings by default" do
        result = layout_with("LAYER_SWEEP")

        expect(ids_by_height(result, %w[a b])).to eq(%w[a b])
        expect(ids_by_height(result, %w[c d e f])).to eq(%w[c f e d])
        expect(LayeredCrossings.count(result)).to eq(1)
      end
    end

    # Orders measured with elkjs 0.11.0: under NONE its greedy switch still
    # runs on graphs under 40 nodes, so b and c end up the same way whatever
    # order they were created in.
    def none_order(children, edges)
      result = Elkrb.layout(
        {
          id: "root",
          children: children.map { |id| { id: id, width: 100, height: 60 } },
          edges: edges.map do |source, target|
            { id: "#{source}#{target}", sources: [source], targets: [target] }
          end,
        },
        algorithm: "layered",
        "elk.layered.crossingMinimization.strategy" => "NONE",
      )
      result.children.select { |node| %w[b c].include?(node.id) }
        .sort_by(&:y).map(&:id)
    end

    creations = %w[dbc dcb bcd cbd]
    {
      "fan-in" => [%w[c b], [%w[b d], %w[c d]]],
      "fan-out" => [%w[b c], [%w[d b], %w[d c]]],
    }.each do |name, (order, edges)|
      creations.each do |creation|
        it "orders a #{name} created as #{creation} as elkjs does under NONE" do
          expect(none_order(creation.chars, edges)).to eq(order)
        end
      end
    end

    it "stops the greedy switch at 40 nodes, as elkjs does" do
      fan_in = [%w[b d], %w[c d]]
      filler = ->(count) { Array.new(count) { |i| "z#{i}" } }

      expect(none_order(%w[d b c] + filler.call(36), fan_in)).to eq(%w[c b])
      expect(none_order(%w[d b c] + filler.call(37), fan_in)).to eq(%w[b c])
    end

    it "places nodes the same way for every nodePlacement.strategy value" do
      values = Elkrb::Options::Registry.all
        .fetch("elk.layered.nodePlacement.strategy").fetch(:values)
      branching = crossing_graph.merge(
        edges: crossing_graph[:edges] +
          [{ id: "3", sources: ["a"], targets: ["c"] }],
      )
      layouts = values.map do |value|
        Elkrb.layout(
          branching,
          algorithm: "layered",
          "elk.layered.nodePlacement.strategy" => value,
        ).to_json
      end

      expect(layouts.uniq.length).to eq(1)
    end

    it "reports both crossing options as honoured" do
      expect(Elkrb::Options::Registry.status(
               "elk.layered.crossingMinimization.strategy",
             )).to eq(:honoured)
      expect(Elkrb::Options::Registry.status(
               "elk.layered.considerModelOrder.strategy",
             )).to eq(:honoured)
    end

    it "places the diamond without crossings" do
      input = JSON.parse(File.read("spec/fixtures/golden/inputs/diamond.json"))
      result = Elkrb.layout(input.fetch("graph"), input.fetch("options"))

      expect(LayeredCrossings.count(result)).to eq(0)
    end
  end

  describe "S9 direction and spacing" do
    let(:chain) do
      {
        id: "root",
        children: %w[n1 n2 n3].map do |id|
          { id: id, width: 30, height: 30 }
        end,
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"] },
          { id: "e2", sources: ["n2"], targets: ["n3"] },
        ],
      }
    end

    it "keeps LEFT inside the graph and reverses RIGHT's layer order" do
      right = Elkrb.layout(Marshal.load(Marshal.dump(chain)),
                           algorithm: "layered", "elk.direction" => "RIGHT")
      left = Elkrb.layout(Marshal.load(Marshal.dump(chain)),
                          algorithm: "layered", "elk.direction" => "LEFT")

      expect(left.children).to all(satisfy do |node|
        node.x >= 0 && node.y >= 0 && node.x + node.width <= left.width &&
          node.y + node.height <= left.height
      end)
      expect(right.children.map(&:x)).to eq(right.children.map(&:x).sort)
      expect(left.children.map(&:x)).to eq(left.children.map(&:x).sort.reverse)
    end

    it "keeps UP inside the graph and reverses DOWN's layer order" do
      down = Elkrb.layout(Marshal.load(Marshal.dump(chain)),
                          algorithm: "layered", "elk.direction" => "DOWN")
      up = Elkrb.layout(Marshal.load(Marshal.dump(chain)),
                        algorithm: "layered", "elk.direction" => "UP")

      expect(up.children).to all(satisfy do |node|
        node.x >= 0 && node.y >= 0 && node.x + node.width <= up.width &&
          node.y + node.height <= up.height
      end)
      expect(down.children.map(&:y)).to eq(down.children.map(&:y).sort)
      expect(up.children.map(&:y)).to eq(up.children.map(&:y).sort.reverse)
    end

    it "treats UNDEFINED as RIGHT" do
      right = Elkrb.layout(Marshal.load(Marshal.dump(chain)),
                           algorithm: "layered", "elk.direction" => "RIGHT")
      undefined_options = {
        algorithm: "layered", "elk.direction" => "UNDEFINED"
      }
      undefined = Elkrb.layout(Marshal.load(Marshal.dump(chain)),
                               undefined_options)

      expect(undefined.children.map { |node| [node.x, node.y] })
        .to eq(right.children.map { |node| [node.x, node.y] })
    end

    it "normalizes spline orientation aliases before layered routing" do
      horizontal = Elkrb.layout(
        Marshal.load(Marshal.dump(chain)),
        algorithm: "layered", "elk.direction" => "HORIZONTAL",
      )
      vertical = Elkrb.layout(
        Marshal.load(Marshal.dump(chain)),
        algorithm: "layered", "elk.direction" => "VERTICAL",
      )

      expect(horizontal.children.map { |node| [node.x, node.y] })
        .to eq(Elkrb.layout(
          Marshal.load(Marshal.dump(chain)),
          algorithm: "layered", "elk.direction" => "RIGHT",
        ).children.map { |node| [node.x, node.y] })
      expect(vertical.children.map { |node| [node.x, node.y] })
        .to eq(Elkrb.layout(
          Marshal.load(Marshal.dump(chain)),
          algorithm: "layered", "elk.direction" => "DOWN",
        ).children.map { |node| [node.x, node.y] })
    end

    it "reads the canonical layer gap and its call-level alias" do
      canonical_graph = Marshal.load(Marshal.dump(chain))
      canonical_graph[:layoutOptions] = {
        "elk.layered.spacing.nodeNodeBetweenLayers" => 40,
      }
      canonical = Elkrb.layout(canonical_graph, algorithm: "layered")
      aliased = Elkrb.layout(Marshal.load(Marshal.dump(chain)),
                             algorithm: "layered", layer_spacing: 40)
      first, second = canonical.children

      expect(second.x).to eq(first.x + first.width + 40)
      expect(aliased.children.map { |node| [node.x, node.y] })
        .to eq(canonical.children.map { |node| [node.x, node.y] })
    end
  end

  describe "#layout" do
    it "lays out edges that reference port ids into separate layers" do
      graph = JSON.parse(File.read("spec/fixtures/elkjs_bug7_complex.json"))

      result = Elkrb.layout(graph, algorithm: "layered")

      expect(result.children.map(&:x).uniq.size).to be > 1
    end

    it "raises Elkrb::ValidationError for a duplicate node id" do
      graph = {
        id: "r",
        children: [
          { id: "a", width: 10, height: 10 },
          { id: "a", width: 10, height: 10 },
        ],
        edges: [],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::ValidationError, /duplicate id: a/)
    end

    it "does not stack-overflow on a two-port self-loop beside a real edge" do
      # "p1" and "p2" are two ports of ONE node, so this edge is a
      # self-loop on "a" however its endpoints are spelled. A layer pass
      # that compares RAW endpoint ids sees "p1" != "p2", treats the edge
      # as real incoming traffic into "a" from "a", and makes "a" its own
      # predecessor. LayerAssigner#usable_edge? is what refuses that: it
      # resolves both endpoints to their owning node through the index and
      # drops the edge when the two are the same node.
      graph = {
        id: "r",
        children: [
          {
            id: "a", width: 10, height: 10,
            ports: [{ id: "p1" }, { id: "p2" }]
          },
          { id: "b", width: 10, height: 10 },
        ],
        edges: [
          { id: "loop", sources: ["p1"], targets: ["p2"] },
          { id: "real", sources: ["a"], targets: ["b"] },
        ],
      }

      result = Elkrb.layout(graph, algorithm: "layered")
      a = result.children.find { |n| n.id == "a" }
      b = result.children.find { |n| n.id == "b" }

      # Both edges are one source and one target, so the validator has
      # nothing to say about either: the self-loop is dropped when layers
      # are assigned, not refused at the door.
      expect(b.x).to be > a.x
    end

    it "preserves cyclic edge directions and assigns three layers" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [
          { id: "ab", sources: ["a"], targets: ["b"] },
          { id: "bc", sources: ["b"], targets: ["c"] },
          { id: "ca", sources: ["c"], targets: ["a"] },
        ],
      }

      result = Elkrb.layout(graph, algorithm: "layered")

      expect(result.edges.map { |edge| [edge.sources, edge.targets] }).to eq(
        [
          [["a"], ["b"]],
          [["b"], ["c"]],
          [["c"], ["a"]],
        ],
      )
      expect(result.edges).to all(
        satisfy { |edge| !edge.properties&.key?("reversed") },
      )
      # Exact layer ORDER, not just a distinct count: a CycleBreaker that
      # detects nothing still produces 3 distinct layers here, because
      # LayerAssigner's own re-entrancy guard independently breaks the
      # 3-node cycle during layer computation -- just into the wrong
      # order (b, c, a instead of a, b, c). Only the order proves
      # CycleBreaker, not the fallback, resolved it.
      a = result.children.find { |n| n.id == "a" }
      b = result.children.find { |n| n.id == "b" }
      c = result.children.find { |n| n.id == "c" }
      expect(a.x).to be < b.x
      expect(b.x).to be < c.x
    end

    it "raises for a hyperedge with multiple sources" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [{ id: "e", sources: %w[a b], targets: ["c"] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(
          Elkrb::UnsupportedConfigurationException,
          "layered does not support hyperedges (edge e)",
        )
    end

    it "raises for a hyperedge with multiple targets" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [{ id: "e", sources: ["a"], targets: %w[b c] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::UnsupportedConfigurationException)
    end

    # nil and "" are one name to the reader, so they are one thing to the
    # validator too: NEITHER is an id. An anonymous edge carries no handle,
    # so it has nothing to be a duplicate of, and a graph may hold as many
    # as it likes.
    #
    # This example is the regression this branch had to undo. While the
    # cycle breaker keyed reversals by edge id, every anonymous edge shared
    # one key, and the validator refused the second one to cover that --
    # so `Elkrb.layout` rejected an ordinary two-edge graph written without
    # ids, which v2 lays out. Reversals are keyed by edge identity now, so
    # the refusal is gone with the reason for it.
    it "lays out a nil id and an empty-string id as two anonymous edges" do
      graph = {
        id: "r",
        children: %w[a b c d].map { |id| { id: id, width: 10, height: 10 } },
        edges: [
          { sources: ["a"], targets: ["b"] },
          { id: "", sources: ["c"], targets: ["d"] },
        ],
      }

      result = Elkrb.layout(graph, algorithm: "layered")
      x = result.children.to_h { |node| [node.id, node.x] }

      # Both edges took effect: each target sits a layer right of its source.
      expect(x["a"]).to be < x["b"]
      expect(x["c"]).to be < x["d"]
    end

    # The reversal set holds edge OBJECTS compared by identity. Keyed by id
    # instead, the anonymous back edge b -> a puts `nil` in the set, and
    # every other anonymous edge in the graph then reads as reversed: c -> d
    # is laid out as d -> c and d comes before c on the layer axis.
    it "reverses only the anonymous edge that closes the cycle" do
      graph = {
        id: "r",
        children: %w[a b c d].map { |id| { id: id, width: 10, height: 10 } },
        edges: [
          { sources: ["a"], targets: ["b"] },
          { sources: ["b"], targets: ["a"] },
          { sources: ["c"], targets: ["d"] },
        ],
      }

      result = Elkrb.layout(graph, algorithm: "layered")
      x = result.children.to_h { |node| [node.id, node.x] }

      expect(x["c"]).to be < x["d"]
    end

    it "still accepts two edges carrying different real ids" do
      graph = {
        id: "r",
        children: %w[a b c d].map { |id| { id: id, width: 10, height: 10 } },
        edges: [
          { id: "e1", sources: ["a"], targets: ["b"] },
          { id: "e2", sources: ["c"], targets: ["d"] },
        ],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .not_to raise_error
    end

    # `""` is truthy in Ruby, so a plain `edge.id.nil?` test reads the
    # empty string as a real id -- and then these two edges are duplicates
    # of each other and the graph is refused. This example is the one that
    # fails if the emptiness half of `anonymous?` is dropped; the nil
    # examples pass either way.
    it "treats an empty-string edge id as no id, not as the id \"\"" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [
          { id: "", sources: ["a"], targets: ["b"] },
          { id: "", sources: ["b"], targets: ["c"] },
        ],
      }

      result = Elkrb.layout(graph, algorithm: "layered")
      x = result.children.to_h { |node| [node.id, node.x] }

      expect(x["a"]).to be < x["b"]
      expect(x["b"]).to be < x["c"]
    end

    # An edge id is optional in ELK, so an error message could name the
    # edge as the empty string. The endpoints are the fallback handle, and
    # "(no endpoints)" is what the fallback itself falls back to -- which
    # is why the comment above `edge_label` no longer claims an edge always
    # has endpoints. Both halves show in this one message.
    it "names an id-less edge by its endpoints in a missing-endpoint error" do
      graph = {
        id: "r",
        children: %w[a b].map { |id| { id: id, width: 10, height: 10 } },
        edges: [{ sources: [], targets: ["b"] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(
          Elkrb::UnsupportedConfigurationException,
          "layered requires non-empty edge endpoints " \
          '(edge (none), (no endpoints) -> "b")',
        )
    end

    it "names an id-less edge by its endpoints in a hyperedge error" do
      graph = {
        id: "r",
        children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
        edges: [{ sources: ["a"], targets: %w[b c] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(
          Elkrb::UnsupportedConfigurationException,
          'layered does not support hyperedges (edge (none), "a" -> "b", "c")',
        )
    end

    it "raises for missing or empty endpoints before the empty fast path" do
      graph = {
        id: "r",
        children: [],
        edges: [{ id: "missing", sources: [], targets: ["a"] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::UnsupportedConfigurationException)
    end

    it "raises for nil endpoint ids" do
      graph = {
        id: "r",
        children: [{ id: "a", width: 10, height: 10 }],
        edges: [{ id: "missing", sources: [nil], targets: ["a"] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(
          Elkrb::UnsupportedConfigurationException,
          "layered requires non-empty edge endpoints (edge missing)",
        )
    end

    it "raises for nil target endpoint ids" do
      graph = {
        id: "r",
        children: [{ id: "a", width: 10, height: 10 }],
        edges: [{ id: "missing", sources: ["a"], targets: [nil] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(
          Elkrb::UnsupportedConfigurationException,
          "layered requires non-empty edge endpoints (edge missing)",
        )
    end

    # `endpoint_present?` rejects nil only, deliberately. NodeIndex#add
    # rejects a nil id and accepts every other value, so "" is a legal node
    # id and an edge reaching it must lay out. Tightening the guard to
    # `!endpoint.to_s.empty?` raises here instead -- and left every other
    # example in the suite green, because nothing else ever passes an empty
    # string to that predicate.
    it "lays out an edge whose endpoint is a node with an empty-string id" do
      graph = {
        id: "r",
        children: [
          { id: "", width: 10, height: 10 },
          { id: "b", width: 10, height: 10 },
        ],
        edges: [{ id: "e", sources: [""], targets: ["b"] }],
      }

      laid_out = Elkrb.layout(graph, algorithm: "layered")
      x = laid_out.children.to_h { |node| [node.id, node.x] }

      expect(x.keys).to contain_exactly("", "b")
      expect(x[""]).to be < x["b"]
    end

    # An unresolvable endpoint is skipped, not rejected -- and "" is not a
    # special case of that. Every id below names no node, and all of them
    # must behave the same way, which is what stops the guard above from
    # being tightened for only one of them. The absolute expectation is the
    # positive control: without it the example would pass on any change that
    # broke every id identically.
    it "treats an unresolvable empty-string endpoint like other absent ids" do
      build = lambda do |target|
        {
          id: "r",
          children: [
            { id: "a", width: 10, height: 10 },
            { id: "b", width: 10, height: 10 },
          ],
          edges: [{ id: "e", sources: ["a"], targets: [target] }],
        }
      end

      positions = lambda do |target|
        laid_out = Elkrb.layout(build.call(target), algorithm: "layered")
        laid_out.children.map { |node| [node.id, node.x, node.y] }
      end

      unlinked = [["a", 12.0, 12.0], ["b", 12.0, 42.0]]
      expect(positions.call("nosuchnode")).to eq(unlinked)
      ["", "  ", "no such node", "A"].each do |absent|
        expect(positions.call(absent)).to eq(unlinked)
      end
    end

    it "validates edges when children are omitted" do
      graph = {
        id: "r",
        edges: [{ id: "e", sources: ["a"], targets: ["b", "c"] }],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::UnsupportedConfigurationException)
    end

    it "validates a leaf child's edges in the parent index" do
      graph = {
        id: "r",
        children: [
          {
            id: "leaf", width: 10, height: 10,
            edges: [{ id: "nested", sources: ["a"], targets: ["b", "c"] }]
          },
        ],
        edges: [],
      }

      expect { Elkrb.layout(graph, algorithm: "layered") }
        .to raise_error(Elkrb::UnsupportedConfigurationException)
    end

    it "lays out a 5000-node chain without overflowing the stack" do
      count = 5000
      graph = {
        id: "r",
        children: (0...count).map do |i|
          { id: "n#{i}", width: 1, height: 1 }
        end,
        edges: (0...(count - 1)).map do |i|
          { id: "e#{i}", sources: ["n#{i}"], targets: ["n#{i + 1}"] }
        end,
      }

      result = Elkrb.layout(graph, algorithm: "layered")

      expect(result.children.size).to eq(count)
      expect(result.children.map(&:x).uniq.size).to eq(count)
    end

    it "leaves a nested edge whose ids alias this level's ports alone" do
      # "x" and "y" name c's children AND a's and b's ports. Resolving
      # c's own edge through the parent index aliased it onto a and b,
      # so walking b -> c reached c with b still on the dfs stack and
      # reversed an acyclic nested edge into y -> x.
      graph = cross_level_graph(
        edges: [{ id: "bc", sources: ["b"], targets: ["c"] }],
      )

      result = Elkrb.layout(graph, algorithm: "layered")
      inner = result.children.find { |n| n.id == "c" }.edges.first

      expect(inner.sources).to eq(["x"])
      expect(inner.targets).to eq(["y"])
    end

    it "does not layer this level by a nested edge's aliased ids" do
      # Nothing connects a, b and c at the top level, so all three are
      # roots. The aliased nested edge made b a layer of its own. Components
      # stay joined so the layers are all there is to see.
      result = Elkrb.layout(
        cross_level_graph, algorithm: "layered",
                           "elk.separateConnectedComponents" => false
      )

      # One layer: every node overlaps the same column. Unequal nodes sit
      # at different x within it.
      expect(result.children.map(&:x).max)
        .to be < result.children.map { |node| node.x + node.width }.min
    end
  end

  def cross_level_graph(edges: [])
    {
      id: "r",
      children: [
        { id: "a", width: 10, height: 10, ports: [{ id: "x" }] },
        { id: "b", width: 10, height: 10, ports: [{ id: "y" }] },
        {
          id: "c", width: 10, height: 10,
          children: [
            { id: "x", width: 5, height: 5 },
            { id: "y", width: 5, height: 5 },
          ],
          edges: [{ id: "inner", sources: ["x"], targets: ["y"] }]
        },
      ],
      edges: edges,
    }
  end
end
