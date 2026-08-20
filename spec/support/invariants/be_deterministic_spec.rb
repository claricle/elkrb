# frozen_string_literal: true

require_relative "be_deterministic"

RSpec.describe "be_deterministic" do
  let(:input_hash) do
    { "id" => "root", "children" => [{ "id" => "a", "width" => 30, "height" => 30 },
                                      { "id" => "b", "width" => 30, "height" => 30 }],
      "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }] }
  end

  it "passes when two layout runs of the same input agree" do
    expect { Elkrb.layout(Elkrb::Graph::Graph.from_hash(input_hash), {}) }.to be_deterministic
  end

  it "fails when the block returns a different result each call" do
    call_count = 0
    expect do
      call_count += 1
      graph = Elkrb::Graph::Graph.from_hash(input_hash)
      graph.children.first.x = call_count.to_f
      graph
    end.not_to be_deterministic
  end
end
