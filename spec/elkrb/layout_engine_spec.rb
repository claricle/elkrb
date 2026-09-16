# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::LayoutEngine do
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

        # Nodes should be shifted by padding but relative positions maintained
        n1 = result.find_node("n1")
        n2 = result.find_node("n2")
        n3 = result.find_node("n3")

        # Check that relative positions are maintained (n2.x - n1.x should equal 40)
        expect(n2.x - n1.x).to eq(40)
        expect(n3.x - n2.x).to eq(40)
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
        end.to raise_error(Elkrb::Error, /Unknown layout algorithm: nonexistent/)
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

      it "prefers the call-level algorithm over a conflicting graph-carried one" do
        graph = { id: "r", layoutOptions: { "elk.algorithm" => "force" } }
        expect(resolved_algorithm(graph, algorithm: "box"))
          .to have_received(:get).with("box")
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
        # first entry. Guards aliased_graph_algorithm's actual scan: a
        # predicate that matched anything Options::Registry recognizes
        # (rather than specifically "elk.algorithm"), or ignored the block
        # entirely (Hash#first ignores a block without raising), would both
        # return "DOWN" here instead of "force".
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
        # layoutOptions attribute at all (Graph.from_hash gives it a nil
        # layout_options, caught by graph_algorithm's own nil guard
        # before aliased_graph_algorithm is ever called). This graph HAS a
        # layoutOptions Hash, just with nothing that resolves to
        # elk.algorithm, so it is aliased_graph_algorithm's #find that comes
        # back empty -- guarding the &.last against a bare .last on nil.
        graph = { id: "r", layoutOptions: { "elk.direction" => "DOWN" } }
        expect(resolved_algorithm(graph)).to have_received(:get).with("layered")
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
