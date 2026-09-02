# frozen_string_literal: true

require_relative "be_deterministic"

RSpec.describe "be_deterministic" do
  let(:input_hash) do
    { "id" => "root",
      "children" => [{ "id" => "a", "width" => 30, "height" => 30 },
                     { "id" => "b", "width" => 30, "height" => 30 }],
      "edges" => [{ "id" => "e1", "sources" => ["a"], "targets" => ["b"] }] }
  end

  it "passes when two layout runs of the same input agree" do
    expect do
      Elkrb.layout(Elkrb::Graph::Graph.from_hash(input_hash),
                   {})
    end.to be_deterministic
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
  # The direction that matters: a difference the JSON mapping cannot show.
  # Comparing serialized output alone would call this deterministic.
  it "fails when two runs differ in a way the JSON hides" do
    hidden = Class.new do
      attr_reader :tag

      def initialize(tag) = @tag = tag
      def to_json(*) = '{"same":"always"}'
      def ==(other) = tag == other.tag
    end

    tags = %w[first second].each
    result = expect { hidden.new(tags.next) }.to be_deterministic
    raise "expected the matcher to fail" if result
  rescue RSpec::Expectations::ExpectationNotMetError => e
    expect(e.message).to match(/attribute the JSON mapping omits/)
  end
end
