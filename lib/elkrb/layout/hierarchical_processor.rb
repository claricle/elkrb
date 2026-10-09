# frozen_string_literal: true

require_relative "algorithm_registry"
require_relative "../options/resolver"

module Elkrb
  module Layout
    # Sizes compound nodes bottom-up, one graph level per algorithm instance.
    module HierarchicalProcessor
      # Layout each compound as its own graph before its parent level.
      def size_compound_children(graph)
        child_resolver = Options::Resolver.new
        graph.children.each do |node|
          next unless node.hierarchical?

          child_graph = create_child_graph(node)
          pin = child_resolver.get("elk.algorithm", child_graph, default: nil)
          algorithm = pin ? AlgorithmRegistry.get(pin) : self.class
          raise AlgorithmNotFoundError.new(pin) unless algorithm

          algorithm.new(@options).layout(child_graph)
          node.width = child_graph.width
          node.height = child_graph.height
        end
      end

      private

      # Build the graph view shared by compound sizing and nested edge routing.
      def create_child_graph(node)
        Graph::Graph.new(
          id: "#{node.id}_children",
          children: node.children,
          edges: node.edges,
          layout_options: node.layout_options,
          properties: node.properties,
        )
      end
    end
  end
end
