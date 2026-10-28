# frozen_string_literal: true

require "spec_helper"
require "open3"
require_relative "../../../lib/elkrb/serializers/dot_serializer"

RSpec.describe Elkrb::Serializers::DotSerializer do
  let(:serializer) { described_class.new }

  describe "#serialize" do
    context "with a simple graph" do
      let(:graph) do
        Elkrb::Graph::Graph.new(
          id: "root",
          width: 500,
          height: 300,
        )
      end

      it "generates valid DOT format" do
        result = serializer.serialize(graph)

        expect(result).to include("digraph G")
        expect(result).to include("{")
        expect(result).to include("}")
      end

      it "includes graph size attributes" do
        result = serializer.serialize(graph)

        # Size should be in inches (500/72, 300/72)
        expect(result).to include("size=")
      end

      it "supports undirected graphs" do
        result = serializer.serialize(graph, directed: false)

        expect(result).to include("graph G")
        expect(result).not_to include("digraph")
      end

      it "supports custom graph name" do
        result = serializer.serialize(graph, graph_name: "MyGraph")

        expect(result).to include("digraph MyGraph")
      end
    end

    context "with nodes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          g.children << Elkrb::Graph::Node.new(
            id: "node1",
            width: 100,
            height: 50,
          )
          g.children << Elkrb::Graph::Node.new(
            id: "node2",
            width: 100,
            height: 50,
          )
        end
      end

      it "includes node declarations" do
        result = serializer.serialize(graph)

        expect(result).to include("node1")
        expect(result).to include("node2")
      end

      it "includes node size attributes" do
        result = serializer.serialize(graph)

        # Sizes should be in inches
        expect(result).to include("width=")
        expect(result).to include("height=")
        expect(result).to include("fixedsize=true")
      end

      it "sanitizes node IDs with special characters" do
        graph.children << Elkrb::Graph::Node.new(
          id: "node-with-dashes",
          width: 100,
          height: 50,
        )

        result = serializer.serialize(graph)

        expect(result).to include('"node-with-dashes"')
      end

      it "handles node IDs starting with digits" do
        graph.children << Elkrb::Graph::Node.new(
          id: "123node",
          width: 100,
          height: 50,
        )

        result = serializer.serialize(graph)

        expect(result).to include('"123node"')
      end
    end

    context "with node labels" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          node = Elkrb::Graph::Node.new(
            id: "node1",
            width: 100,
            height: 50,
          )
          node.labels = [
            Elkrb::Graph::Label.new(text: "Hello World"),
          ]
          g.children << node
        end
      end

      it "includes label attribute" do
        result = serializer.serialize(graph)

        expect(result).to include('label="Hello World"')
      end

      it "handles multiple labels with newlines" do
        graph.children.first.labels << Elkrb::Graph::Label.new(
          text: "Second Line",
        )

        result = serializer.serialize(graph)

        expect(result).to include('label="Hello World\\nSecond Line"')
      end

      it "escapes special characters in labels" do
        graph.children.first.labels = [
          Elkrb::Graph::Label.new(text: 'Text with "quotes"'),
        ]

        result = serializer.serialize(graph)

        expect(result).to include('label="Text with \\"quotes\\""')
      end
    end

    context "with edges" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          g.children << Elkrb::Graph::Node.new(
            id: "node1",
            width: 100,
            height: 50,
          )
          g.children << Elkrb::Graph::Node.new(
            id: "node2",
            width: 100,
            height: 50,
          )
          g.edges << Elkrb::Graph::Edge.new(
            id: "edge1",
            sources: ["node1"],
            targets: ["node2"],
          )
        end
      end

      it "includes edge declarations" do
        result = serializer.serialize(graph)

        expect(result).to include("node1 -> node2")
      end

      it "uses -- for undirected graphs" do
        result = serializer.serialize(graph, directed: false)

        expect(result).to include("node1 -- node2")
      end

      it "includes edge labels" do
        graph.edges.first.labels = [
          Elkrb::Graph::Label.new(text: "Edge Label"),
        ]

        result = serializer.serialize(graph)

        expect(result).to include('label="Edge Label"')
      end

      it "resolves repeated port ids in the edge container's scope" do
        outer = Elkrb::Graph::Node.new(
          id: "outer", ports: [Elkrb::Graph::Port.new(id: "p")],
        )
        inner = Elkrb::Graph::Node.new(
          id: "inner", ports: [Elkrb::Graph::Port.new(id: "p")],
        )
        group = Elkrb::Graph::Node.new(
          id: "group", children: [inner, Elkrb::Graph::Node.new(id: "sink")],
          edges: [Elkrb::Graph::Edge.new(
            id: "nested", sources: ["p"], targets: ["sink"],
          )]
        )
        scoped = Elkrb::Graph::Graph.new(
          id: "root",
          children: [outer, group, Elkrb::Graph::Node.new(id: "outside")],
          edges: [Elkrb::Graph::Edge.new(
            id: "root_edge", sources: ["p"], targets: ["outside"],
          )],
        )

        result = serializer.serialize(scoped)

        expect(result).to include(
          "inner:p -> sink",
          "outer:p -> outside",
        )
      end

      it "falls back to a port owner in an enclosing scope" do
        outer = Elkrb::Graph::Node.new(
          id: "outer", ports: [Elkrb::Graph::Port.new(id: "q")],
        )
        group = Elkrb::Graph::Node.new(
          id: "group", children: [Elkrb::Graph::Node.new(id: "sink")],
          edges: [Elkrb::Graph::Edge.new(
            id: "nested", sources: ["q"], targets: ["sink"],
          )]
        )
        scoped = Elkrb::Graph::Graph.new(
          id: "root", children: [outer, group], edges: [],
        )

        expect(serializer.serialize(scoped))
          .to include("outer:q -> sink")
      end

      it "declares ports owned by hierarchical nodes on their representative" do
        leaf = Elkrb::Graph::Node.new(
          id: "leaf", width: 72, height: 36,
          ports: [Elkrb::Graph::Port.new(id: "p")]
        )
        group = Elkrb::Graph::Node.new(
          id: "group",
          children: [leaf, Elkrb::Graph::Node.new(id: "sink")],
          ports: [Elkrb::Graph::Port.new(id: "p")],
          edges: [Elkrb::Graph::Edge.new(
            id: "inner", sources: ["p"], targets: ["sink"],
          )],
        )
        graph = Elkrb::Graph::Graph.new(
          id: "root",
          children: [group, Elkrb::Graph::Node.new(id: "target")],
          edges: [Elkrb::Graph::Edge.new(
            id: "e", sources: ["p"], targets: ["target"],
          )],
        )

        dot = serializer.serialize(graph)
        plain, stderr, status = Open3.capture3(
          "dot", "-Tplain", stdin_data: dot
        )

        expect(dot).to include(
          'PORT="p"', 'PORT="port1"',
          "leaf:p -> target [ltail=cluster_0]",
          "leaf:port1 -> sink"
        )
        expect(status).to be_success, stderr
        expect(stderr).to be_empty
        expect(plain.lines.grep(/^node /).length).to eq(3)
        leaf_line = plain.lines.find { |line| line.start_with?("node leaf ") }
        expect(leaf_line.split.values_at(4, 5).map(&:to_f))
          .to contain_exactly(a_value_within(0.01).of(1.0),
                              a_value_within(0.01).of(0.5))
      rescue Errno::ENOENT
        skip "Graphviz is not installed; skipping external DOT acceptance"
      end

      it "resolves deeply nested hierarchical ports without phantom nodes" do
        leaf = Elkrb::Graph::Node.new(id: "leaf", width: 72, height: 36)
        inner = Elkrb::Graph::Node.new(
          id: "inner", children: [leaf],
          ports: [Elkrb::Graph::Port.new(id: "p")]
        )
        outer = Elkrb::Graph::Node.new(id: "outer", children: [inner])
        graph = Elkrb::Graph::Graph.new(
          id: "root", children: [outer, Elkrb::Graph::Node.new(id: "outside")],
          edges: [Elkrb::Graph::Edge.new(
            id: "e", sources: ["p"], targets: ["outside"],
          )]
        )

        dot = serializer.serialize(graph)
        plain, stderr, status = Open3.capture3(
          "dot", "-Tplain", stdin_data: dot
        )

        expect(dot).to include("leaf:p -> outside [ltail=cluster_1]")
        expect(status).to be_success, stderr
        expect(stderr).to be_empty
        expect(plain.lines.grep(/^node /).length).to eq(2)
      rescue Errno::ENOENT
        skip "Graphviz is not installed; skipping external DOT acceptance"
      end

      it "prefers direct child ports over earlier descendant ports" do
        nested = Elkrb::Graph::Node.new(
          id: "group",
          children: [Elkrb::Graph::Node.new(
            id: "inner", ports: [Elkrb::Graph::Port.new(id: "p")],
          )],
        )
        direct = Elkrb::Graph::Node.new(
          id: "direct", ports: [Elkrb::Graph::Port.new(id: "p")],
        )
        graph = Elkrb::Graph::Graph.new(
          id: "root",
          children: [nested, direct, Elkrb::Graph::Node.new(id: "target")],
          edges: [Elkrb::Graph::Edge.new(
            id: "e", sources: ["p"], targets: ["target"],
          )],
        )

        expect(serializer.serialize(graph)).to include("direct:p -> target")
      end

      it "omits cluster routing when the opposite endpoint is inside it" do
        group = Elkrb::Graph::Node.new(
          id: "group",
          children: [
            Elkrb::Graph::Node.new(id: "leaf", width: 72, height: 36),
            Elkrb::Graph::Node.new(id: "sink"),
          ],
          ports: [Elkrb::Graph::Port.new(id: "p")],
        )
        graph = Elkrb::Graph::Graph.new(
          id: "root", children: [group],
          edges: [
            Elkrb::Graph::Edge.new(
              id: "outbound", sources: ["p"], targets: ["sink"],
            ),
            Elkrb::Graph::Edge.new(
              id: "inbound", sources: ["sink"], targets: ["p"],
            ),
          ]
        )

        dot = serializer.serialize(graph)
        _plain, stderr, status = Open3.capture3(
          "dot", "-Tplain", stdin_data: dot
        )

        expect(dot).to include("leaf:p -> sink", "sink -> leaf:p")
        expect(dot).not_to include("ltail=", "lhead=")
        expect(status).to be_success, stderr
        expect(stderr).to be_empty
      rescue Errno::ENOENT
        skip "Graphviz is not installed; skipping external DOT acceptance"
      end

      it "keeps same-named nodes distinct across hierarchy scopes" do
        nested = Elkrb::Graph::Node.new(
          id: "nested",
          children: [Elkrb::Graph::Node.new(id: "shared")],
        )
        group = Elkrb::Graph::Node.new(
          id: "group",
          children: [
            nested, Elkrb::Graph::Node.new(id: "sink")
          ],
          edges: [Elkrb::Graph::Edge.new(
            id: "nested", sources: ["shared"], targets: ["sink"],
          )],
        )
        graph = Elkrb::Graph::Graph.new(
          id: "root",
          children: [
            Elkrb::Graph::Node.new(id: "shared"), group,
            Elkrb::Graph::Node.new(id: "shared_2"),
            Elkrb::Graph::Node.new(id: "outside")
          ],
          edges: [Elkrb::Graph::Edge.new(
            id: "root_edge", sources: ["shared"], targets: ["outside"],
          )],
        )

        dot = serializer.serialize(graph)
        plain, stderr, status = Open3.capture3(
          "dot", "-Tplain", stdin_data: dot
        )

        expect(dot).to include(
          "shared_3 -> sink",
          "shared -> outside",
          "shared_3 [label=\"shared\", shape=box]",
        )
        expect(status).to be_success, stderr
        expect(stderr).to be_empty
        expect(plain.lines.grep(/^node /).length).to eq(5)
        expect(plain).to include(
          "node shared_3", "shared solid box",
          "edge shared_3 sink", "edge shared outside"
        )
      rescue Errno::ENOENT
        skip "Graphviz is not installed; skipping external DOT acceptance"
      end

      it "declares escaped Graphviz ports without renderer warnings" do
        source = Elkrb::Graph::Node.new(
          id: "source", width: 720, height: 360,
          ports: [Elkrb::Graph::Port.new(id: "port.with-dash")],
          labels: [
            Elkrb::Graph::Label.new(text: "A & <B>"),
            Elkrb::Graph::Label.new(text: "Second"),
          ]
        )
        rendered = Elkrb::Graph::Graph.new(
          id: "root",
          children: [source, Elkrb::Graph::Node.new(id: "target")],
          edges: [Elkrb::Graph::Edge.new(
            id: "e", sources: ["port.with-dash"], targets: ["target"],
          )],
        )

        dot = serializer.serialize(rendered)
        stdout, stderr, status = Open3.capture3(
          "dot", "-Tplain", stdin_data: dot
        )

        expect(dot).to include(
          "PORT=\"port0\"", "A &amp; &lt;B&gt;<BR/>Second",
          "source:port0 -> target", "shape=box",
          'WIDTH="720" HEIGHT="360"'
        )
        expect(status).to be_success, stderr
        expect(stderr).to be_empty
        source_line = stdout.lines.find do |line|
          line.start_with?("node source ")
        end
        expect(source_line.split.values_at(4, 5).map(&:to_f))
          .to contain_exactly(a_value_within(0.01).of(10.0),
                              a_value_within(0.01).of(5.0))
      rescue Errno::ENOENT
        skip "Graphviz is not installed; skipping external DOT acceptance"
      end

      it "keeps declared dimensions when a port id is wider than its node" do
        port_id = "port-#{'wide' * 30}"
        source = Elkrb::Graph::Node.new(
          id: "n", width: 72, height: 36,
          ports: [Elkrb::Graph::Port.new(id: port_id)]
        )
        graph = Elkrb::Graph::Graph.new(
          id: "root",
          children: [source, Elkrb::Graph::Node.new(id: "target")],
          edges: [Elkrb::Graph::Edge.new(
            id: "e", sources: [port_id], targets: ["target"],
          )],
        )

        dot = serializer.serialize(graph)
        stdout, stderr, status = Open3.capture3(
          "dot", "-Tplain", stdin_data: dot
        )

        expect(status).to be_success, stderr
        expect(stderr).to be_empty
        source_line = stdout.lines.find { |line| line.start_with?("node n ") }
        expect(source_line.split.values_at(4, 5).map(&:to_f))
          .to contain_exactly(a_value_within(0.01).of(1.0),
                              a_value_within(0.01).of(0.5))
      rescue Errno::ENOENT
        skip "Graphviz is not installed; skipping external DOT acceptance"
      end

      it "keeps generated Graphviz port names distinct from declared names" do
        source = Elkrb::Graph::Node.new(
          id: "source",
          ports: [
            Elkrb::Graph::Port.new(id: "a-b"),
            Elkrb::Graph::Port.new(id: "port0"),
          ],
        )
        graph = Elkrb::Graph::Graph.new(
          id: "root", children: [source, Elkrb::Graph::Node.new(id: "target")],
          edges: [
            Elkrb::Graph::Edge.new(
              id: "invalid", sources: ["a-b"], targets: ["target"],
            ),
            Elkrb::Graph::Edge.new(
              id: "valid", sources: ["port0"], targets: ["target"],
            ),
          ]
        )

        dot = serializer.serialize(graph)

        expect(dot).to include(
          'PORT="port1"', 'PORT="port0"',
          "source:port1 -> target", "source:port0 -> target"
        )
      end
    end

    context "with edge routing" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          g.children << Elkrb::Graph::Node.new(id: "node1")
          g.children << Elkrb::Graph::Node.new(id: "node2")

          edge = Elkrb::Graph::Edge.new(
            id: "edge1",
            sources: ["node1"],
            targets: ["node2"],
          )

          section = Elkrb::Graph::EdgeSection.new
          section.start_point = Elkrb::Geometry::Point.new(x: 0, y: 0)
          section.bend_points = [
            Elkrb::Geometry::Point.new(x: 50, y: 25),
            Elkrb::Geometry::Point.new(x: 75, y: 50),
          ]
          section.end_point = Elkrb::Geometry::Point.new(x: 100, y: 100)

          edge.sections = [section]
          g.edges << edge
        end
      end

      it "includes routing points" do
        result = serializer.serialize(graph, engine: "neato")

        expect(result).to include("pos=")
        expect(result).to include("0.0,0.0")
        expect(result).to include("100.0,100.0")
      end
    end

    context "with hierarchical graphs" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          parent = Elkrb::Graph::Node.new(
            id: "parent",
            width: 200,
            height: 150,
          )
          parent.labels = [
            Elkrb::Graph::Label.new(text: "Parent Node"),
          ]
          parent.children = [
            Elkrb::Graph::Node.new(
              id: "child1",
              width: 50,
              height: 30,
            ),
            Elkrb::Graph::Node.new(
              id: "child2",
              width: 50,
              height: 30,
            ),
          ]
          g.children << parent
        end
      end

      it "creates subgraphs for hierarchical nodes" do
        result = serializer.serialize(graph)

        expect(result).to include("subgraph cluster_")
      end

      it "includes subgraph label" do
        result = serializer.serialize(graph)

        expect(result).to include('label="Parent Node"')
      end

      it "includes child nodes within subgraph" do
        result = serializer.serialize(graph)

        expect(result).to include("child1")
        expect(result).to include("child2")
      end

      it "properly indents subgraph content" do
        result = serializer.serialize(graph)
        lines = result.split("\n")

        subgraph_line = lines.find { |l| l.include?("subgraph") }
        expect(subgraph_line).to start_with("  ")

        # Content inside subgraph should be further indented
        inside_subgraph = false
        lines.each do |line|
          inside_subgraph = true if line.include?("subgraph")
          inside_subgraph = false if inside_subgraph && line.strip == "}"

          if inside_subgraph && line.include?("child1")
            expect(line).to start_with("    ")
          end
        end
      end
    end

    context "with layout options" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          g.layout_options = { "elk.direction" => "DOWN" }
        end
      end

      it "converts ELK direction to DOT rankdir" do
        result = serializer.serialize(graph)

        expect(result).to include("rankdir=TB")
      end

      it "handles RIGHT direction" do
        graph.layout_options["elk.direction"] = "RIGHT"
        result = serializer.serialize(graph)

        expect(result).to include("rankdir=LR")
      end

      it "handles LEFT direction" do
        graph.layout_options["elk.direction"] = "LEFT"
        result = serializer.serialize(graph)

        expect(result).to include("rankdir=RL")
      end

      it "handles UP direction" do
        graph.layout_options["elk.direction"] = "UP"
        result = serializer.serialize(graph)

        expect(result).to include("rankdir=BT")
      end

      it "allows overriding rankdir via options" do
        result = serializer.serialize(graph, rankdir: "LR")

        expect(result).to include("rankdir=LR")
      end

      it "falls back to a bare direction key (Gate A finding 4)" do
        graph.layout_options.delete("elk.direction")
        graph.layout_options["direction"] = "RIGHT"

        result = serializer.serialize(graph)

        expect(result).to include("rankdir=LR")
      end
    end

    context "with custom graph attributes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root")
      end

      it "includes custom graph attributes" do
        result = serializer.serialize(
          graph,
          graph_attrs: {
            bgcolor: "lightgray",
            fontsize: 12,
          },
        )

        expect(result).to include("bgcolor=lightgray")
        expect(result).to include("fontsize=12")
      end
    end

    context "with default node and edge attributes" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          g.children << Elkrb::Graph::Node.new(id: "node1")
        end
      end

      it "includes default node attributes" do
        result = serializer.serialize(
          graph,
          node_attrs: {
            shape: "ellipse",
            color: "blue",
          },
        )

        expect(result).to include("node [shape=ellipse, color=blue]")
      end

      it "includes default edge attributes" do
        result = serializer.serialize(
          graph,
          edge_attrs: {
            color: "red",
            style: "dashed",
          },
        )

        expect(result).to include("edge [color=red, style=dashed]")
      end
    end

    context "with node positions" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          g.children << Elkrb::Graph::Node.new(
            id: "node1",
            x: 100,
            y: 50,
            width: 60,
            height: 40,
          )
        end
      end

      it "includes position attribute" do
        result = serializer.serialize(graph, engine: "neato")

        # Position should be center of node
        # x: 100 + 60/2 = 130
        # y: 50 + 40/2 = 70
        expect(result).to include("pos=")
      end
    end

    context "with nested hierarchical graphs" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          grandparent = Elkrb::Graph::Node.new(id: "grandparent")
          parent = Elkrb::Graph::Node.new(id: "parent")
          child = Elkrb::Graph::Node.new(id: "child")

          parent.children = [child]
          grandparent.children = [parent]
          g.children << grandparent
        end
      end

      it "creates nested subgraphs" do
        result = serializer.serialize(graph)

        # Should have multiple cluster declarations
        cluster_count = result.scan("subgraph cluster_").length
        expect(cluster_count).to be >= 2
      end
    end

    context "with empty graphs" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root")
      end

      it "generates valid DOT for empty graph" do
        result = serializer.serialize(graph)

        expect(result).to include("digraph G")
        expect(result).to include("{")
        expect(result).to include("}")
      end
    end

    context "with complex graph" do
      let(:graph) do
        Elkrb::Graph::Graph.new(id: "root").tap do |g|
          # Add multiple nodes
          3.times do |i|
            node = Elkrb::Graph::Node.new(
              id: "node#{i}",
              width: 100,
              height: 50,
            )
            node.labels = [
              Elkrb::Graph::Label.new(text: "Node #{i}"),
            ]
            g.children << node
          end

          # Add edges
          g.edges << Elkrb::Graph::Edge.new(
            id: "e1",
            sources: ["node0"],
            targets: ["node1"],
          )
          g.edges << Elkrb::Graph::Edge.new(
            id: "e2",
            sources: ["node1"],
            targets: ["node2"],
          )
          g.edges << Elkrb::Graph::Edge.new(
            id: "e3",
            sources: ["node2"],
            targets: ["node0"],
          )
        end
      end

      it "generates complete DOT output" do
        result = serializer.serialize(graph)

        # Check structure
        expect(result).to include("digraph G")

        # Check all nodes
        expect(result).to include("node0")
        expect(result).to include("node1")
        expect(result).to include("node2")

        # Check all edges
        expect(result).to include("node0 -> node1")
        expect(result).to include("node1 -> node2")
        expect(result).to include("node2 -> node0")

        # Check labels
        expect(result).to include('label="Node 0"')
        expect(result).to include('label="Node 1"')
        expect(result).to include('label="Node 2"')
      end
    end
  end
end
