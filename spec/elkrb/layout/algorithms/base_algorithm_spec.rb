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

  describe ".normalize_nil_positions" do
    # Shared by SporeOverlap and SporeCompaction, both of which read
    # node.x/node.y arithmetically before any other pass assigns them.
    # Java ELK treats an unset position as 0.0 rather than raising.
    # Defined once here rather than duplicated per subclass; a subclass
    # calls it as `self.class.normalize_nil_positions`, which resolves
    # here through ordinary class-method inheritance.
    it "defaults a nil x or y to 0.0 independently, leaving a set value " \
       "alone" do
      both_nil = Elkrb::Graph::Node.new(id: "a", width: 10, height: 10)
      x_set = Elkrb::Graph::Node.new(id: "b", x: 5.0, width: 10, height: 10)
      y_set = Elkrb::Graph::Node.new(id: "c", y: 7.0, width: 10, height: 10)

      described_class.normalize_nil_positions([both_nil, x_set, y_set])

      expect(both_nil.x).to eq(0.0)
      expect(both_nil.y).to eq(0.0)
      expect(x_set.x).to eq(5.0)
      expect(x_set.y).to eq(0.0)
      expect(y_set.x).to eq(0.0)
      expect(y_set.y).to eq(7.0)
    end

    it "is inherited by subclasses as a class method, not duplicated" do
      expect(Elkrb::Layout::Algorithms::SporeOverlap.singleton_class.instance_method(:normalize_nil_positions).owner)
        .to eq(described_class.singleton_class)
      expect(Elkrb::Layout::Algorithms::SporeCompaction.singleton_class.instance_method(:normalize_nil_positions).owner)
        .to eq(described_class.singleton_class)
    end
  end
end
