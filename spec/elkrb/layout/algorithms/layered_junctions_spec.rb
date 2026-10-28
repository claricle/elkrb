# frozen_string_literal: true

require "json"

# Each case in the fixture holds a graph whose edges share ports, and the
# junction points elkjs 0.11.0 put on each edge when routing ORTHOGONAL.
# Edges that share a bend get the junction point once, on the first of them.
RSpec.describe "Layered junction points against elkjs" do
  cases = JSON.parse(
    File.read(File.expand_path("../../../fixtures/layered_junctions/cases.json",
                               __dir__)),
  )

  cases.each do |example|
    describe example["name"] do
      let(:result) { Elkrb.layout(example["graph"]) }

      example["junctions"].each do |edge_id, expected|
        it "gives #{edge_id} the junction points of elkjs" do
          edge = result.edges.find { |candidate| candidate.id == edge_id }
          actual = edge.junction_points.map { |point| [point.x, point.y] }

          expect(actual.flatten)
            .to match(expected.flatten.map { |v| be_within(1e-6).of(v) })
        end
      end
    end
  end
end
