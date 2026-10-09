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
end
