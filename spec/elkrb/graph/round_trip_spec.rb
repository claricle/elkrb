# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Graph round trips" do
  # Port#index and Port#offset are rendered as -1 and 0.0 after any parse, even
  # when the source document carried neither. That belongs to the ports item,
  # not to this one, so it is excluded here rather than fixed. Delete this
  # method and its two call sites when ports stop emitting their defaults --
  # it is a no-op once they do, so nothing else has to change.
  #
  # Mutates in place and returns the same object; both call sites pass a
  # freshly parsed structure.
  def without_port_defaults!(node)
    case node
    when Hash
      Array(node["ports"]).each do |port|
        port.delete("index")
        port.delete("offset")
      end
      node.each_value { |value| without_port_defaults!(value) }
    when Array
      node.each { |element| without_port_defaults!(element) }
    end
    node
  end

  describe "every committed fixture" do
    # Resolved against __dir__, not the process CWD: a glob that silently comes
    # back empty would generate zero examples and pass.
    fixtures = Dir[File.expand_path("../../fixtures/*.json", __dir__)]

    it "finds the committed fixtures" do
      expect(fixtures).not_to be_empty
    end

    fixtures.each do |path|
      it "survives parse and re-serialize for #{File.basename(path)}" do
        source = File.read(path)

        expect(without_port_defaults!(
                 JSON.parse(Elkrb::Graph::Graph.from_json(source).to_json),
               ))
          .to eq(without_port_defaults!(JSON.parse(source)))
      end
    end
  end

  describe "a synthetic elkjs graph" do
    # Carries every key this item adds TO OUTPUT, plus the surrounding shapes
    # they sit in. The legacy source/target/sourcePort/targetPort keys are
    # deliberately absent: they normalise to sources/targets on read, so they
    # could never round-trip identically. edge_spec covers them instead.
    # The port declares index and offset so no default has to be masked, and
    # deliberately sets no side -- Port#side survives parse but is dropped on
    # WRITE, because Port#side= never calls value_set_for. That is the ports
    # item's defect, not this one's, and a side key here would add a sixth
    # difference that belongs to it.
    let(:source) do
      <<~JSON
        {
          "id": "root",
          "layoutOptions": { "elk.algorithm": "layered", "elk.direction": "RIGHT" },
          "children": [
            {
              "id": "n1",
              "width": 30.0,
              "height": 30.0,
              "layoutOptions": { "elk.portConstraints": "FIXED_SIDE" },
              "labels": [
                {
                  "id": "n1l",
                  "text": "N1",
                  "x": 1.0,
                  "y": 2.0,
                  "width": 10.0,
                  "height": 5.0,
                  "properties": { "kind": "title" }
                }
              ],
              "ports": [
                { "id": "p1", "width": 4.0, "height": 4.0, "index": 0, "offset": 0.0 }
              ]
            },
            { "id": "n2", "width": 30.0, "height": 30.0 }
          ],
          "edges": [
            {
              "id": "e1",
              "sources": ["p1"],
              "targets": ["n2"],
              "container": "root",
              "junctionPoints": [{ "x": 5.0, "y": 6.0 }],
              "sections": [
                {
                  "id": "e1_s0",
                  "startPoint": { "x": 0.0, "y": 0.0 },
                  "endPoint": { "x": 10.0, "y": 10.0 },
                  "bendPoints": [{ "x": 5.0, "y": 0.0 }],
                  "incomingShape": "n1",
                  "outgoingShape": "n2",
                  "incomingSections": ["a"],
                  "outgoingSections": ["b"]
                }
              ]
            }
          ]
        }
      JSON
    end

    # No exclusion at all: every key here must survive on its own merits.
    it "survives parse and re-serialize with nothing dropped or added" do
      expect(JSON.parse(Elkrb::Graph::Graph.from_json(source).to_json))
        .to eq(JSON.parse(source))
    end
  end
end
