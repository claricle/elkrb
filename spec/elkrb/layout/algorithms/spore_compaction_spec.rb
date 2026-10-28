# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Algorithms::SporeCompaction do
  include SporeCompactionGraphs

  # elkjs 0.11.0 is the reference; the tolerance covers float summation order.
  tolerance = 1e-6

  describe "#layout against elkjs" do
    JSON.parse(File.read(SporeCompactionGraphs::FIXTURE)).each do |name, kase|
      it "places #{name} where elkjs does" do
        laid_out = Elkrb.layout(spore_compaction_graph(kase),
                                algorithm: "sporeCompaction")
        expected = kase.fetch("expected")
        got = laid_out.children.to_h { |node| [node.id, [node.x, node.y]] }

        expect(got.keys).to eq(expected.fetch("nodes").keys)
        expected.fetch("nodes").each do |id, (x, y)|
          expect(got.fetch(id)).to match([be_within(tolerance).of(x),
                                          be_within(tolerance).of(y)])
        end
        expect([laid_out.width, laid_out.height])
          .to match(expected.fetch("size").map do |v|
            be_within(tolerance).of(v)
          end)
      end
    end
  end

  describe "spore.compactionDirection" do
    let(:kase) { spore_compaction_cases.fetch("default_scatter") }

    # Axes along which some node moved relative to the first node; the final
    # shift to the padding moves every node alike and is not a slide.
    def slid_axes(kase, direction)
      graph = spore_compaction_graph(kase)
      graph.layout_options["spore.compactionDirection"] = direction
      before = offsets(graph)
      Elkrb.layout(graph, algorithm: "sporeCompaction")
      %i[x y].zip(before, offsets(graph)).filter_map do |axis, was, now|
        axis unless was.zip(now).all? { |a, b| (a - b).abs <= 1e-9 }
      end
    end

    # Per axis, every node's distance from the first node.
    def offsets(graph)
      %i[x y].map do |axis|
        graph.children.map do |node|
          node.public_send(axis) - graph.children.first.public_send(axis)
        end
      end
    end

    it "slides along x only for horizontal" do
      expect(slid_axes(kase, "horizontal")).to eq([:x])
    end

    it "slides along y only for vertical" do
      expect(slid_axes(kase, "vertical")).to eq([:y])
    end

    it "slides along both for both" do
      expect(slid_axes(kase, "both")).to eq(%i[x y])
    end
  end
end
