# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::LayoutEngine do
  include GraphPositions

  let(:simple_graph_json) do
    JSON.parse(File.read("spec/fixtures/simple_graph.json"))
  end

  describe "#layout" do
    context "with box algorithm" do
      it "positions nodes in a grid pattern" do
        result = described_class.layout(simple_graph_json, algorithm: "box")

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children.length).to eq(3)

        # Check that nodes have positions
        result.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # Check graph has dimensions
        expect(result.width).to be > 0
        expect(result.height).to be > 0
      end
    end

    context "with random algorithm" do
      it "positions nodes at random locations" do
        result = described_class.layout(simple_graph_json, algorithm: "random")

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.children.length).to eq(3)

        # Check that nodes have positions
        result.children.each do |node|
          expect(node.x).to be_a(Numeric)
          expect(node.y).to be_a(Numeric)
          expect(node.x).to be >= 0
          expect(node.y).to be >= 0
        end

        # Check graph has dimensions
        expect(result.width).to be > 0
        expect(result.height).to be > 0
      end
    end

    context "with fixed algorithm" do
      it "keeps nodes at their current positions" do
        graph_with_positions = simple_graph_json.dup
        graph_with_positions["children"] = [
          { "id" => "n1", "x" => 10, "y" => 20, "width" => 30, "height" => 30 },
          { "id" => "n2", "x" => 50, "y" => 60, "width" => 30, "height" => 30 },
          { "id" => "n3", "x" => 90, "y" => 100, "width" => 30,
            "height" => 30 },
        ]

        result = described_class.layout(
          graph_with_positions,
          algorithm: "fixed",
        )

        expect(result).to be_a(Elkrb::Graph::Graph)

        n1 = result.find_node("n1")
        n2 = result.find_node("n2")
        n3 = result.find_node("n3")

        expect([n1.x, n1.y]).to eq([10.0, 20.0])
        expect([n2.x, n2.y]).to eq([50.0, 60.0])
        expect([n3.x, n3.y]).to eq([90.0, 100.0])
      end
    end

    context "with layout options" do
      it "applies spacing options" do
        result = described_class.layout(
          simple_graph_json,
          algorithm: "box",
          spacing_node_node: 50,
        )

        expect(result).to be_a(Elkrb::Graph::Graph)

        # With larger spacing, graph should be larger
        n1 = result.children[0]
        n2 = result.children[1]

        # Nodes should be spaced at least 50 units apart
        distance = n2.x - n1.x
        expect(distance).to be >= 50
      end

      it "applies padding options" do
        result = described_class.layout(
          simple_graph_json,
          algorithm: "box",
          padding: { top: 20, bottom: 20, left: 20, right: 20 },
        )

        expect(result).to be_a(Elkrb::Graph::Graph)

        # First node should be at least at padding position
        n1 = result.children[0]
        expect(n1.x).to be >= 20
        expect(n1.y).to be >= 20
      end
    end

    context "with hash input" do
      it "converts hash to Graph model" do
        result = described_class.layout(simple_graph_json, algorithm: "box")

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.id).to eq("root")
      end
    end

    context "with Graph model input" do
      it "accepts Graph model directly" do
        graph = Elkrb::Graph::Graph.from_hash(simple_graph_json)
        result = described_class.layout(graph, algorithm: "box")

        expect(result).to be_a(Elkrb::Graph::Graph)
        expect(result.id).to eq("root")
      end
    end

    context "with invalid algorithm" do
      it "raises an error naming the algorithm that was not found" do
        expect do
          described_class.layout(simple_graph_json, algorithm: "nonexistent")
        end.to raise_error(Elkrb::AlgorithmNotFoundError, /Unknown layout algorithm: nonexistent/)
      end

      it "names the algorithm a graph pins when that one is not found" do
        graph = { id: "r", layoutOptions: { "elk.algorithm" => "nonexistent" } }

        expect { described_class.layout(graph, algorithm: "box") }
          .to raise_error(Elkrb::AlgorithmNotFoundError, /Unknown layout algorithm: nonexistent/)
      end
    end

    context "with a pinned algorithm that differs from the default" do
      let(:pinned_box_json) do
        {
          id: "root",
          layoutOptions: { "elk.algorithm" => "box" },
          children: [{ id: "a", width: 30, height: 30 }, { id: "b", width: 30, height: 30 }],
          edges: [{ id: "e", sources: ["a"], targets: ["b"] }],
        }
      end

      it "runs box for a pin and no call option: b sits right of a with 15 spacing" do
        result = described_class.layout(pinned_box_json, {})
        a, b = result.children

        expect([b.x, b.y]).to eq([a.x + 30 + 15, a.y])
      end

      it "keeps the pin when the call passes a different algorithm" do
        pinned = child_positions(described_class.layout(pinned_box_json, algorithm: "random"))

        expect(pinned).to eq(child_positions(described_class.layout(pinned_box_json, {})))
      end

      it "uses the call option when the graph pins nothing" do
        unpinned = pinned_box_json.merge(layoutOptions: {})

        expect(child_positions(described_class.layout(unpinned, algorithm: "box")))
          .to eq(child_positions(described_class.layout(pinned_box_json, {})))
      end

      it "reads an algorithm from the graph's properties" do
        from_properties = pinned_box_json.merge(layoutOptions: {}, properties: { "algorithm" => "box" })

        expect(child_positions(described_class.layout(from_properties, {})))
          .to eq(child_positions(described_class.layout(pinned_box_json, {})))
      end

      it "reads spacing from the graph's layoutOptions under the ELK id" do
        wide = pinned_box_json.merge(layoutOptions: { "elk.algorithm" => "box", "elk.spacing.nodeNode" => 80 })
        a, b = described_class.layout(wide, {}).children

        expect(b.x - a.x).to eq(30 + 80)
      end
    end

    context "with the spacing call option" do
      it "moves a box layout when spacing_node_node is given" do
        plain = described_class.layout(simple_graph_json, algorithm: "box")
        spaced = described_class.layout(simple_graph_json, algorithm: "box", spacing_node_node: 50)

        expect(spaced.children.map(&:x)).not_to eq(plain.children.map(&:x))
      end

      it "reaches layered under the ELK id, the same as under spacing_node_node" do
        fan_out = lambda do
          { id: "r",
            children: %w[a b c].map { |id| { id: id, width: 100, height: 60 } },
            edges: [{ id: "e1", sources: ["a"], targets: ["b"] }, { id: "e2", sources: ["a"], targets: ["c"] }] }
        end

        by_id = described_class.layout(fan_out.call, "elk.spacing.nodeNode" => 80)
        by_alias = described_class.layout(fan_out.call, spacing_node_node: 80)
        default = described_class.layout(fan_out.call, {})

        expect(by_id.children.map { |n| [n.x, n.y] }).to eq(by_alias.children.map { |n| [n.x, n.y] })
        expect(by_id.children.map { |n| [n.x, n.y] }).not_to eq(default.children.map { |n| [n.x, n.y] })
      end

      it "honours an ELK padding string" do
        graph = { id: "root", children: [{ id: "a", width: 10, height: 10 }] }
        result = described_class.layout(graph, "elk.padding" => "[top=50,left=50,bottom=50,right=50]")

        expect(result.width).to eq(110.0)
      end
    end

    context "with an accepted-but-unhonoured option in the call" do
      let(:graph) { { id: "r", children: [] } }

      it "raises Elkrb::Error naming the option under strict: true" do
        expect { described_class.layout(graph, strict: true, "elk.spacing.edgeNode" => 5) }
          .to raise_error(Elkrb::Error, /elk\.spacing\.edgeNode/)
      end

      it "lays out under strict: true when the call carries only engine flags" do
        expect { described_class.layout(graph, strict: true, hierarchical: true) }
          .not_to raise_error
      end
    end

    context "with an accepted-but-unhonoured option on the graph" do
      let(:graph) { { id: "r", layoutOptions: { "elk.spacing.edgeNode" => 5 }, children: [] } }

      it "raises Elkrb::Error naming the option under strict: true" do
        expect { described_class.layout(graph, strict: true) }
          .to raise_error(Elkrb::Error, /elk\.spacing\.edgeNode/)
      end

      it "raises before any algorithm runs" do
        expect(Elkrb::Layout::AlgorithmRegistry.get("layered"))
          .not_to receive(:new)

        expect { described_class.layout(graph, strict: true) }
          .to raise_error(Elkrb::Error)
      end

      it "warns again when the same graph is laid out a second time" do
        io = StringIO.new
        previous = Elkrb.logger
        Elkrb.logger = Logger.new(io, level: Logger::WARN)

        2.times { described_class.layout(graph, {}) }

        expect(io.string.lines.grep(/elk\.spacing\.edgeNode/).size).to eq(2)
      ensure
        Elkrb.logger = previous
      end

      it "warns and lays out when strict is not given" do
        io = StringIO.new
        previous = Elkrb.logger
        Elkrb.logger = Logger.new(io, level: Logger::WARN)

        described_class.layout(graph, {})

        expect(io.string).to match(/option elk\.spacing\.edgeNode is accepted but not honoured/)
      ensure
        Elkrb.logger = previous
      end
    end

    context "with a graph-carried algorithm" do
      def resolved_algorithm(graph, options = {})
        registry = Elkrb::Layout::AlgorithmRegistry
        allow(registry).to receive(:get).and_call_original
        described_class.layout(graph, options)
        registry
      end

      it "reads the canonical elk.algorithm key when no call-level algorithm is given" do
        graph = { id: "r", layoutOptions: { "elk.algorithm" => "force" } }
        expect(resolved_algorithm(graph)).to have_received(:get).with("force")
      end

      it "reads the algorithm alias when no call-level algorithm is given" do
        graph = { id: "r", layoutOptions: { "algorithm" => "force" } }
        expect(resolved_algorithm(graph)).to have_received(:get).with("force")
      end

      it "reads the org.eclipse.elk. long form when no call-level algorithm is given" do
        graph = { id: "r", layoutOptions: { "org.eclipse.elk.algorithm" => "force" } }
        expect(resolved_algorithm(graph)).to have_received(:get).with("force")
      end

      it "prefers the graph-carried algorithm over a conflicting call-level one" do
        graph = { id: "r", layoutOptions: { "elk.algorithm" => "force" } }
        expect(resolved_algorithm(graph, algorithm: "box"))
          .to have_received(:get).with("force")
      end

      it "still defaults to layered with no algorithm key anywhere" do
        expect(resolved_algorithm({ id: "r" })).to have_received(:get).with("layered")
      end

      it "prefers the canonical key over a conflicting alias, canonical first" do
        graph = {
          id: "r",
          layoutOptions: { "elk.algorithm" => "force", "algorithm" => "box" },
        }
        expect(resolved_algorithm(graph)).to have_received(:get).with("force")
      end

      it "prefers the canonical key over a conflicting alias, alias first" do
        graph = {
          id: "r",
          layoutOptions: { "algorithm" => "box", "elk.algorithm" => "force" },
        }
        expect(resolved_algorithm(graph)).to have_received(:get).with("force")
      end

      it "reads a call-level algorithm given only under the string key" do
        graph = { id: "r" }
        expect(resolved_algorithm(graph, "algorithm" => "force"))
          .to have_received(:get).with("force")
      end

      it "scans past an earlier, unrelated recognized key for the alias" do
        # A layout_options Hash where the algorithm selector is NOT the
        # first entry. Guards the resolver's scan for the alias: a predicate
        # that matched anything Options::Registry recognizes (rather than
        # specifically "elk.algorithm") would return "DOWN" here instead of
        # "force".
        graph = {
          id: "r",
          layoutOptions: { "elk.direction" => "DOWN", "algorithm" => "force" },
        }
        expect(resolved_algorithm(graph)).to have_received(:get).with("force")
      end

      it "resolves the default when options is omitted entirely" do
        # Distinct from every row above: resolved_algorithm's own `options =
        # {}` default means the helper always passes options EXPLICITLY,
        # never exercising layout's OWN default argument. A single
        # positional call is the common real form (Elkrb.layout(json)) and
        # is the only thing that reaches layout's `options = {}` default
        # rather than a caller-supplied one.
        registry = Elkrb::Layout::AlgorithmRegistry
        allow(registry).to receive(:get).and_call_original
        described_class.layout({ id: "r" })
        expect(registry).to have_received(:get).with("layered")
      end

      it "does not raise when layoutOptions carries no algorithm key at all" do
        # Distinct from "no algorithm key anywhere" above: that graph has NO
        # layoutOptions attribute at all. This graph HAS a layoutOptions
        # Hash, just with nothing that resolves to elk.algorithm, so the
        # resolver's scan of it comes back empty.
        graph = { id: "r", layoutOptions: { "elk.direction" => "DOWN" } }
        expect(resolved_algorithm(graph)).to have_received(:get).with("layered")
      end
    end

    context "with a nested graph naming its own algorithm" do
      # A child node that is itself a hierarchical graph with its own
      # layoutOptions was laid out by whichever algorithm was already
      # recursing through the hierarchy, never its own elk.algorithm
      # selector. Root-level graph-carried algorithm selection is a
      # separate, not-yet-merged change (PR #38); these specs pin the fix
      # at the recursion boundary in HierarchicalProcessor only, and so
      # deliberately give the root algorithm through options[:algorithm]
      # or a layoutOptions value that already matches today's "layered"
      # default, so they exercise only the nested selector.
      def algorithm_used_for(_node_id)
        registry = Elkrb::Layout::AlgorithmRegistry
        seen = {}
        allow(registry).to receive(:get).and_wrap_original do |original, name|
          seen[name] = true
          original.call(name)
        end
        yield
        seen
      end

      it "lays out a nested graph's children with the algorithm the nested graph names" do
        graph = {
          id: "root",
          layoutOptions: { "elk.algorithm" => "layered" },
          children: [
            {
              id: "child_graph",
              layoutOptions: { "elk.algorithm" => "box" },
              children: [
                { id: "n1", width: 10.0, height: 10.0 },
                { id: "n2", width: 10.0, height: 10.0 },
              ],
            },
          ],
        }

        used = algorithm_used_for("box") { described_class.layout(graph) }

        expect(used).to have_key("box")
      end

      it "still uses the recursing algorithm when the nested graph names none" do
        graph = {
          id: "root",
          layoutOptions: { "elk.algorithm" => "box" },
          children: [
            {
              id: "child_graph",
              children: [
                { id: "n1", width: 10.0, height: 10.0 },
                { id: "n2", width: 10.0, height: 10.0 },
              ],
            },
          ],
        }

        result = described_class.layout(graph)
        child_node = result.children.first

        # Box arranges children in a grid starting at the origin; both
        # inherited-box positions land on that grid.
        expect(child_node.children.map(&:x)).to all(be >= 0)
      end

      it "resolves the nested alias and long-form spellings the same as the root" do
        %w[algorithm org.eclipse.elk.algorithm].each do |key|
          graph = {
            id: "root",
            layoutOptions: { "elk.algorithm" => "layered" },
            children: [
              {
                id: "child_graph",
                layoutOptions: { key => "box" },
                children: [
                  { id: "n1", width: 10.0, height: 10.0 },
                  { id: "n2", width: 10.0, height: 10.0 },
                ],
              },
            ],
          }

          used = algorithm_used_for("box") { described_class.layout(graph) }

          expect(used).to have_key("box"), "expected \"box\" via #{key.inspect} to run"
        end
      end
    end

    context "with invalid graph input" do
      # A Node is in the Elkrb::Graph:: namespace and is not a Graph, so it
      # separates a class check from a namespace check. Six siblings do that
      # too. Node is the pick because it is the only one of them answering
      # both `children` and `edges`, so it is also the only input that kills a
      # duck-typed guard -- swap it for an Edge or a Label and that goes.
      # The plain rejected types -- nil, String, Array, Integer -- are already
      # covered in spec/elkrb_spec.rb through this same entry point, and a
      # namespace check rejects those just as a class check does, so they are
      # not repeated here. The nil below is there for the ordering, not the type.
      it "raises ArgumentError for a Graph::Node" do
        expect { described_class.layout(Elkrb::Graph::Node.new) }
          .to raise_error(
            ArgumentError,
            "graph must be a Hash or Elkrb::Graph::Graph, " \
            "got Elkrb::Graph::Node",
          )
      end

      # Ordering is asserted by removing the capability, not by watching for
      # its use -- and the removal is DERIVED from the registry's public surface
      # rather than naming a route. Stubbing only :get leaves an implementation
      # that resolves through algorithm_info green while the guard runs second.
      # singleton_methods returns the public routes; the registry's private
      # helpers are unreachable from layout without an explicit send.
      #
      # Keep NotImplementedError. It buys nothing today, because layout carries
      # no rescue and a StandardError sentinel behaves identically. It becomes
      # the only thing holding this example up the moment layout gains a
      # `rescue StandardError`, which would swallow a StandardError sentinel
      # and leave this passing while asserting nothing.
      it "rejects the graph before the algorithm is resolved" do
        registry = Elkrb::Layout::AlgorithmRegistry
        (registry.singleton_methods - Object.singleton_methods).each do |route|
          allow(registry).to receive(route)
            .and_raise(NotImplementedError, "algorithm resolution must not run")
        end

        expect { described_class.layout(nil, algorithm: "layered") }
          .to raise_error(
            ArgumentError,
            "graph must be a Hash or Elkrb::Graph::Graph, got NilClass",
          )
      end
    end

    context "with a node missing width and height" do
      it "treats missing size as 0 and does not raise" do
        graph = { id: "r", children: [{ id: "a" }] }

        expect { described_class.layout(graph, algorithm: "layered") }
          .not_to raise_error
      end

      it "does not raise for box" do
        graph = { id: "r", children: [{ id: "a" }, { id: "b" }] }

        expect { described_class.layout(graph, algorithm: "box") }
          .not_to raise_error
      end

      it "does not raise for random" do
        graph = { id: "r", children: [{ id: "a" }, { id: "b" }] }

        expect { described_class.layout(graph, algorithm: "random") }
          .not_to raise_error
      end

      it "does not raise for force" do
        graph = { id: "r", children: [{ id: "a" }, { id: "b" }] }

        expect { described_class.layout(graph, algorithm: "force") }
          .not_to raise_error
      end

      it "does not raise for stress" do
        graph = { id: "r", children: [{ id: "a" }, { id: "b" }] }

        expect { described_class.layout(graph, algorithm: "stress") }
          .not_to raise_error
      end
    end

    context "with a size-less compound (container) node" do
      it "does not raise" do
        graph = {
          id: "r",
          children: [
            { id: "a", children: [{ id: "a1", width: 5.0, height: 5.0 }] },
          ],
        }

        expect do
          described_class.layout(
            graph, algorithm: "layered", hierarchical: true
          )
        end.not_to raise_error
      end
    end

    context "with an empty root graph (no children/edges keys)" do
      Elkrb::Layout::AlgorithmRegistry.available_algorithms.each do |algo|
        it "does not raise for #{algo}" do
          expect { described_class.layout({ id: "root" }, algorithm: algo) }
            .not_to raise_error
        end
      end
    end

    context "with children but no edges key, using disco" do
      it "does not raise" do
        graph = { id: "r", children: [{ id: "a", width: 10, height: 10 }] }

        expect { described_class.layout(graph, algorithm: "disco") }
          .not_to raise_error
      end
    end
  end
end

RSpec.describe "fixed layout element options" do
  it "applies elk.position without translating the node" do
    graph = Elkrb.layout(
      {
        id: "root",
        children: [
          {
            id: "a", width: 30, height: 30,
            layoutOptions: { "elk.position" => "(40,50)" }
          },
        ],
      },
      algorithm: "fixed",
    )

    expect([graph.children.first.x, graph.children.first.y])
      .to eq([40.0, 50.0])
  end

  it "applies elk.bendPoints to an edge" do
    graph = Elkrb.layout(
      {
        id: "root",
        children: [
          { id: "a", x: 0, y: 0, width: 10, height: 10 },
          { id: "b", x: 50, y: 0, width: 10, height: 10 },
        ],
        edges: [
          {
            id: "e", sources: ["a"], targets: ["b"],
            layoutOptions: { "elk.bendPoints" => "(10,20; 30,40)" }
          },
        ],
      },
      algorithm: "fixed",
    )

    bends = graph.edges.first.sections.first.bend_points
    expect(bends.map { |point| [point.x, point.y] })
      .to eq([[10.0, 20.0], [30.0, 40.0]])
  end
end
