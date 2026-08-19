# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Graph::LayoutOptions do
  describe "after deserialization (from_json bypasses #initialize)" do
    let(:deserialized) { described_class.from_json('{"algorithm":"layered"}') }

    it "#[] returns nil instead of raising" do
      expect(deserialized["elk.direction"]).to be_nil
    end

    it "#[]= sets a value instead of raising" do
      deserialized["elk.direction"] = "DOWN"
      expect(deserialized["elk.direction"]).to eq("DOWN")
    end

    it "#merge applies another options hash instead of raising" do
      deserialized.merge("elk.direction" => "DOWN")
      expect(deserialized["elk.direction"]).to eq("DOWN")
    end

    it "#port_constraints returns the documented default instead of raising" do
      expect(deserialized.port_constraints).to eq("UNDEFINED")
    end

    it "#port_constraints= then #port_constraints round-trips" do
      deserialized.port_constraints = "FIXED_SIDE"
      expect(deserialized.port_constraints).to eq("FIXED_SIDE")
    end

    it "#self_loop_offset returns the documented default instead of raising" do
      expect(deserialized.self_loop_offset).to eq(20.0)
    end
  end

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
      graph = Elkrb::Graph::Graph.from_hash(
        { id: "r", layout_options: { direction: "DOWN" },
          children: [{ id: "n1", width: 10.0, height: 10.0 }] },
      )
      expect { Elkrb.layout(graph) }.not_to raise_error
    end
  end
end
