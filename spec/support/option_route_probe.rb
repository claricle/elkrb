# frozen_string_literal: true

require "json"

# Lays out one small graph with an option at two values and reports whether
# the output moved. registry_spec uses it to hold each status and note to
# what layout actually does on each route an option can arrive by.
module OptionRouteProbe
  # @param route [:layout_options, :edge_layout_options,
  #   :compound_layout_options, :call_option] the graph's layoutOptions, one
  #   edge's layoutOptions, a compound node's own layoutOptions, or a keyword
  #   to Elkrb.layout
  # @param values [Array] the two values to compare
  # @param context [Hash] `positioned:` (default true) says whether the nodes
  #   arrive with input positions: true for all, false for none, :some for
  #   the first node only (an algorithm that re-places every node unless all
  #   have one). `compound_options:` is layoutOptions the compound
  #   node carries besides the probed key, such as its own elk.algorithm.
  def option_moves_layout?(algorithm:, key:, values:, route:, **context)
    unknown = context.keys - %i[positioned compound_options]
    raise ArgumentError, "unknown context #{unknown}" unless unknown.empty?

    positioned = context.fetch(:positioned, true)
    unless [true, false, :some].include?(positioned)
      raise ArgumentError, "unknown positioned #{positioned.inspect}"
    end

    extra = context.fetch(:compound_options, {})
    low, high = values.map do |value|
      probe_layout(algorithm, { route => extra.merge(key => value),
                                positioned: positioned })
    end
    low != high
  end

  private

  # Cheap enough to run thousands of rows: force would otherwise spend its
  # default 300 iterations on every one.
  PROBE_FORCE_ITERATIONS = 10
  private_constant :PROBE_FORCE_ITERATIONS

  # force and random draw from Kernel#rand, so both runs start from one seed,
  # put back afterwards. Call-option keys go to Elkrb.layout exactly as
  # given: layered reads only Symbol keys, so a String key is its own row.
  def probe_layout(algorithm, options)
    call_options = options.fetch(:call_option, {})
    previous = srand(1)
    out = Elkrb.layout(probe_graph(options), algorithm: algorithm,
                                             iterations: PROBE_FORCE_ITERATIONS,
                                             **call_options)
    [out.children.map { |node| geometry(node) }, out.width, out.height,
     out.edges.map(&:sections)]
  ensure
    srand(previous)
  end

  def geometry(node)
    [node.x, node.y, node.width, node.height,
     (node.children || []).map { |child| geometry(child) }]
  end

  # SPLINES so an edge's own direction has something to orient. Nodes start
  # spread far apart (wider than any probed spacing) so an algorithm that
  # keeps or compacts input positions has something to move. A compound node
  # joins n1..n6 only for its own route, with no edge to it, so only its own
  # options can move anything. The graph is parsed once per shape and deep
  # copied for each layout, because parsing is slow; the probed options are
  # put on the copy after a JSON round trip, which is what parsing them from
  # the graph's JSON gives them.
  def probe_graph(options)
    base = base_graph(options[:positioned],
                      options.key?(:compound_layout_options))
    put_options(Marshal.load(Marshal.dump(base)), options)
  end

  def put_options(graph, options)
    graph.layout_options = json_copy({ "elk.edgeRouting" => "SPLINES" }
      .merge(options.fetch(:layout_options, {})))
    graph.edges.first.layout_options =
      json_copy(options.fetch(:edge_layout_options, {}))
    compound = options[:compound_layout_options]
    graph.children.last.layout_options = json_copy(compound) if compound
    graph
  end

  def json_copy(hash)
    JSON.parse(hash.to_json)
  end

  def base_graph(positioned, compound)
    @base_graphs ||= {}
    @base_graphs[[positioned, compound]] ||= Elkrb::Graph::Graph.from_json(
      {
        id: "root",
        layoutOptions: {},
        children: probe_children(positioned, compound),
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"], layoutOptions: {} },
          { id: "e2", sources: ["n2"], targets: ["n3"] },
        ],
      }.to_json,
    )
  end

  def probe_children(positioned, compound)
    nodes = (1..6).map { |i| probe_node("n#{i}", i, positioned) }
    return nodes unless compound

    nodes + [compound_node(positioned)]
  end

  def compound_node(positioned)
    probe_node("c", 7, positioned).merge(
      layoutOptions: {},
      children: (1..5).map { |i| probe_node("c#{i}", i, positioned) },
      edges: [{ id: "ce1", sources: ["c1"], targets: ["c2"] },
              { id: "ce2", sources: ["c2"], targets: ["c3"] }],
    )
  end

  def probe_node(id, index, positioned)
    node = { id: id, width: 30, height: 30 }
    return node if positioned == false
    return node if positioned == :some && index != 1

    node.merge(x: index * 200, y: (index % 2) * 200)
  end
end
