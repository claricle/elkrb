# frozen_string_literal: true

require "spec_helper"
require "open3"
require_relative "../../../lib/elkrb/parsers/elkt_parser"
require_relative "../../../lib/elkrb/serializers/elkt_serializer"
require_relative "../../../lib/elkrb/serializers/dot_serializer"

RSpec.describe "S22 serializers" do
  describe Elkrb::Serializers::ElktSerializer do
    subject(:serializer) { described_class.new }

    it "preserves edge IDs, hyperedges, labels, options, and port geometry" do
      graph = {
        id: "root",
        children: [
          {
            id: "node-1", width: 100, height: 60,
            layoutOptions: { "elk.direction" => "RIGHT" },
            ports: [{
              id: "port.1", x: 2, y: 3, width: 4, height: 5,
              layoutOptions: { "elk.port.side" => "WEST" }
            }]
          },
          { id: "node_2", width: 40, height: 40 },
          { id: "node_3", width: 40, height: 40 },
        ],
        edges: [{
          id: "A:B", sources: ["port.1", "node_2"], targets: ["node_3"],
          layoutOptions: { "elk.direction" => "RIGHT" },
          labels: [{ text: "say \"hi\" \\ now" }]
        }],
      }

      elkt = serializer.serialize(graph)
      parsed = Elkrb::Parsers::ElktParser.parse(elkt)

      expect(elkt).to include(
        "node node_1",
        "port port_1",
        "layout [ position: 2, 3  size: 4, 5 ]",
        "edge A_B: node_1.port_1, node_2 -> node_3",
        'label "say \\"hi\\" \\\\ now"',
      )
      expect(elkt).not_to include("properties:")
      expect(parsed[:edges].first).to include(
        id: "A_B", sources: %w[port_1 node_2], targets: ["node_3"],
      )
      expect(parsed[:edges].first[:layoutOptions])
        .to include("elk.direction" => "RIGHT")
      expect(parsed[:edges].first[:labels].first[:text])
        .to eq('say "hi" \\ now')
    end

    it "keeps valid IDs and makes colliding sanitized IDs distinct" do
      graph = {
        id: "root",
        children: [
          { id: "a_b" },
          { id: "a-b" },
          { id: "a.b" },
        ],
        edges: [],
      }

      result = serializer.serialize(graph)

      expect(result.lines.grep(/^node /).map { |line| line.split[1] })
        .to eq(%w[a_b a_b_2 a_b_3])
    end

    it "always writes explicit edge IDs including e-number IDs" do
      graph = {
        id: "root",
        children: [{ id: "a" }, { id: "b" }],
        edges: [{ id: "e1", sources: ["a"], targets: ["b"] }],
      }

      expect(serializer.serialize(graph)).to include("edge e1: a -> b")
    end

    it "round-trips the simple fixture without changing edge IDs" do
      graph = Elkrb::Graph::Graph.from_json(
        File.read("spec/fixtures/simple_graph.json"),
      )

      parsed = Elkrb::Parsers::ElktParser.parse(serializer.serialize(graph))
      parsed_edges = parsed[:edges].map do |edge|
        edge.values_at(:id, :sources, :targets)
      end

      expect(parsed_edges)
        .to eq(graph.edges.map { |edge| [edge.id, edge.sources, edge.targets] })
    end

    it "round-trips root labels and ports through the shared ID map" do
      graph = Elkrb::Graph::Graph.from_hash(
        id: "root",
        labels: [{ id: "root-label", text: "Title" }],
        ports: [{
          id: "root.port",
          labels: [{ id: "port-label", text: "Port label" }],
        }],
      )

      elkt = serializer.serialize(graph)
      parsed = Elkrb::Parsers::ElktParser.parse(elkt)

      expect(elkt).to include('label root_label: "Title"', "port root_port")
      expect(parsed.dig(:labels, 0)).to include(id: "root_label", text: "Title")
      expect(parsed.dig(:ports, 0, :id)).to eq("root_port")
      expect(parsed.dig(:ports, 0, :labels, 0))
        .to include(id: "port_label", text: "Port label")
    end

    it "round-trips complex edges through one deterministic ID map" do
      graph = Elkrb::Graph::Graph.from_json(
        File.read("spec/fixtures/elkjs_bug7_complex.json"),
      )
      expected_id = lambda do |id|
        sanitized = id.gsub(/\W/, "_")
        sanitized.match?(/\A[A-Za-z_]/) ? sanitized : "_#{sanitized}"
      end

      parsed = Elkrb::Parsers::ElktParser.parse(serializer.serialize(graph))

      expected_edges = graph.edges.map do |edge|
        [
          expected_id.call(edge.id),
          edge.sources.map(&expected_id),
          edge.targets.map(&expected_id),
        ]
      end
      parsed_edges = parsed[:edges].map do |edge|
        edge.values_at(:id, :sources, :targets)
      end

      expect(parsed_edges).to eq(expected_edges)
    end
  end

  describe Elkrb::Serializers::DotSerializer do
    subject(:serializer) { described_class.new }

    def graph_model(document)
      Elkrb::Graph::Graph.from_json(JSON.generate(document))
    end

    it "quotes distinct DOT IDs and produces input Graphviz accepts" do
      graph = graph_model(
        id: "root",
        children: [
          { id: "1st", width: 40, height: 40 },
          { id: "a-b", width: 40, height: 40 },
          { id: "a.b", width: 40, height: 40 },
          { id: "node", width: 40, height: 40 },
        ],
        edges: [{ id: "e", sources: ["a-b"], targets: ["a.b"] }],
      )

      dot = serializer.serialize(graph)
      _stdout, stderr, status = Open3.capture3("dot", "-Tcanon",
                                               stdin_data: dot)

      expect(status).to be_success, stderr
      expect(dot).to include('"1st"', '"a-b" -> "a.b"', '"node"')
    end

    it "emits nested and port edges once without phantom port nodes" do
      graph = graph_model(
        id: "root",
        children: [
          {
            id: "parent",
            children: [
              { id: "n1", width: 40, height: 40, ports: [{ id: "p1" }] },
              { id: "n2", width: 40, height: 40, ports: [{ id: "p2" }] },
            ],
            edges: [
              { id: "inner", sources: ["p1"], targets: ["p2"] },
            ],
          },
        ],
        edges: [],
      )

      dot = serializer.serialize(graph)
      plain, stderr, status = Open3.capture3("dot", "-Tplain",
                                             stdin_data: dot)

      expect(status).to be_success, stderr
      expect(dot.scan("n1:p1 -> n2:p2").length).to eq(1)
      expect(plain.lines.grep(/^node /).length).to eq(2)
    end

    it "routes compound endpoints through representative children" do
      graph = graph_model(
        id: "root",
        children: [
          { id: "group", children: [{ id: "inside", width: 40, height: 40 }] },
          { id: "outside", width: 40, height: 40 },
        ],
        edges: [{ id: "e", sources: ["group"], targets: ["outside"] }],
      )

      dot = serializer.serialize(graph)

      expect(dot).to include("compound=true")
      expect(dot).to match(/inside -> outside \[ltail=cluster_\d+\]/)
    end

    it "emits positions only for neato and keeps label line breaks active" do
      graph = graph_model(
        id: "root",
        children: [{
          id: "n", x: 1, y: 2, width: 40, height: 40,
          labels: [{ text: "First" }, { text: "Second" }]
        }],
        edges: [],
      )

      dot = serializer.serialize(graph)
      neato = serializer.serialize(graph, engine: "neato")

      expect(dot).not_to include("pos=")
      expect(neato).to include('pos="21.0,22.0!"')
      expect(dot).to include('label="First\nSecond"')
      expect(dot).not_to include("First\\\\\\\\nSecond")
    end

    it "reads long-form direction through the option resolver" do
      graph = graph_model(
        id: "root",
        layoutOptions: { "org.eclipse.elk.direction" => "RIGHT" },
        children: [], edges: []
      )

      expect(serializer.serialize(graph)).to include("rankdir=LR")
    end
  end
end
