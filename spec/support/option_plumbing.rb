# frozen_string_literal: true

require "json"
require "stringio"

# Builders for spec/elkrb/options/option_plumbing_spec.rb. The helpers take
# arguments, so they live here rather than as `let` (no arity) or a
# describe-body `def`.
module OptionPlumbing
  # Where an option is written. The resolver is element-scoped, so an option
  # that a router or label placer reads from an edge or a port has to be set
  # on that element, not on the root.
  PLACE_PATHS = {
    root: [],
    node: ["children", 0],
    port: ["children", 0, "ports", 0],
    edge: ["edges", 0],
    loop: ["edges", 2],
    spline_edge: ["edges", 1],
  }.freeze
  PLACES = PLACE_PATHS.keys.freeze

  NODE_BASE = [
    { "id" => "a", "x" => 0, "y" => 0, "width" => 40, "height" => 30,
      "layoutOptions" => {},
      "labels" => [{ "text" => "A", "width" => 12, "height" => 8 }],
      "ports" => [{ "id" => "a.p", "width" => 6, "height" => 6,
                    "layoutOptions" => {},
                    "labels" => [{ "text" => "p", "width" => 6,
                                   "height" => 6 }] }] },
    { "id" => "b", "x" => 70, "y" => 0, "width" => 40, "height" => 30 },
    { "id" => "c", "x" => 150, "y" => 0, "width" => 30, "height" => 30 },
    { "id" => "d", "x" => 20, "y" => 20, "width" => 30, "height" => 30 },
  ].freeze

  SPREAD_AT = [[0, 0], [200, 0], [0, 200], [200, 200]].freeze

  # Same four nodes, differently placed for the algorithms whose option only
  # shows when the input has the shape it acts on.
  NODE_VARIANTS = {
    default: nil,
    unpositioned: lambda do |nodes|
      nodes.each do |node|
        node.delete("x")
        node.delete("y")
      end
    end,
    # Declared sizes are kept by topdownpacking, so its cell options only
    # show on nodes that declare none.
    sizeless: lambda do |nodes|
      nodes.each do |node|
        node.delete("width")
        node.delete("height")
      end
    end,
    # A chain of overlaps that needs more than one removal pass.
    crowded: lambda do |nodes|
      nodes.each_with_index do |node, i|
        node["x"] = i * 10
        node["y"] = i * 5
      end
    end,
    # Four nodes far apart in both directions, so compaction has room to move.
    spread: lambda do |nodes|
      nodes.zip(SPREAD_AT) do |node, (x, y)|
        node["x"] = x
        node["y"] = y
      end
    end,
  }.freeze

  # The 4-node fixture: a-b and a-c edges (a labelled one, a port on a), and
  # d alone with a self-loop, so there are two components for disco. `places`
  # maps a place to the option Hash written there.
  def plumbing_json(places = {}, variant: :default)
    unknown = places.keys - PLACES
    raise ArgumentError, "unknown place #{unknown}" unless unknown.empty?

    graph = plumbing_skeleton(variant)
    place_options(graph, places)
    JSON.generate(graph)
  end

  # The laid-out graph as a Hash, without the layoutOptions that were written
  # into it: those are the input, and the question is whether the layout
  # moved.
  def plumbing_geometry(algorithm, places = {}, variant: :default)
    laid_out(JSON.parse(plumbing_json(places, variant: variant)), algorithm)
  end

  # A hand-written graph Hash laid out the same way as plumbing_geometry.
  def laid_out(graph_hash, algorithm, call_options = {})
    quietly do
      srand(1)
      graph = Elkrb::Graph::Graph.from_json(JSON.generate(graph_hash))
      Elkrb.layout(graph, call_options.merge(algorithm: algorithm))
      without_layout_options(JSON.parse(graph.to_json))
    end
  end

  # Two positioned nodes with one edge from a to b, `edge_options` on the
  # edge and `root_options` on the root.
  def two_node_graph(edge_options, root_options = {})
    {
      "id" => "r", "layoutOptions" => root_options,
      "children" => [positioned("a", 0, 0, 30), positioned("b", 100, 80, 30)],
      "edges" => [
        { "id" => "e", "sources" => ["a"], "targets" => ["b"],
          "layoutOptions" => edge_options },
      ]
    }
  end

  # The bend points of the one edge of two_node_graph, [] when its section has
  # none.
  def bends(edge_options, algorithm, root_options = {}, call_options = {})
    graph = two_node_graph(edge_options, root_options)
    laid = laid_out(graph, algorithm, call_options)
    laid["edges"][0]["sections"][0].fetch("bendPoints", [])
  end

  # The bend points of an edge from a port of a to the node b, with
  # `edge_options` on the edge and `root_options` on the root. b has no port
  # to end at, so the router takes its half-ported path.
  def port_to_node_bends(edge_options, root_options = {}, call_options = {})
    port = { "id" => "p", "x" => 30, "y" => 10, "width" => 6, "height" => 6 }
    source = positioned("a", 0, 0, 30).merge("ports" => [port])
    graph = { "id" => "r", "layoutOptions" => root_options,
              "children" => [source, positioned("b", 100, 80, 30)],
              "edges" => [{ "id" => "e", "sources" => ["p"],
                            "targets" => ["b"],
                            "layoutOptions" => edge_options }] }
    laid = laid_out(graph, "box", call_options)
    laid["edges"][0]["sections"][0].fetch("bendPoints", [])
  end

  # Where the one port label of a labelled node lands, with `port_options` on
  # the port and `call_options` on the layout call.
  def port_label_position(port_options, call_options = {})
    port = { "id" => "p", "x" => 40, "y" => 10, "width" => 6, "height" => 6,
             "layoutOptions" => port_options,
             "labels" => [{ "text" => "p", "width" => 6, "height" => 6 }] }
    node = { "id" => "a", "x" => 0, "y" => 0, "width" => 40, "height" => 30,
             "labels" => [{ "text" => "A", "width" => 10, "height" => 8 }],
             "ports" => [port] }
    graph = laid_out({ "id" => "r", "children" => [node], "edges" => [] },
                     "fixed", call_options)
    graph.dig("children", 0, "ports", 0, "labels", 0).values_at("x", "y")
  end

  # The bend points of a self-loop on a lone node, with `edge_options` on the
  # loop and `node_options` on the node.
  def self_loop_bends(edge_options, node_options)
    node = { "id" => "a", "x" => 0, "y" => 0, "width" => 40, "height" => 30,
             "layoutOptions" => node_options }
    loop_edge = { "id" => "l", "sources" => ["a"], "targets" => ["a"],
                  "layoutOptions" => edge_options }
    graph = laid_out({ "id" => "r", "children" => [node],
                       "edges" => [loop_edge] }, "box")
    graph.dig("edges", 0, "sections", 0, "bendPoints")
  end

  # A compound node p holding x and y, a sibling q, an edge inside p and an
  # edge from x to q that crosses the compound boundary.
  def nested_graph(root_options = {})
    inner = [positioned("x", 10, 10, 30), positioned("y", 60, 10, 30)]
    compound = positioned("p", 0, 0, 120, 100).merge(
      "children" => inner,
      "edges" => [{ "id" => "pe", "sources" => ["x"], "targets" => ["y"] }],
    )
    {
      "id" => "root", "layoutOptions" => root_options,
      "children" => [compound, positioned("q", 200, 0, 40)],
      "edges" => [{ "id" => "cross", "sources" => ["x"], "targets" => ["q"] }]
    }
  end

  # Every id the layout asked the resolver for, as canonical ids.
  def plumbing_reads(algorithm, places = {}, variant: :default)
    reads = []
    spy_on_resolver_reads(reads)
    plumbing_geometry(algorithm, places, variant: variant)
    reads.compact.uniq
  end

  def quietly
    saved = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = saved
  end

  private

  def positioned(id, left, top, width, height = 30)
    { "id" => id, "x" => left, "y" => top, "width" => width,
      "height" => height }
  end

  def spy_on_resolver_reads(reads)
    allow(Elkrb::Options::Resolver).to receive(:new)
      .and_wrap_original do |new, *args|
      new.call(*args).tap { |resolver| record_reads(resolver, reads) }
    end
  end

  def record_reads(resolver, reads)
    allow(resolver).to receive(:get)
      .and_wrap_original do |get, key, *elements, **kwargs|
      reads << Elkrb::Options::Registry.canonical(key)
      get.call(key, *elements, **kwargs)
    end
  end

  def plumbing_skeleton(variant)
    nodes = Marshal.load(Marshal.dump(NODE_BASE))
    NODE_VARIANTS.fetch(variant)&.call(nodes)
    {
      "id" => "root",
      "layoutOptions" => {},
      "children" => nodes,
      "edges" => [
        { "id" => "e1", "sources" => ["a"], "targets" => ["b"],
          "layoutOptions" => {},
          "labels" => [{ "text" => "x", "width" => 10, "height" => 10 }] },
        { "id" => "e2", "sources" => ["a"], "targets" => ["c"],
          "layoutOptions" => {} },
        { "id" => "loop", "sources" => ["d"], "targets" => ["d"],
          "layoutOptions" => {} },
      ],
    }
  end

  def place_options(graph, places)
    if places.key?(:spline_edge)
      graph["layoutOptions"]["elk.edgeRouting"] = "SPLINES"
    end
    places.each do |place, options|
      place_target(graph, place)["layoutOptions"].merge!(options)
    end
  end

  def place_target(graph, place)
    path = PLACE_PATHS.fetch(place)
    path.empty? ? graph : graph.dig(*path)
  end

  def without_layout_options(value)
    case value
    when Hash
      value.except("layoutOptions")
        .transform_values { |inner| without_layout_options(inner) }
    when Array then value.map { |inner| without_layout_options(inner) }
    else value
    end
  end
end

RSpec.configure { |config| config.include OptionPlumbing }
