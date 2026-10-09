# frozen_string_literal: true

require "json"

# The consumer contract table and helpers for the sirena contract spec.
module SirenaContract
  FIXTURE_DIR = File.expand_path("../fixtures/consumers/sirena", __dir__)

  # The consumer's option keys, as data. Never derived from the registry.
  KEYS = {
    "algorithm" => { status: :honoured, slice: "08, 09" },
    "elk.direction" => { status: :partial, slice: "13, 23" },
    "elk.spacing.nodeNode" => { status: :partial, slice: "09, 10" },
    "elk.layered.spacing.nodeNodeBetweenLayers" =>
      { status: :honoured, slice: "13" },
    "elk.spacing.edgeNode" => { status: :accepted, slice: "08" },
    "elk.spacing.edgeEdge" => { status: :accepted, slice: "08" },
    "elk.layered.nodePlacement.strategy" =>
      { status: :accepted, slice: "13" },
    "elk.layered.considerModelOrder.strategy" =>
      { status: :honoured, slice: "31" },
    "elk.layered.crossingMinimization.strategy" =>
      { status: :honoured, slice: "31" },
    "elk.layered.compaction.postCompaction.strategy" =>
      { status: :accepted, slice: "08" },
    "elk.hierarchyHandling" => { status: :partial, slice: "14, 15" },
    "elk.edgeRouting" => { status: :partial, slice: "16" },
    "elk.padding" => { status: :honoured, slice: "09" },
    "elk.box.packingMode" => { status: :accepted, slice: "22" },
    "elk.algorithm" => { status: :honoured, slice: "14" },
  }.freeze

  # Partial keys sirena sends to layered, which reads them: value to send.
  PARTIAL_READ_BY_LAYERED = {
    "elk.direction" => "DOWN",
    "elk.spacing.nodeNode" => 50,
    "elk.edgeRouting" => "ORTHOGONAL",
  }.freeze

  # Accepted key => [algorithm that lays the graph out, a value sirena sends].
  ACCEPTED_PROBES = {
    "elk.spacing.edgeNode" => ["layered", 30],
    "elk.spacing.edgeEdge" => ["layered", 20],
    "elk.layered.nodePlacement.strategy" => ["layered", "NETWORK_SIMPLEX"],
    "elk.layered.compaction.postCompaction.strategy" =>
      ["layered", "LEFT_RIGHT_CONSTRAINT_LOCKING"],
    "elk.box.packingMode" => ["box", "GROUP_MIXED"],
  }.freeze

  # A fresh Hash of a captured sirena graph; `options` replaces the root
  # layoutOptions when given.
  def consumer_hash(name, options = nil)
    hash = JSON.parse(File.read(File.join(FIXTURE_DIR, "#{name}.json")))
    hash["layoutOptions"] = options if options
    hash
  end

  # a fans out to b and c, declared c before b: b and c tie on barycenter, so
  # only model order decides which one goes first.
  def model_order_tie_hash(options)
    node = ->(id) { { "id" => id, "width" => 40, "height" => 30 } }
    {
      "id" => "tie",
      "layoutOptions" => options,
      "children" => %w[a c b].map(&node),
      "edges" => %w[a-b a-c].map do |pair|
        source, target = pair.split("-")
        { "id" => pair, "sources" => [source], "targets" => [target] }
      end,
    }
  end

  # Two layers whose input order crosses every edge.
  def reversed_bipartite_hash(options)
    node = ->(id) { { "id" => id, "width" => 40, "height" => 30 } }
    ids = %w[a b c x y z]
    {
      "id" => "bipartite",
      "layoutOptions" => options,
      "children" => ids.map(&node),
      "edges" => %w[a-z b-y c-x].map do |pair|
        source, target = pair.split("-")
        { "id" => pair, "sources" => [source], "targets" => [target] }
      end,
    }
  end

  def layout_hash(hash)
    Elkrb.layout(Elkrb::Graph::Graph.from_hash(hash), {})
  end

  # Lays out a captured graph with `options` as its root layoutOptions.
  def layout_consumer(name, options)
    layout_hash(consumer_hash(name, options))
  end

  # The graph as JSON without the root layoutOptions, which echo the input.
  def echo_free_json(graph)
    JSON.parse(graph.to_json).except("layoutOptions")
  end

  def positions_by_id(graph)
    graph.children.to_h { |node| [node.id, [node.x, node.y]] }
  end

  def bend_point_count(graph)
    graph.edges.sum do |edge|
      edge.sections.sum { |section| section.bend_points.to_a.size }
    end
  end

  # { id => Rectangle } in the root frame, for every node at any depth.
  def absolute_rectangles(owner, origin = [0.0, 0.0], result = {})
    owner.children.to_a.each do |node|
      rect = rectangle_in(node, origin)
      result[node.id] = rect
      absolute_rectangles(node, [rect.x, rect.y], result)
    end
    result
  end

  def rectangle_in(node, origin)
    Elkrb::Geometry::Rectangle.new(origin[0] + node.x, origin[1] + node.y,
                                   node.width, node.height)
  end

  def centres(graph)
    absolute_rectangles(graph).transform_values do |rect|
      [rect.x + (rect.width / 2), rect.y + (rect.height / 2)]
    end
  end

  def edge_ends(graph)
    graph.edges.map { |edge| [edge.sources.first, edge.targets.first] }
  end

  # Edge crossings of the straight lines between node centres; edges that
  # share an endpoint never count.
  def crossing_count(graph)
    points = centres(graph)
    edge_ends(graph).combination(2).count do |a, b|
      (a + b).uniq.size == 4 &&
        segments_cross?(points.values_at(*a), points.values_at(*b))
    end
  end

  def segments_cross?(first, second)
    side(*first, second[0]) * side(*first, second[1]) < 0 &&
      side(*second, first[0]) * side(*second, first[1]) < 0
  end

  def side(from, to, point)
    ((to[0] - from[0]) * (point[1] - from[1])) -
      ((to[1] - from[1]) * (point[0] - from[0]))
  end
end
