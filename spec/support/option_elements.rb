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

  # A root graph with the given layoutOptions and children.
  def option_graph(layout_options, children: [])
    Elkrb::Graph::Graph.new(id: "root", layout_options: layout_options,
                            children: children)
  end
end

RSpec.configure { |config| config.include OptionElements }
