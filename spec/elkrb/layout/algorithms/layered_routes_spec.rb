# frozen_string_literal: true

require "json"

# Each case in the fixture holds a graph and the ORTHOGONAL routes elkjs
# 0.11.0 computed for it. Our routes must match point for point.
RSpec.describe "Layered orthogonal routes against elkjs" do
  cases = JSON.parse(
    File.read(File.expand_path("../../../fixtures/layered_routes/cases.json",
                               __dir__)),
  )

  def route_of(edge)
    section = edge.sections.first
    [section.start_point, *section.bend_points, section.end_point]
      .map { |point| [point.x, point.y] }
  end

  cases.each do |example|
    describe example["name"] do
      let(:result) { Elkrb.layout(example["graph"]) }

      example["routes"].each do |edge_id, expected|
        it "routes #{edge_id} like elkjs" do
          edge = result.edges.find { |candidate| candidate.id == edge_id }

          within = expected.flatten.map { |value| be_within(1e-6).of(value) }

          expect(route_of(edge).flatten).to match(within)
        end
      end
    end
  end
end
