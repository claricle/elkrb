# frozen_string_literal: true

require_relative "preserve_ids_and_endpoints"

RSpec.describe "preserve_ids_and_endpoints" do
  let(:input_hash) do
    {
      "id" => "root",
      "children" => [
        { "id" => "a", "width" => 30, "height" => 30 },
        { "id" => "b", "width" => 30, "height" => 30 },
      ],
      "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }],
    }
  end

  it "passes when every node and edge survives layout with unchanged " \
     "endpoints" do
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})

    expect(result).to preserve_ids_and_endpoints(input_hash)
  end

  # The root's own id is the one id in the graph that sits in no
  # children/edges collection, so nothing was matching it: renaming
  # "root" left this matcher returning true.
  it "fails when the root graph's own id changed" do
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})
    result.id = "renamed"

    expect(result).not_to preserve_ids_and_endpoints(input_hash)
  end

  it "fails when a compound node's own id changed" do
    nested = { "id" => "root",
               "children" => [{ "id" => "p", "children" => [{ "id" => "c" }] }],
               "edges" => [] }
    graph = Elkrb::Graph::Graph.from_hash(nested)
    result = Elkrb.layout(graph, {})
    result.children.first.id = "renamed"

    expect(result).not_to preserve_ids_and_endpoints(nested)
  end

  it "fails when an edge's endpoints changed" do
    graph = Elkrb::Graph::Graph.from_hash(input_hash)
    result = Elkrb.layout(graph, {})
    result.edges.first.sources, result.edges.first.targets =
      result.edges.first.targets, result.edges.first.sources

    expect(result).not_to preserve_ids_and_endpoints(input_hash)
  end

  # `Elkrb.layout` documents and accepts a Symbol-keyed Hash directly (see
  # its own @example in lib/elkrb.rb). Every String-keyed lookup in this
  # matcher used to read nil from a Symbol-keyed input_hash, which is
  # indistinguishable from "not declared" -- a genuinely preserved node
  # then looked like one the layout added.
  it "passes a Symbol-keyed input_hash, unchanged" do
    symbol_input = { id: "root",
                     children: [{ id: "n1", width: 40, height: 20 }],
                     edges: [] }
    graph = Elkrb::Graph::Graph.from_hash(symbol_input)
    result = Elkrb.layout(graph, {})

    expect(result).to preserve_ids_and_endpoints(symbol_input)
  end

  it "still fails a Symbol-keyed input_hash when a node genuinely vanished" do
    symbol_input = { id: "root",
                     children: [{ id: "n1", width: 40, height: 20 }],
                     edges: [] }
    result = Elkrb::Graph::Graph.new(id: "root", children: [], edges: [])

    expect(result).not_to preserve_ids_and_endpoints(symbol_input)
  end

  # The legacy elkjs single-endpoint keys (edge.rb's `source`/`target`,
  # read-only, merged into `sources`/`targets`). This matcher used to read
  # `input_edge["sources"]` directly, which is nil for a legacy edge even
  # though the layout genuinely preserved its endpoint.
  it "passes an edge declared with legacy source/target keys" do
    legacy_input = {
      "id" => "root",
      "children" => [
        { "id" => "a", "width" => 30, "height" => 30 },
        { "id" => "b", "width" => 30, "height" => 30 },
      ],
      "edges" => [{ "id" => "e1", "source" => "a", "target" => "b" }],
    }
    graph = Elkrb::Graph::Graph.from_hash(legacy_input)
    result = Elkrb.layout(graph, {})

    expect(result).to preserve_ids_and_endpoints(legacy_input)
  end

  it "still fails a legacy-keyed edge whose endpoint genuinely changed" do
    legacy_input = {
      "id" => "root",
      "children" => [
        { "id" => "a", "width" => 30, "height" => 30 },
        { "id" => "b", "width" => 30, "height" => 30 },
      ],
      "edges" => [{ "id" => "e1", "source" => "a", "target" => "b" }],
    }
    graph = Elkrb::Graph::Graph.from_hash(legacy_input)
    result = Elkrb.layout(graph, {})
    result.edges.first.sources, result.edges.first.targets =
      result.edges.first.targets, result.edges.first.sources

    expect(result).not_to preserve_ids_and_endpoints(legacy_input)
  end
end

RSpec.describe "preserve_ids_and_endpoints duplicate detection" do
  # Indexing children/edges by id keeps only the last entry per id, so a
  # result that duplicated `a` and `e1` passed as long as the final copy
  # still matched the input.
  let(:input_hash) do
    {
      "id" => "root",
      "children" => [
        { "id" => "a", "width" => 30, "height" => 30 },
        { "id" => "b", "width" => 30, "height" => 30 },
      ],
      "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }],
    }
  end

  let(:result) { Elkrb.layout(Elkrb::Graph::Graph.from_hash(input_hash), {}) }

  it "fails when a node id appears twice in the result" do
    result.children << result.children.first

    expect(result).not_to preserve_ids_and_endpoints(input_hash)
  end

  it "fails when an edge id appears twice in the result" do
    result.edges << result.edges.first

    expect(result).not_to preserve_ids_and_endpoints(input_hash)
  end

  it "fails when a duplicate is nested inside a compound child" do
    nested_input = {
      "id" => "root",
      "children" => [
        { "id" => "p",
          "children" => [{ "id" => "c1", "width" => 30, "height" => 30 }] },
      ],
    }
    nested = Elkrb.layout(Elkrb::Graph::Graph.from_hash(nested_input), {})
    compound = nested.children.first
    compound.children << compound.children.first

    expect(nested).not_to preserve_ids_and_endpoints(nested_input)
  end
  # A one-way subset test cannot see either of these. Both passed before the
  # matcher compared the id SEQUENCE.
  describe "differences a subset check cannot see" do
    let(:input) do
      { "id" => "root",
        "children" => [{ "id" => "a" }, { "id" => "b" }],
        "edges" => [] }
    end

    def graph_with(ids)
      graph = Elkrb::Graph::Graph.new
      graph.children = ids.map { |id| Elkrb::Graph::Node.new(id: id) }
      graph.edges = []
      graph
    end

    it "rejects a node the layout added" do
      expect(graph_with(%w[a b extra]))
        .not_to preserve_ids_and_endpoints(input)
    end

    # Edges, not just nodes. Both reviewers found this independently: the
    # node half was closed and the edge half was left a one-way lookup, so an
    # added edge passed.
    it "rejects an edge the layout added" do
      with_edge = { "id" => "root",
                    "children" => [{ "id" => "a" }, { "id" => "b" }],
                    "edges" => [{ "id" => "e", "sources" => ["a"],
                                  "targets" => ["b"] }] }
      graph = Elkrb::Graph::Graph.new
      graph.children = %w[a b].map { |id| Elkrb::Graph::Node.new(id: id) }
      graph.edges = [
        Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"]),
        Elkrb::Graph::Edge.new(id: "phantom", sources: ["b"], targets: ["a"]),
      ]

      expect(graph).not_to preserve_ids_and_endpoints(with_edge)
    end

    it "rejects a reordered sequence" do
      expect(graph_with(%w[b a])).not_to preserve_ids_and_endpoints(input)
    end

    it "still accepts the unchanged sequence" do
      expect(graph_with(%w[a b])).to preserve_ids_and_endpoints(input)
    end
  end
end
