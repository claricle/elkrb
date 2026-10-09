# frozen_string_literal: true

require "json"

# Each case in the fixture holds a graph with several connected components and
# the layout elkjs 0.11.0 computed for it: node positions, graph size and edge
# routes. Ours must match number for number.
RSpec.describe "Layered connected components against elkjs" do
  cases = JSON.parse(
    File.read(
      File.expand_path("../../../fixtures/layered_components/cases.json",
                       __dir__),
    ),
  )

  def route_of(edge)
    section = edge.sections.first
    [section.start_point, *section.bend_points, section.end_point]
      .map { |point| [point.x, point.y] }
  end

  def close_to(expected)
    expected.flatten.map { |value| be_within(1e-6).of(value) }
  end

  cases.each do |example|
    describe example["name"] do
      let(:result) { Elkrb.layout(example["graph"]) }

      it "places every node like elkjs" do
        placed = result.children.to_h { |node| [node.id, [node.x, node.y]] }

        expect(placed.keys).to eq(example["positions"].keys)
        example["positions"].each do |id, expected|
          expect(placed.fetch(id)).to match(close_to(expected))
        end
      end

      it "sizes the graph like elkjs" do
        expect([result.width, result.height])
          .to match(close_to(example["size"]))
      end

      it "routes every edge with its nodes like elkjs" do
        example["routes"].each do |edge_id, expected|
          edge = result.edges.find { |candidate| candidate.id == edge_id }

          expect(route_of(edge).flatten).to match(close_to(expected)),
                                            "edge #{edge_id}"
        end
      end
    end
  end
end
