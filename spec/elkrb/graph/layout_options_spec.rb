# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Graph::LayoutOptions do
  describe "graph/node/edge-level layoutOptions through the full pipeline" do
    it "graph-level layoutOptions from JSON does not raise" do
      graph = Elkrb::Graph::Graph.from_json(
        '{"id":"r","layoutOptions":{"elk.direction":"DOWN"},' \
        '"children":[{"id":"n1","width":10,"height":10}]}',
      )
      expect { Elkrb.layout(graph) }.not_to raise_error
    end

    it "edge-level layoutOptions from JSON does not raise" do
      graph = Elkrb::Graph::Graph.from_json(
        '{"id":"r","children":[{"id":"a","width":10,"height":10},' \
        '{"id":"b","width":10,"height":10}],"edges":[{"id":"e",' \
        '"sources":["a"],"targets":["b"],' \
        '"layoutOptions":{"elk.edgeRouting":"POLYLINE"}}]}',
      )
      expect { Elkrb.layout(graph) }.not_to raise_error
    end

    it "node-level layoutOptions from JSON does not raise" do
      # Node-level layoutOptions is only read internally by the self-loop
      # router (edge_router.rb#get_self_loop_side), so the repro needs a
      # self-loop. Uses algorithm: "fixed", which does no cycle-breaking or
      # layering at all, so this example depends only on RC1 — verified it
      # raises NoMethodError on unfixed code and already passes once RC1
      # alone lands, with no dependency on the RC4a self-loop fix above.
      graph = Elkrb::Graph::Graph.from_json(
        '{"id":"r","children":[{"id":"a","width":10,"height":10,' \
        '"layoutOptions":{"elk.selfLoopSide":"WEST"}}],' \
        '"edges":[{"id":"e","sources":["a"],"targets":["a"]}]}',
      )
      expect { Elkrb.layout(graph, algorithm: "fixed") }.not_to raise_error
    end

    it "graph-level layoutOptions from YAML does not raise" do
      yaml = "id: r\nlayout_options:\n  direction: DOWN\n" \
             "children:\n  - id: n1\n    width: 10.0\n    height: 10.0\n"
      graph = Elkrb::Graph::Graph.from_yaml(yaml)
      expect { Elkrb.layout(graph) }.not_to raise_error
    end

    it "graph-level layoutOptions from_hash does not raise" do
      # Snake-case `layout_options:` on Hash input is intentionally not
      # honoured (only camelCase `layoutOptions:` is, per decision 1).
      graph = Elkrb::Graph::Graph.from_hash(
        { id: "r", layout_options: { direction: "DOWN" },
          children: [{ id: "n1", width: 10.0, height: 10.0 }] },
      )
      expect(graph.layout_options).to be_nil
      expect { Elkrb.layout(graph) }.not_to raise_error
    end
  end

  describe "open map round trip" do
    it "keeps every key from JSON at graph/node/port/label/edge level, and re-serializes each level's layoutOptions unchanged" do
      json = '{"id":"r","layoutOptions":{"elk.algorithm":"box",' \
             '"elk.spacing.nodeNode":40,' \
             '"elk.padding":"[top=1,left=2,bottom=3,right=4]",' \
             '"foo.bar":true,"nested":{"a":1}},' \
             '"children":[{"id":"n","width":10,"height":10,' \
             '"layoutOptions":{"elk.direction":"DOWN"},' \
             '"ports":[{"id":"p","layoutOptions":{"elk.port.side":"EAST"}}],' \
             '"labels":[{"text":"L","layoutOptions":{"x":1}}]}],' \
             '"edges":[{"id":"e","sources":["n"],"targets":["n"],' \
             '"layoutOptions":{"elk.edgeRouting":"SPLINES"}}]}'
      graph = Elkrb::Graph::Graph.from_json(json)

      expect(graph.layout_options).to eq(
        "elk.algorithm" => "box",
        "elk.spacing.nodeNode" => 40,
        "elk.padding" => "[top=1,left=2,bottom=3,right=4]",
        "foo.bar" => true,
        "nested" => { "a" => 1 },
      )
      # `eq` uses `==`, which treats 40 and 40.0 as equal — pin the type too.
      expect(graph.layout_options["elk.spacing.nodeNode"]).to be_a(Integer)
      node = graph.children.first
      expect(node.layout_options).to eq("elk.direction" => "DOWN")
      expect(node.ports.first.layout_options).to eq("elk.port.side" => "EAST")
      expect(node.labels.first.layout_options).to eq("x" => 1)
      expect(graph.edges.first.layout_options).to eq("elk.edgeRouting" => "SPLINES")

      # Pin serialization (not just deserialization) at every level. Compare
      # each level's layoutOptions sub-object specifically, rather than the
      # whole document: width/height round-trip as Float (Integer 10 -> 10.0)
      # and Port always emits its index/offset defaults — both pre-existing,
      # unrelated to layoutOptions, and out of this slice's scope.
      serialized = JSON.parse(graph.to_json)
      input = JSON.parse(json)
      expect(serialized["layoutOptions"]).to eq(input["layoutOptions"])
      # `eq` would let a serialization-only 40 -> 40.0 coercion through.
      expect(serialized["layoutOptions"]["elk.spacing.nodeNode"]).to be_a(Integer)
      serialized_node = serialized["children"].first
      input_node = input["children"].first
      expect(serialized_node["layoutOptions"]).to eq(input_node["layoutOptions"])
      expect(serialized_node["ports"].first["layoutOptions"])
        .to eq(input_node["ports"].first["layoutOptions"])
      expect(serialized_node["labels"].first["layoutOptions"])
        .to eq(input_node["labels"].first["layoutOptions"])
      expect(serialized["edges"].first["layoutOptions"])
        .to eq(input["edges"].first["layoutOptions"])
    end

    it "round-trips the same document through from_yaml/to_yaml" do
      yaml = <<~YAML
        id: r
        layout_options:
          elk.algorithm: box
          elk.spacing.nodeNode: 40
        children:
          - id: n
            width: 10.0
            height: 10.0
            layout_options:
              elk.direction: DOWN
      YAML
      graph = Elkrb::Graph::Graph.from_yaml(yaml)

      expect(graph.layout_options).to eq(
        "elk.algorithm" => "box", "elk.spacing.nodeNode" => 40,
      )
      expect(graph.children.first.layout_options).to eq("elk.direction" => "DOWN")

      # Re-parse the regenerated YAML rather than substring-matching one key,
      # so a dropped elk.spacing.nodeNode or child elk.direction would fail.
      reparsed = Elkrb::Graph::Graph.from_yaml(graph.to_yaml)
      expect(reparsed.layout_options).to eq(graph.layout_options)
      expect(reparsed.children.first.layout_options)
        .to eq(graph.children.first.layout_options)
    end

    it "round-trips layout_options carried on an edge, a port, and a label through YAML (Gate A finding 4)" do
      yaml = <<~YAML
        id: r
        children:
          - id: n
            width: 10.0
            height: 10.0
            ports:
              - id: p
                layout_options:
                  elk.port.side: EAST
            labels:
              - id: l
                text: L
                layout_options:
                  elk.nodeLabels.placement: OUTSIDE
        edges:
          - id: e
            sources: [n]
            targets: [n]
            layout_options:
              elk.edgeRouting: SPLINES
      YAML
      graph = Elkrb::Graph::Graph.from_yaml(yaml)
      node = graph.children.first

      expect(node.ports.first.layout_options).to eq("elk.port.side" => "EAST")
      expect(node.labels.first.layout_options).to eq("elk.nodeLabels.placement" => "OUTSIDE")
      expect(graph.edges.first.layout_options).to eq("elk.edgeRouting" => "SPLINES")

      reparsed = Elkrb::Graph::Graph.from_yaml(graph.to_yaml)
      reparsed_node = reparsed.children.first
      expect(reparsed_node.ports.first.layout_options).to eq(node.ports.first.layout_options)
      expect(reparsed_node.labels.first.layout_options).to eq(node.labels.first.layout_options)
      expect(reparsed.edges.first.layout_options).to eq(graph.edges.first.layout_options)
    end

    it "leaves opaque non-option data alone, stringifying only what it owns" do
      graph = Elkrb::Graph::Graph.from_hash(
        { "id" => "r",
          "properties" => { "opaque" => { 1 => "integer", "1" => "string" } } },
      )

      expect(graph.properties).to eq("opaque" => { 1 => "integer",
                                                   "1" => "string" })
    end

    it "accepts the braceless from_hash form without raising" do
      graph = Elkrb::Graph::Graph.from_hash(id: "r", layoutOptions: { foo: 1 })

      expect(graph.layout_options).to eq("foo" => 1)
    end

    it "stringifies symbol keys at every depth from_hash" do
      graph = Elkrb::Graph::Graph.from_hash(
        { id: "r", layoutOptions: { "elk.algorithm" => "box", :"elk.x" => 1 },
          children: [{ id: "n", layoutOptions: { sym: "v" } }] },
      )

      expect(graph.layout_options).to eq("elk.algorithm" => "box", "elk.x" => 1)
      expect(graph.children.first.layout_options).to eq("sym" => "v")
      expect(graph.to_yaml).to include("elk.x: 1")
      expect(graph.to_yaml).not_to include(":elk.x:")
    end

    it "LayoutOptions.new accepts braceless string keys, explicit-brace hashes, and symbol kwargs" do
      expect(Elkrb::Graph::LayoutOptions.new("elk.x" => 1)["elk.x"]).to eq(1)
      expect(Elkrb::Graph::LayoutOptions.new({ "elk.x" => 1 })["elk.x"]).to eq(1)
      expect(Elkrb::Graph::LayoutOptions.new(foo: "x")["foo"]).to eq("x")

      graph = Elkrb::Graph::Graph.new(layout_options: Elkrb::Graph::LayoutOptions.new("a" => 1))
      expect(graph.layout_options).to eq("a" => 1)
      expect(graph.layout_options).to be_a(Hash)
    end

    it "omits layoutOptions from to_json when absent or empty" do
      expect(Elkrb::Graph::Graph.new(id: "r").to_json).not_to include("layoutOptions")
      expect(Elkrb::Graph::Graph.from_json('{"id":"r","layoutOptions":{}}').to_json)
        .not_to include("layoutOptions")
    end

    it "layout_options is nil when absent from input, and layout still runs" do
      graph = Elkrb::Graph::Graph.from_json(
        '{"id":"r","children":[{"id":"a","width":1,"height":1}]}',
      )
      expect(graph.layout_options).to be_nil
      expect { Elkrb.layout(graph) }.not_to raise_error
    end

    it "mutation through the getter sticks" do
      edge = Elkrb::Graph::Edge.new(id: "e")
      edge.layout_options = Elkrb::Graph::LayoutOptions.new
      edge.layout_options["k"] = 1
      expect(edge.layout_options["k"]).to eq(1)
    end

    it "normalizes a Symbol key written in place through the getter, on every model" do
      %w[Graph Node Edge Port Label].each do |name|
        model = Elkrb::Graph.const_get(name).new(id: "x")
        model.layout_options = { "a" => 1 }
        model.layout_options[:edgeRouting] = "SPLINES"

        expect(model.layout_options["edgeRouting"]).to eq("SPLINES")
        expect(model.layout_options.keys).to contain_exactly("a", "edgeRouting")
      end
    end

    it "normalizes a Symbol key written in place on a freshly constructed graph" do
      graph = Elkrb::Graph::Graph.new(id: "r")
      graph.layout_options[:edgeRouting] = "SPLINES"

      expect(graph.layout_options["edgeRouting"]).to eq("SPLINES")
    end

    it "normalizes through every ::Hash writer, not just #[]=" do
      options = Elkrb::Graph::LayoutOptions.new
      options.store(:stored, 1)
      options.merge!(merged: 2)
      options.update(updated: 3)

      expect(options.keys).to contain_exactly("stored", "merged", "updated")

      options.replace(replaced: 4)
      expect(options.keys).to contain_exactly("replaced")

      options.transform_keys!(&:to_sym)
      expect(options.keys).to contain_exactly("replaced")
      expect(options["replaced"]).to eq(4)
    end

    it "leaves the map alone when replaced by itself, like ::Hash does" do
      options = Elkrb::Graph::LayoutOptions.new("elk.direction" => "DOWN")

      options.replace(options)

      expect(options).to eq("elk.direction" => "DOWN")
    end

    it "carries the source hash's default across a replace, like ::Hash does" do
      source = Hash.new("FALLBACK")
      source["elk.direction"] = "DOWN"
      options = Elkrb::Graph::LayoutOptions.new

      options.replace(source)

      expect(options["elk.direction"]).to eq("DOWN")
      expect(options["absent"]).to eq("FALLBACK")
    end

    it "keeps its own default across transform_keys!" do
      options = Elkrb::Graph::LayoutOptions.new
      options.default = "MINE"
      options["elk.direction"] = "DOWN"

      options.transform_keys!(&:to_s)

      expect(options["absent"]).to eq("MINE")
    end

    it "answers an Enumerator and mutates nothing when transform_keys! gets no block" do
      options = Elkrb::Graph::LayoutOptions.new("elk.direction" => "DOWN")

      expect(options.transform_keys!).to be_a(Enumerator)
      expect(options).to eq("elk.direction" => "DOWN")
    end

    it "normalizes keys built through the class-level ::Hash.[] constructor" do
      options = Elkrb::Graph::LayoutOptions[edgeRouting: "SPLINES"]

      expect(options.keys).to eq(["edgeRouting"])
      expect(options[:edgeRouting]).to eq("SPLINES")
      expect(options["edgeRouting"]).to eq("SPLINES")
    end

    it "lets a merge! conflict block pick the value, like ::Hash does" do
      options = Elkrb::Graph::LayoutOptions.new("elk.spacing.nodeNode" => 10)

      options.merge!("elk.spacing.nodeNode": 30) do |_key, old, new|
        old + new
      end

      expect(options).to eq("elk.spacing.nodeNode" => 40)
    end

    it "normalizes a Symbol key assigned directly via .new(layout_options:), on every model" do
      graph = Elkrb::Graph::Graph.new(id: "g",
                                      layout_options: { edgeRouting: "SPLINES" })
      node = Elkrb::Graph::Node.new(id: "n", layout_options: { padding: 10 })
      edge = Elkrb::Graph::Edge.new(id: "e",
                                    layout_options: { direction: "RIGHT" })
      port = Elkrb::Graph::Port.new(id: "p", layout_options: { side: "EAST" })
      label = Elkrb::Graph::Label.new(id: "l",
                                      layout_options: { placement: "CENTER" })

      expect(graph.layout_options).to eq("edgeRouting" => "SPLINES")
      expect(node.layout_options).to eq("padding" => 10)
      expect(edge.layout_options).to eq("direction" => "RIGHT")
      expect(port.layout_options).to eq("side" => "EAST")
      expect(label.layout_options).to eq("placement" => "CENTER")
    end

    it "normalizes a Symbol key assigned via the setter, not just the constructor" do
      node = Elkrb::Graph::Node.new(id: "n")
      node.layout_options = { edgeRouting: "SPLINES" }

      expect(node.layout_options).to eq("edgeRouting" => "SPLINES")
      expect(node.layout_options["edgeRouting"]).to eq("SPLINES")
    end

    it "a direct-constructor edgeRouting key now resolves through the real routing pipeline" do
      node1 = Elkrb::Graph::Node.new(id: "a", width: 10, height: 10)
      node2 = Elkrb::Graph::Node.new(id: "b", width: 10, height: 10)
      edge = Elkrb::Graph::Edge.new(id: "e", sources: ["a"], targets: ["b"])
      graph = Elkrb::Graph::Graph.new(
        id: "g", children: [node1, node2], edges: [edge],
        layout_options: { edgeRouting: "SPLINES" }
      )

      Elkrb.layout(graph, algorithm: "fixed")

      expect(edge.sections.first.bend_points).not_to be_empty
    end
  end

  describe "legacy snake_case edge_routing from YAML (temporary until S5)" do
    it "honours a self-loop's edge_routing key end to end, matching pre-S3 behaviour" do
      yaml = <<~YAML
        id: r
        layout_options:
          edge_routing: SPLINES
        children:
          - id: a
            width: 10.0
            height: 10.0
        edges:
          - id: e
            sources: [a]
            targets: [a]
      YAML
      graph = Elkrb::Graph::Graph.from_yaml(yaml)

      expect(graph.layout_options).to eq("edge_routing" => "SPLINES")

      Elkrb.layout(graph, algorithm: "fixed")

      expect(graph.edges.first.sections.first.bend_points.size).to eq(2)
    end
  end

  describe "legacy typed kwarg translation (temporary until S3b removes the shim)" do
    it "translates known legacy attribute names to their ELK keys" do
      opts = Elkrb::Graph::LayoutOptions.new(edge_routing: "SPLINES",
                                             spacing_node_node: 40)

      expect(opts).to eq("elk.edgeRouting" => "SPLINES",
                         "elk.spacing.nodeNode" => 40)
    end

    it "flattens the 1.x properties: bag into the map itself" do
      # The deprecation memo is process-wide, so another example in this file
      # may already have spent the one warning for :properties.
      Elkrb::Graph::LayoutOptions.instance_variable_set(:@warned_legacy_kwargs,
                                                        nil)
      options = nil

      expect do
        options = Elkrb::Graph::LayoutOptions.new(properties: { "padding" => 20 })
      end.to output(/deprecated/).to_stderr

      expect(options).to eq("padding" => 20)
      expect(options["padding"]).to eq(20)
    end

    it "merges a properties: bag alongside its sibling kwargs" do
      options = Elkrb::Graph::LayoutOptions.new(
        properties: { "elk.padding" => 5 },
        edge_routing: "SPLINES",
      )

      expect(options).to eq("elk.padding" => 5, "elk.edgeRouting" => "SPLINES")
    end

    it "leaves an unknown symbol kwarg as its bare key (no translation)" do
      expect(Elkrb::Graph::LayoutOptions.new(foo: "x")).to eq("foo" => "x")
    end

    it "leaves the elkrb-private hierarchical kwarg untranslated (no ELK counterpart)" do
      expect(Elkrb::Graph::LayoutOptions.new(hierarchical: true)).to eq("hierarchical" => true)
    end

    it "does not translate a positional Hash, braced or braceless (matches pre-S3 behaviour)" do
      expect(Elkrb::Graph::LayoutOptions.new({ edge_routing: "X" })).to eq("edge_routing" => "X")
      expect(Elkrb::Graph::LayoutOptions.new("edge_routing" => "Y")).to eq("edge_routing" => "Y")
    end

    it "warns once per key, not once per call" do
      # Order-independent: the once-per-key memo is process-wide.
      Elkrb::Graph::LayoutOptions.instance_variable_set(:@warned_legacy_kwargs,
                                                        nil)

      expect { Elkrb::Graph::LayoutOptions.new(cycle_breaking_strategy: "GREEDY") }
        .to output(/cycle_breaking_strategy/).to_stderr

      expect { Elkrb::Graph::LayoutOptions.new(cycle_breaking_strategy: "DEPTH_FIRST") }
        .not_to output(/cycle_breaking_strategy/).to_stderr

      # A second key still warns — the memo is per key, not one shot per process.
      expect { Elkrb::Graph::LayoutOptions.new(edge_routing: "SPLINES") }
        .to output(/edge_routing/).to_stderr
    end

    it "an explicit canonical key always wins over a same-call legacy alias (Gate B finding 2)" do
      # positional Hash + separate kwarg
      expect(
        Elkrb::Graph::LayoutOptions.new({ "elk.edgeRouting" => "explicit" },
                                        edge_routing: "legacy"),
      ).to eq("elk.edgeRouting" => "explicit")

      # braceless, canonical key written first
      expect(
        Elkrb::Graph::LayoutOptions.new("elk.edgeRouting" => "explicit",
                                        edge_routing: "legacy"),
      ).to eq("elk.edgeRouting" => "explicit")

      # braceless, canonical key written last (order must not flip the winner)
      expect(
        Elkrb::Graph::LayoutOptions.new(edge_routing: "legacy",
                                        "elk.edgeRouting" => "explicit"),
      ).to eq("elk.edgeRouting" => "explicit")
    end
  end

  describe "lutaml-reserved keys inside layoutOptions (pinned quirks)" do
    it "raises on a bare `text` key" do
      expect do
        Elkrb::Graph::Graph.from_json('{"id":"r","layoutOptions":{"text":"v"}}')
      end.to raise_error(Lutaml::Model::InvalidFormatError)
    end

    it "unwraps a bare `elements` key and drops its siblings" do
      graph = Elkrb::Graph::Graph.from_json(
        '{"id":"r","layoutOptions":{"elements":{"a":1},"b":2}}',
      )
      expect(graph.layout_options).to eq("a" => 1)
    end

    it "names the reserved key when one is assigned through a setter, on every model" do
      [Elkrb::Graph::Graph.new,
       Elkrb::Graph::Node.new(id: "n"),
       Elkrb::Graph::Edge.new(id: "e"),
       Elkrb::Graph::Port.new(id: "p"),
       Elkrb::Graph::Label.new(text: "l")].each do |model|
        expect do
          model.layout_options = { "text" => "v" }
        end.to raise_error(Elkrb::ValidationError, /reserved by lutaml-model/)
      end
    end
  end
end
