# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::NodeIndex do
  def graph_from(hash)
    Elkrb::Graph::Graph.from_hash(hash)
  end

  describe ".build" do
    it "maps node ids to their node" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          { "id" => "a", "width" => 10, "height" => 10 },
          { "id" => "b", "width" => 10, "height" => 10 },
        ],
      )

      index = described_class.build(graph)

      expect(index.node("a").id).to eq("a")
      expect(index.node("b").id).to eq("b")
    end

    it "maps a port id to its owning node" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "a_p1" }],
          },
        ],
      )

      index = described_class.build(graph)

      expect(index.node("a_p1").id).to eq("a")
    end

    it "returns nil for an id not present at this level" do
      graph = graph_from("id" => "r", "children" => [])

      index = described_class.build(graph)

      expect(index.node("missing")).to be_nil
    end

    it "raises Elkrb::ValidationError on a duplicate node id" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          { "id" => "a", "width" => 10, "height" => 10 },
          { "id" => "a", "width" => 10, "height" => 10 },
        ],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /a/)
    end

    it "raises Elkrb::ValidationError on a duplicate port id" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "p1" }],
          },
          {
            "id" => "b",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "p1" }],
          },
        ],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /p1/)
    end

    it "raises Elkrb::ValidationError when a node id collides with " \
       "another node's port id" do
      # Node and port ids share one namespace at a level (D4) — this
      # proves that holds across kinds, not just node-node/port-port.
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "shared" }],
          },
          { "id" => "shared", "width" => 10, "height" => 10 },
        ],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /shared/)
    end

    it "raises Elkrb::ValidationError for a node without an id" do
      graph = Elkrb::Graph::Graph.new(
        children: [Elkrb::Graph::Node.new(width: 10, height: 10)],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /node without id/)
    end

    it "raises Elkrb::ValidationError for a port without an id" do
      graph = Elkrb::Graph::Graph.new(
        children: [
          Elkrb::Graph::Node.new(
            id: "a", width: 10, height: 10,
            ports: [Elkrb::Graph::Port.new],
          ),
        ],
      )

      expect { described_class.build(graph) }
        .to raise_error(Elkrb::ValidationError, /port without id/)
    end

    it "allows the same id to repeat at a different level" do
      parent = graph_from(
        "id" => "r",
        "children" => [{ "id" => "a", "width" => 10, "height" => 10 }],
      )
      child_graph = Elkrb::Graph::Graph.new(
        children: [Elkrb::Graph::Node.new(id: "a", width: 5, height: 5)],
      )

      expect(described_class.build(parent).node("a").width).to eq(10)
      expect(described_class.build(child_graph).node("a").width).to eq(5)
    end

    it "does not recurse into a node's own nested children" do
      # A version of NodeIndex that (incorrectly) walked node.children
      # would see the id "a" twice within ONE build call here and raise
      # a duplicate-id error; this proves it stays level-scoped.
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "children" => [
              { "id" => "a", "width" => 5, "height" => 5 },
            ],
          },
        ],
      )

      index = described_class.build(graph)

      expect(index.node("a").width).to eq(10)
    end
  end

  describe "#edges" do
    it "takes the graph's own edges and a leaf child's" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a", "width" => 10, "height" => 10,
            "ports" => [{ "id" => "p1" }, { "id" => "p2" }],
            "edges" => [
              { "id" => "loop", "sources" => ["p1"], "targets" => ["p2"] },
            ]
          },
          { "id" => "b", "width" => 10, "height" => 10 },
        ],
        "edges" => [{ "id" => "ab", "sources" => ["a"], "targets" => ["b"] }],
      )

      expect(described_class.build(graph).edges.map(&:id)).to eq(%w[ab loop])
    end

    it "leaves a hierarchical child's edges to that child's own level" do
      # "x" and "y" name c's children AND a's ports. Ids are unique
      # only within a level, so reading c's edge here would alias its
      # endpoints onto "a".
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a", "width" => 10, "height" => 10,
            "ports" => [{ "id" => "x" }, { "id" => "y" }]
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

      expect(described_class.build(graph).edges).to eq([])
    end
  end

  describe "#edges_on" do
    it "returns a leaf child's own edges" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a", "width" => 10, "height" => 10,
            "ports" => [{ "id" => "p1" }, { "id" => "p2" }],
            "edges" => [
              { "id" => "loop", "sources" => ["p1"], "targets" => ["p2"] },
            ]
          },
        ],
      )
      index = described_class.build(graph)

      expect(index.edges_on(graph.children.first).map(&:id)).to eq(["loop"])
    end

    it "returns nothing for a hierarchical child" do
      graph = graph_from(
        "id" => "r",
        "children" => [
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
      )
      index = described_class.build(graph)

      expect(index.edges_on(graph.children.first)).to eq([])
    end
  end

  describe "#endpoint_nodes" do
    it "resolves a mix of node and port ids, dropping unresolved ones" do
      graph = graph_from(
        "id" => "r",
        "children" => [
          {
            "id" => "a",
            "width" => 10,
            "height" => 10,
            "ports" => [{ "id" => "a_p1" }],
          },
          { "id" => "b", "width" => 10, "height" => 10 },
        ],
      )
      index = described_class.build(graph)

      expect(index.endpoint_nodes(%w[a_p1 b missing]).map(&:id))
        .to eq(%w[a b])
    end

    it "returns an empty array for nil" do
      index = described_class.build(graph_from("id" => "r", "children" => []))

      expect(index.endpoint_nodes(nil)).to eq([])
    end
  end
end

RSpec.describe "EdgeRouter node_map contract" do
  # A plain {id => node} Hash was the documented node_map before NodeIndex
  # existed. Both public entry points still have to accept one.
  let(:router) { Class.new { include Elkrb::Layout::EdgeRouter }.new }

  def fresh
    a = Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 10, height: 10)
    b = Elkrb::Graph::Node.new(id: "b", x: 50, y: 50, width: 10, height: 10)
    edge = Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"])
    [Elkrb::Graph::Graph.new(id: "r", children: [a, b], edges: [edge]), edge, { "a" => a, "b" => b }]
  end

  it "routes a single edge given a plain Hash" do
    graph, edge, hash = fresh

    router.route_edge(edge, hash, graph)

    expect(edge.sections&.size).to eq(1)
  end

  it "routes a whole graph given a plain Hash" do
    graph, edge, hash = fresh

    router.route_edges(graph, hash)

    expect(edge.sections&.size).to eq(1)
  end

  it "resolves a port-id endpoint through a node-keyed Hash" do
    a = Elkrb::Graph::Node.new(id: "a", x: 0, y: 0, width: 10, height: 10,
                               ports: [Elkrb::Graph::Port.new(id: "ap", x: 0, y: 0, width: 2, height: 2)])
    b = Elkrb::Graph::Node.new(id: "b", x: 50, y: 50, width: 10, height: 10,
                               ports: [Elkrb::Graph::Port.new(id: "bp", x: 0, y: 0, width: 2, height: 2)])
    edge = Elkrb::Graph::Edge.new(id: "e", sources: ["ap"], targets: ["bp"])
    graph = Elkrb::Graph::Graph.new(id: "r", children: [a, b], edges: [edge])

    router.route_edges(graph, { "a" => a, "b" => b })

    expect(edge.sections&.size).to eq(1)
  end

  it "still builds its own NodeIndex when no map is given" do
    graph, edge, = fresh

    router.route_edges(graph)

    expect(edge.sections&.size).to eq(1)
  end
end

RSpec.describe "cross-hierarchy edges owned by the graph" do
  # c1 is nested under p1. The root declares c1 -> p2, which hierarchical
  # layout explicitly supports. Resolving only this level drops c1, takes the
  # edge out of the topology, and flattens p1 and p2 into one layer.
  let(:graph) do
    {
      "id" => "root",
      "children" => [
        { "id" => "p1", "width" => 40, "height" => 40,
          "children" => [{ "id" => "c1", "width" => 10, "height" => 10 }] },
        { "id" => "p2", "width" => 40, "height" => 40 },
      ],
      "edges" => [{ "id" => "e1", "sources" => ["c1"], "targets" => ["p2"] }],
    }
  end

  it "keeps a nested source in the layered topology by projecting it onto its ancestor" do
    by_id = Elkrb.layout(graph, algorithm: "layered").children.to_h { |node| [node.id, node] }

    expect(by_id["p2"].y).to be > by_id["p1"].y
  end
end
