# frozen_string_literal: true

# Graph builders and a distance probe for the sporeOverlap specs.
module SporeOverlapGraphs
  # Two 30x30 nodes: a at the origin, then +second+.
  def spore_pair(second)
    Elkrb.layout(
      { id: "root",
        children: [{ id: "a", x: 0, y: 0, width: 30, height: 30 }, second] },
      algorithm: "spore_overlap",
    )
  end

  # 2..14 boxes scattered over a small area, so most start overlapping.
  # Every seventh seed also gets a node on exactly the first one's point.
  def spore_scatter(seed)
    rng = Random.new(seed)
    children = Array.new(rng.rand(2..14)) do |i|
      { id: "n#{i}", x: rng.rand(0..80), y: rng.rand(0..80),
        width: rng.rand(5..60), height: rng.rand(5..60) }
    end
    children << children.first.merge(id: "twin") if (seed % 7).zero?
    { id: "root", children: children }
  end

  # Clear space between two laid-out nodes along the axis that separates them
  # most; negative when they overlap.
  def box_gap(first, second)
    [axis_gap(first.x, first.width, second.x, second.width),
     axis_gap(first.y, first.height, second.y, second.height)].max
  end

  def axis_gap(low_a, size_a, low_b, size_b)
    [low_b - (low_a + size_a), low_a - (low_b + size_b)].max
  end
end

RSpec.configure { |config| config.include SporeOverlapGraphs }
