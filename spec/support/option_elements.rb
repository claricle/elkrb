# frozen_string_literal: true

# Builders for the resolver and wiring specs. They take arguments, so they
# live here rather than as `let` (no arity) or a describe-body `def`.
module OptionElements
  # A node carrying only the two option maps a resolver reads.
  def option_element(layout_options: nil, properties: nil)
    Elkrb::Graph::Node.new(id: "n", layout_options: layout_options,
                           properties: properties)
  end

  # A node with just layoutOptions.
  def with_layout_options(layout_options)
    option_element(layout_options: layout_options)
  end

  # A Hash holding `pairs` in order. kind :default and :default_proc make a
  # missing key answer `leak`, the way a Hash.new(...) from a caller would.
  def option_hash(pairs, kind = :plain, leak: "LEAK")
    hash = case kind
           when :default then Hash.new(leak)
           when :default_proc then Hash.new { leak }
           else {}
           end
    pairs.each { |key, value| hash[key] = value }
    hash
  end

  # A node whose option maps are exactly the given Hashes, with their key
  # types and default. Node.new stringifies layoutOptions keys and drops a
  # default, so the maps go in with Hash#replace, which keeps both.
  def option_element_holding(layout_options: {}, properties: {})
    node = option_element(layout_options: {}, properties: {})
    node.layout_options.replace(layout_options)
    node.properties.replace(properties)
    node
  end

  # A root graph whose layoutOptions are exactly `layout_options`, as above.
  def option_graph_holding(layout_options)
    graph = option_graph({})
    graph.layout_options.replace(layout_options)
    graph
  end

  # [resolver, elements] for one option map holding `entries`, placed where
  # `source` says: an element's layout_options, its properties, the
  # properties map nested in layout_options (under `nested_key`), or the
  # call options.
  def option_source(source, entries, kind, nested_key = "properties")
    map = option_hash(entries, kind)
    resolver = Elkrb::Options::Resolver
    case source
    when :layout_options
      [resolver.new({}), [option_element_holding(layout_options: map)]]
    when :properties
      [resolver.new({}), [option_element_holding(properties: map)]]
    when :nested
      layout = option_hash({ nested_key => map }, kind)
      [resolver.new({}), [option_element_holding(layout_options: layout)]]
    when :call
      [resolver.new(map), []]
    end
  end

  # What `resolver` answers for each spelling asked, from the same chain.
  def answers_for(resolver, elements, spellings)
    spellings.map { |spelling| resolver.get(spelling, *elements) }
  end

  # A layoutOptions map, or one nested under `nested_key` when it is given,
  # whose missing keys answer `leak`.
  def leaky_layout_options(nested_key, pairs, kind, leak)
    map = option_hash(pairs, kind, leak: leak)
    return map unless nested_key

    option_hash({ nested_key => map }, kind, leak: leak)
  end

  # A node holding one child, as the parent of a nested graph.
  def nested_parent(id, layout_options: nil, properties: nil)
    Elkrb::Graph::Node.new(
      id: id, width: 50, height: 50, layout_options: layout_options,
      properties: properties,
      children: [Elkrb::Graph::Node.new(id: "#{id}-kid", width: 5, height: 5)]
    )
  end

  # [x, y] of the three chained nodes of a graph nested under a root that
  # pins `root_algorithm`, where `inner` adds the options naming the nested
  # algorithm and `call` holds the options passed to Elkrb.layout.
  def nested_graph_positions(inner, root_algorithm: "layered", call: {})
    inner_graph = {
      id: "inner",
      children: %w[a b c].map { |id| { id: id, width: 10, height: 10 } },
      edges: [{ id: "ab", sources: ["a"], targets: ["b"] },
              { id: "bc", sources: ["b"], targets: ["c"] }],
    }.merge(inner)
    root = { id: "root", layoutOptions: { "elk.algorithm" => root_algorithm },
             children: [inner_graph] }
    Elkrb.layout(root, call).children.first.children.map { |n| [n.x, n.y] }
  end

  # [x, y] of the four nodes of a graph two levels down: a layered root, a
  # middle node that selects box through `mid_options`, and a graph below it
  # that names no options. `call` holds the options passed to Elkrb.layout.
  def grandchild_positions(mid_options, call: {})
    leaves = Array.new(4) { |i| { id: "n#{i}", width: 10, height: 10 } }
    below = { id: "below", width: 50, height: 50, children: leaves }
    mid = { id: "mid", properties: { "elk.algorithm" => "box" },
            children: [below] }.merge(mid_options)
    root = { id: "root", layoutOptions: { "elk.algorithm" => "layered" },
             children: [mid] }
    graph = Elkrb.layout(root, call)
    graph.children.first.children.first.children.map { |n| [n.x, n.y] }
  end

  # A root graph with the given layoutOptions and children.
  def option_graph(layout_options, children: [])
    Elkrb::Graph::Graph.new(id: "root", layout_options: layout_options,
                            children: children)
  end
end

RSpec.configure { |config| config.include OptionElements }
