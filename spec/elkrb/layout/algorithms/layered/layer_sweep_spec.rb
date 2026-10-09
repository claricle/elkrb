# frozen_string_literal: true

require "spec_helper"

# Every expected order below was printed by elkjs 0.11.0 for the same graph
# with the default LAYER_SWEEP strategy.
RSpec.describe Elkrb::Layout::Algorithms::Layered::LayerSweep do
  describe "two sources into one node" do
    {
      %w[d b c] => %w[c b],
      %w[d c b] => %w[c b],
      %w[b c d] => %w[c b],
      %w[c b d] => %w[c b],
    }.each do |ids, expected|
      it "orders the sources #{expected.join} for nodes listed #{ids.join}" do
        layers = layer_columns(ids: ids, edges: [%w[b d], %w[c d]])

        expect(layers.first).to eq(expected)
      end
    end
  end

  describe "one node into two targets" do
    {
      %w[d b c] => %w[b c],
      %w[d c b] => %w[b c],
      %w[b c d] => %w[b c],
      %w[c b d] => %w[c b],
    }.each do |ids, expected|
      it "orders the targets #{expected.join} for nodes listed #{ids.join}" do
        layers = layer_columns(ids: ids, edges: [%w[d b], %w[d c]])

        expect(layers.last).to eq(expected)
      end
    end
  end

  describe "graphs with a crossing to resolve" do
    {
      "a shared sink" => [
        %w[e a d c f b], [%w[b f], %w[c f], %w[b e], %w[a d], %w[a f]],
        [%w[a c b], %w[d f e]]
      ],
      "a source that feeds two" => [
        %w[c a b d e], [%w[a c], %w[b c], %w[a d], %w[a e]],
        [%w[b a], %w[c e d]]
      ],
      "a chain beside a source" => [
        %w[d c b e a], [%w[b c], %w[c e], %w[a d], %w[b d]],
        [%w[a b], %w[d c], %w[e]]
      ],
      "two sources, two sinks" => [
        %w[b e c a d], [%w[c e], %w[b d], %w[b e], %w[a d]],
        [%w[a b c], %w[d e]]
      ],
      "a source into three" => [
        %w[e c b d a], [%w[a d], %w[a b], %w[d e], %w[a c]],
        [%w[a], %w[c b d], %w[e]]
      ],
    }.each do |name, (ids, edges, expected)|
      it "matches elkjs for #{name}" do
        expect(layer_columns(ids: ids, edges: edges)).to eq(expected)
      end
    end
  end

  # Port keys are fractions: 5/3 and 1 must not both truncate to 1, or two
  # ports that elkjs tells apart stay in their input order.
  describe "ports whose neighbours average to a fraction" do
    # The routes elkjs 0.11.0 drew for the "UP forward 8" graph of
    # spec/fixtures/layered_junctions/cases.json.
    {
      "e2" => [[47.66666666666667, 128], [47.66666666666667, 118],
               [51, 118], [51, 108]],
      "e5" => [[47.66666666666667, 128], [47.66666666666667, 118],
               [37, 118], [37, 108]],
      "e6" => [[37, 128], [37, 108]],
    }.each do |edge_id, expected|
      it "routes #{edge_id} as elkjs does" do
        path = File.join(__dir__, "../../../../fixtures/layered_junctions",
                         "cases.json")
        cases = JSON.parse(File.read(path))
        graph = cases.find { |c| c["name"] == "UP forward 8" }["graph"]
        section = Elkrb.layout(graph).edges.find { |e| e.id == edge_id }
          .sections.first

        route = [section.start_point, *section.bend_points, section.end_point]
        expect(route.flat_map { |q| [q.x, q.y] })
          .to match(expected.flatten.map { |v| be_within(1e-6).of(v) })
      end
    end
  end
end
