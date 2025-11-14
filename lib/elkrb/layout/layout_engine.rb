# frozen_string_literal: true

require_relative "algorithm_registry"

module Elkrb
  module Layout
    # Main entry point for graph layout operations.
    #
    # The LayoutEngine provides a high-level interface for applying layout
    # algorithms to graphs. It handles algorithm selection, graph conversion,
    # and delegates to the appropriate algorithm implementation.
    #
    # @example Basic usage with hash input
    #   graph = {
    #     id: "root",
    #     layoutOptions: { "elk.algorithm" => "layered" },
    #     children: [
    #       { id: "n1", width: 100, height: 60 },
    #       { id: "n2", width: 100, height: 60 }
    #     ],
    #     edges: [
    #       { id: "e1", sources: ["n1"], targets: ["n2"] }
    #     ]
    #   }
    #   result = Elkrb::Layout::LayoutEngine.layout(graph)
    #
    # @example Using Graph model objects
    #   graph = Elkrb::Graph::Graph.new(id: "root")
    #   node1 = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60)
    #   node2 = Elkrb::Graph::Node.new(id: "n2", width: 100, height: 60)
    #   graph.children = [node1, node2]
    #   result = Elkrb::Layout::LayoutEngine.layout(graph, algorithm: "force")
    #
    # @example Querying available algorithms
    #   algorithms = Elkrb::Layout::LayoutEngine.known_layout_algorithms
    #   algorithms.each do |name, info|
    #     puts "#{name}: #{info[:description]}"
    #   end
    class LayoutEngine
      class << self
        # Applies a layout algorithm to a graph.
        #
        # This method is the primary entry point for graph layout. It accepts
        # either a Hash representation or a Graph model object, selects the
        # appropriate algorithm based on options, and computes node positions
        # and edge routes.
        #
        # The algorithm is selected in this order:
        # 1. options[:algorithm] or options["algorithm"]
        # 2. graph.layoutOptions["elk.algorithm"]
        # 3. Default: "layered"
        #
        # @param graph [Hash, Elkrb::Graph::Graph] The graph to layout. Can be:
        #   - A Hash with keys: :id, :children, :edges, :layoutOptions
        #   - A Graph model object
        # @param options [Hash] Layout options including:
        #   - :algorithm (String) - Algorithm name (layered, force, etc.)
        #   - Algorithm-specific options
        # @return [Elkrb::Graph::Graph] The input graph with computed positions
        # @raise [Elkrb::Error] If the specified algorithm is not found
        #
        # @example With specific algorithm
        #   result = Elkrb::Layout::LayoutEngine.layout(
        #     graph,
        #     algorithm: "force",
        #     "elk.force.repulsion" => 5.0
        #   )
        #
        # @example With hierarchical layout
        #   result = Elkrb::Layout::LayoutEngine.layout(
        #     graph,
        #     algorithm: "layered",
        #     hierarchical: true
        #   )
        def layout(graph, options = {})
          # Convert hash to Graph if needed
          graph = convert_to_graph(graph) if graph.is_a?(Hash)

          # Get algorithm name from options
          algorithm_name = options[:algorithm] ||
            options["algorithm"] ||
            "layered"

          algorithm_class = AlgorithmRegistry.get(algorithm_name)

          raise Error, "Unknown layout algorithm: #{algorithm_name}" unless
            algorithm_class

          # Create and run algorithm with options
          algorithm = algorithm_class.new(options)
          algorithm.layout(graph)

          graph
        end

        # Returns metadata for all registered layout algorithms.
        #
        # This method provides information about each available algorithm
        # including its name, description, category, and capabilities.
        #
        # @return [Hash{String => Hash}] A hash mapping algorithm names to their metadata.
        #   Each metadata hash contains:
        #   - :name (String) - Display name of the algorithm
        #   - :description (String) - Brief description
        #   - :category (String, nil) - Algorithm category (e.g., "hierarchical", "force")
        #   - :supports_hierarchy (Boolean, nil) - Whether it supports hierarchical graphs
        #
        # @example List all algorithms
        #   algorithms = Elkrb::Layout::LayoutEngine.known_layout_algorithms
        #   algorithms.each do |name, info|
        #     puts "#{name}: #{info[:description]}"
        #   end
        #   # Output:
        #   # layered: Hierarchical layout using the Sugiyama framework
        #   # force: Physics-based layout using attractive and repulsive forces
        #   # ...
        #
        # @example Filter by category
        #   force_algs = Elkrb::Layout::LayoutEngine.known_layout_algorithms
        #     .select { |_, info| info[:category] == "force" }
        def known_layout_algorithms
          AlgorithmRegistry.all_algorithm_info
        end

        # Exports a graph to Graphviz DOT format.
        #
        # This method serializes an ELK graph structure to DOT format,
        # which can be rendered by Graphviz or other DOT-compatible tools.
        #
        # @param graph [Hash, Elkrb::Graph::Graph] The graph to export
        # @param options [Hash] Serialization options (see DotSerializer)
        # @return [String] DOT format string
        #
        # @example Basic export
        #   dot = Elkrb::Layout::LayoutEngine.export_dot(graph)
        #   File.write("output.dot", dot)
        #
        # @example With custom options
        #   dot = Elkrb::Layout::LayoutEngine.export_dot(
        #     graph,
        #     directed: true,
        #     rankdir: "LR",
        #     graph_name: "MyGraph"
        #   )
        def export_dot(graph, options = {})
          # Convert hash to Graph if needed
          graph = convert_to_graph(graph) if graph.is_a?(Hash)

          serializer = Elkrb::Serializers::DotSerializer.new
          serializer.serialize(graph, options)
        end

        # Returns metadata for all supported layout options.
        #
        # @return [Array<Hash>] Array of option metadata
        # @note Currently returns an empty array. Full implementation planned.
        def known_layout_options
          # TODO: Build from all algorithms' supported options
          []
        end

        private

        def convert_to_graph(hash)
          Graph::Graph.from_hash(hash)
        end
      end
    end
  end
end
