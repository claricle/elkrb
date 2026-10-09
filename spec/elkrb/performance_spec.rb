# frozen_string_literal: true

require "timeout"

# Wall-clock budgets, skipped unless ELKRB_PERF=1:
# `ELKRB_PERF=1 bundle exec rspec --tag perf`. They are skipped rather than
# tag-excluded because the coverage floor refuses any filtered run. Each budget
# is a multiple of the slowest run measured under SimpleCov on a loaded
# machine, so it fails on a blow-up, not on a slow laptop. Re-measure before
# tightening one.
RSpec.describe "Performance budgets", :perf,
               skip: (ENV["ELKRB_PERF"] == "1" ? false : "set ELKRB_PERF=1") do
  [
    ["layered", 4000, 15],
    ["stress", 200, 180],
    ["force", 100, 15],
  ].each do |algorithm, size, budget_seconds|
    it "lays out a #{size}-node #{algorithm} chain within #{budget_seconds}s" do
      graph_data = chain_graph(size)
      graph = nil

      seconds = elapsed_seconds do
        graph = Timeout.timeout(budget_seconds * 2) do
          Elkrb.layout(graph_data, algorithm: algorithm)
        end
      end

      expect(graph.children.size).to eq(size)
      expect(seconds).to be < budget_seconds
    end
  end

  describe "libavoid" do
    it "returns from a search whose goal is off the grid" do
      algorithm = Elkrb::Layout::Algorithms::Libavoid.new
      start = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      goal = Elkrb::Geometry::Point.new(x: 1003.7, y: 877.3)
      wall = Elkrb::Geometry::Rectangle.new(400.0, -2000.0, 20.0, 4000.0)

      _path, status = Timeout.timeout(30) do
        algorithm.send(:find_path, start, goal, [wall])
      end

      expect(status).to eq(:capped)
    end
  end
end
