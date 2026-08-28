# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::BaseAlgorithm do
  describe "#layout dispatch to #layout_flat" do
    # Codex round-1 diff finding: an earlier version of the RC4c fix guarded
    # dispatch with `graph.children.any?`, which also skipped layout_flat
    # for an explicit empty array (`children: []`), not just a nil/missing
    # children key. That silently broke the documented contract that a
    # BaseAlgorithm subclass's #layout_flat always runs, including the
    # NotImplementedError a subclass gets for not overriding it.
    let(:tracking_algorithm) do
      Class.new(described_class) do
        attr_reader :layout_flat_called

        def layout_flat(graph, _options = {})
          @layout_flat_called = true
          graph
        end
      end.new
    end

    it "calls layout_flat for an explicit empty children array" do
      graph = Elkrb::Graph::Graph.new(children: [])

      tracking_algorithm.layout(graph)

      expect(tracking_algorithm.layout_flat_called).to be true
    end

    it "skips layout_flat for a nil children key (deserialized, no crash)" do
      graph = Elkrb::Graph::Graph.from_hash({ id: "r" })

      expect { described_class.new.layout(graph) }.not_to raise_error
    end

    it "raises NotImplementedError for an unoverridden layout_flat with an empty array" do
      graph = Elkrb::Graph::Graph.new(children: [])

      expect { described_class.new.layout(graph) }
        .to raise_error(NotImplementedError)
    end
  end

  describe "#get_edge_routing_style" do
    it "reads from a bare edgeRouting option (Gate A finding 4)" do
      graph = Elkrb::Graph::Graph.new(layout_options: { "edgeRouting" => "POLYLINE" })

      expect(described_class.new.send(:get_edge_routing_style, graph)).to eq("POLYLINE")
    end
  end
end
