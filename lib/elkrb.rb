# frozen_string_literal: true

require_relative "elkrb/version"
require_relative "elkrb/errors"

# Geometry
require_relative "elkrb/geometry/point"
require_relative "elkrb/geometry/dimension"
require_relative "elkrb/geometry/rectangle"
require_relative "elkrb/geometry/vector"

# Graph models
require_relative "elkrb/graph/layout_options"
require_relative "elkrb/graph/label"
require_relative "elkrb/graph/port"
require_relative "elkrb/graph/node_constraints"
require_relative "elkrb/graph/edge"
require_relative "elkrb/graph/node"
require_relative "elkrb/graph/graph"

# Serializers
require_relative "elkrb/serializers/dot_serializer"

# Options parsers
require_relative "elkrb/options/elk_padding"
require_relative "elkrb/options/k_vector"
require_relative "elkrb/options/k_vector_chain"

# Layout constraints
require_relative "elkrb/layout/constraints/base_constraint"
require_relative "elkrb/layout/constraints/fixed_position_constraint"
require_relative "elkrb/layout/constraints/alignment_constraint"
require_relative "elkrb/layout/constraints/layer_constraint"
require_relative "elkrb/layout/constraints/relative_position_constraint"
require_relative "elkrb/layout/constraints/constraint_processor"

# Layout engine
require_relative "elkrb/layout/algorithm_registry"
require_relative "elkrb/layout/layout_engine"
require_relative "elkrb/layout/algorithms/base_algorithm"
require_relative "elkrb/layout/algorithms/random"
require_relative "elkrb/layout/algorithms/fixed"
require_relative "elkrb/layout/algorithms/box"
require_relative "elkrb/layout/algorithms/layered"
require_relative "elkrb/layout/algorithms/force"
require_relative "elkrb/layout/algorithms/stress"
require_relative "elkrb/layout/algorithms/mrtree"
require_relative "elkrb/layout/algorithms/radial"
require_relative "elkrb/layout/algorithms/rectpacking"
require_relative "elkrb/layout/algorithms/topdown_packing"
require_relative "elkrb/layout/algorithms/disco"
require_relative "elkrb/layout/algorithms/spore_overlap"
require_relative "elkrb/layout/algorithms/spore_compaction"
require_relative "elkrb/layout/algorithms/libavoid"
require_relative "elkrb/layout/algorithms/vertiflex"

# ElkRb - Pure Ruby implementation of the Eclipse Layout Kernel
#
# ElkRb provides automatic graph layout algorithms for node-link diagrams.
# It implements 12 layout algorithms from the Eclipse Layout Kernel (ELK),
# supporting hierarchical graphs, port-based connections, and automatic
# label placement.
#
# @example Basic usage
#   require 'elkrb'
#
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
#
#   result = Elkrb.layout(graph)
#   puts result[:children][0][:x]  # Node positions computed
#
# @example Using model classes
#   graph = Elkrb::Graph::Graph.new(id: "root")
#   node = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60)
#   graph.children = [node]
#
#   result = Elkrb.layout(graph, algorithm: "force")
#
# @example Querying available algorithms
#   Elkrb.known_layout_algorithms.each do |alg|
#     puts "#{alg[:id]}: #{alg[:description]}"
#   end
#
# @see https://www.eclipse.org/elk/ Eclipse Layout Kernel
# @see https://github.com/kieler/elkjs elkjs - JavaScript port
module Elkrb
  # Register basic layout algorithms
  Layout::AlgorithmRegistry.register(
    "random",
    Layout::Algorithms::Random,
    {
      name: "Random",
      description: "Places nodes at random positions",
    },
  )

  Layout::AlgorithmRegistry.register(
    "fixed",
    Layout::Algorithms::Fixed,
    {
      name: "Fixed",
      description: "Keeps nodes at their current positions",
    },
  )

  Layout::AlgorithmRegistry.register(
    "box",
    Layout::Algorithms::Box,
    {
      name: "Box",
      description: "Arranges nodes in a grid pattern",
    },
  )

  Layout::AlgorithmRegistry.register(
    "layered",
    Layout::Algorithms::LayeredAlgorithm,
    {
      name: "Layered (Sugiyama)",
      description: "Hierarchical layout using the Sugiyama framework",
      category: "hierarchical",
      supports_hierarchy: true,
    },
  )

  Layout::AlgorithmRegistry.register(
    "force",
    Layout::Algorithms::Force,
    {
      name: "Force-Directed",
      description: "Physics-based layout using attractive and repulsive forces",
      category: "force",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "stress",
    Layout::Algorithms::Stress,
    {
      name: "Stress Minimization",
      description: "High-quality layout using stress majorization",
      category: "force",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "mrtree",
    Layout::Algorithms::MRTree,
    {
      name: "Multi-Rooted Tree",
      description: "Tree layout supporting multiple root nodes",
      category: "hierarchical",
      supports_hierarchy: true,
    },
  )

  Layout::AlgorithmRegistry.register(
    "radial",
    Layout::Algorithms::Radial,
    {
      name: "Radial",
      description: "Circular/radial node arrangement",
      category: "general",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "rectpacking",
    Layout::Algorithms::RectPacking,
    {
      name: "Rectangle Packing",
      description: "Efficient rectangle bin packing layout",
      category: "packing",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "topdownpacking",
    Layout::Algorithms::TopdownPacking,
    {
      name: "TopdownPacking",
      description: "Top-down rectangle packing with hierarchical space partitioning",
      category: "packing",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "disco",
    Layout::Algorithms::Disco,
    {
      name: "DISCO",
      description: "Layout for disconnected graph components",
      category: "general",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "spore_overlap",
    Layout::Algorithms::SporeOverlap,
    {
      name: "SPOrE Overlap Removal",
      description: "Removes node overlaps while preserving structure",
      category: "optimization",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "spore_compaction",
    Layout::Algorithms::SporeCompaction,
    {
      name: "SPOrE Compaction",
      description: "Compacts layout by removing whitespace",
      category: "optimization",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "libavoid",
    Layout::Algorithms::Libavoid,
    {
      name: "Libavoid",
      description: "Orthogonal connector routing with obstacle avoidance",
      category: "routing",
      supports_hierarchy: false,
    },
  )

  Layout::AlgorithmRegistry.register(
    "vertiflex",
    Layout::Algorithms::VertiFlex,
    {
      name: "VertiFlex",
      description: "Vertical flexible layout with column-based arrangement",
      category: "layered",
      supports_hierarchy: false,
      experimental: true,
    },
  )

  # Performs layout on a graph using the specified algorithm.
  #
  # This is the main entry point for ElkRb. It accepts either a Hash or
  # a Graph model object and applies the chosen layout algorithm to compute
  # node positions and edge routes.
  #
  # @param graph [Hash, Graph::Graph] The graph to layout
  # @param options [Hash] Layout options including:
  #   - :algorithm (String) - Algorithm name (default: "layered")
  #   - Algorithm-specific options (e.g., "elk.spacing.nodeNode")
  # @return [Graph::Graph] The input graph with computed positions
  #
  # @example With hash input
  #   result = Elkrb.layout({
  #     id: "root",
  #     children: [{ id: "n1", width: 100, height: 60 }]
  #   })
  #
  # @example With specific algorithm
  #   result = Elkrb.layout(graph, algorithm: "force")
  #
  # @example With algorithm options
  #   result = Elkrb.layout(graph,
  #     algorithm: "layered",
  #     "elk.direction" => "DOWN",
  #     "elk.spacing.nodeNode" => 50
  #   )
  def self.layout(graph, options = {})
    Layout::LayoutEngine.layout(graph, options)
  end

  # Exports a graph to Graphviz DOT format.
  #
  # This is a convenience method that delegates to the LayoutEngine.
  # It serializes an ELK graph structure to DOT format that can be
  # rendered by Graphviz or other DOT-compatible tools.
  #
  # @param graph [Hash, Graph::Graph] The graph to export
  # @param options [Hash] Serialization options:
  #   - :directed (Boolean) - Whether graph is directed (default: true)
  #   - :rankdir (String) - Layout direction (TB, LR, BT, RL)
  #   - :graph_name (String) - Name for the graph (default: "G")
  #   - :graph_attrs (Hash) - Additional graph attributes
  #   - :node_attrs (Hash) - Default node attributes
  #   - :edge_attrs (Hash) - Default edge attributes
  # @return [String] DOT format string
  #
  # @example Basic export
  #   dot = Elkrb.export_dot(graph)
  #   File.write("output.dot", dot)
  #
  # @example Layout then export
  #   graph = Elkrb.layout(graph, algorithm: "layered")
  #   dot = Elkrb.export_dot(graph, rankdir: "LR")
  #   File.write("output.dot", dot)
  #
  # @example With custom attributes
  #   dot = Elkrb.export_dot(graph,
  #     graph_name: "MyGraph",
  #     graph_attrs: { bgcolor: "lightgray" },
  #     node_attrs: { shape: "box", color: "blue" }
  #   )
  def self.export_dot(graph, options = {})
    Layout::LayoutEngine.export_dot(graph, options)
  end

  # Registers a custom layout algorithm.
  #
  # This allows you to extend ElkRb with your own layout algorithms.
  # The algorithm class must implement the layout interface (inherit from
  # BaseAlgorithm or implement a compatible interface).
  #
  # @param name [String] Unique algorithm identifier
  # @param algorithm_class [Class] Algorithm implementation class
  # @param metadata [Hash] Optional metadata:
  #   - :name (String) - Display name
  #   - :description (String) - Brief description
  #   - :category (String) - Algorithm category
  #   - :supports_hierarchy (Boolean) - Hierarchical support
  #
  # @example Register custom algorithm
  #   class MyAlgorithm < Elkrb::Layout::Algorithms::BaseAlgorithm
  #     def layout_flat(graph, options = {})
  #       # Custom layout logic
  #       graph
  #     end
  #   end
  #
  #   Elkrb.register_algorithm("my_algo", MyAlgorithm, {
  #     name: "My Algorithm",
  #     description: "Custom layout algorithm",
  #     category: "general"
  #   })
  #
  #   # Use it
  #   Elkrb.layout(graph, algorithm: "my_algo")
  def self.register_algorithm(name, algorithm_class, metadata = {})
    Layout::AlgorithmRegistry.register(name, algorithm_class, metadata)
  end

  # Returns metadata for all available layout algorithms.
  #
  # This includes the 12 built-in algorithms plus any custom algorithms
  # registered via {register_algorithm}.
  #
  # @return [Array<Hash>] Array of algorithm metadata with keys:
  #   - :id (String) - Algorithm identifier
  #   - :name (String) - Display name
  #   - :description (String) - Brief description
  #   - :category (String) - Algorithm category
  #   - :supports_hierarchy (Boolean) - Whether it supports nested graphs
  #
  # @example List all algorithms
  #   Elkrb.known_layout_algorithms.each do |alg|
  #     puts "#{alg[:id]}: #{alg[:description]}"
  #   end
  #
  # @example Filter by category
  #   force_algorithms = Elkrb.known_layout_algorithms
  #     .select { |alg| alg[:category] == "force" }
  def self.known_layout_algorithms
    Layout::AlgorithmRegistry.all.map do |name, data|
      {
        id: name,
        name: data[:metadata][:name] || name.capitalize,
        description: data[:metadata][:description] || "",
        category: data[:metadata][:category] || "general",
        supports_hierarchy: data[:metadata][:supports_hierarchy] || false,
      }
    end
  end

  # Returns metadata for all supported layout options.
  #
  # This includes common options like algorithm selection, spacing,
  # direction, and padding, as well as algorithm-specific options.
  #
  # @return [Hash{String => Hash}] Hash mapping option names to metadata.
  #   Each metadata hash contains:
  #   - :type (String) - Option value type
  #   - :description (String) - Brief description
  #   - :default - Default value
  #   - :values (Array, nil) - Allowed values for enum types
  #   - :parser (String, nil) - Parser class for complex types
  #
  # @example Query options
  #   options = Elkrb.known_layout_options
  #   puts options["elk.direction"][:description]
  #   # => "Overall direction of layout"
  #
  # @example Get allowed values
  #   directions = Elkrb.known_layout_options["elk.direction"][:values]
  #   # => ["UP", "DOWN", "LEFT", "RIGHT"]
  def self.known_layout_options
    {
      "algorithm" => {
        type: "string",
        description: "The layout algorithm to use",
        default: "layered",
        values: Layout::AlgorithmRegistry.all.keys,
      },
      "elk.direction" => {
        type: "string",
        description: "Overall direction of layout",
        default: "RIGHT",
        values: %w[UP DOWN LEFT RIGHT],
      },
      "elk.spacing.nodeNode" => {
        type: "float",
        description: "Spacing between nodes",
        default: 20.0,
      },
      "elk.padding" => {
        type: "ElkPadding",
        description: "Padding around the graph",
        default: "[left=12, top=12, right=12, bottom=12]",
        parser: "Elkrb::Options::ElkPadding",
      },
      "position" => {
        type: "KVector",
        description: "Fixed position for nodes (when using fixed algorithm)",
        default: nil,
        parser: "Elkrb::Options::KVector",
      },
      "bendPoints" => {
        type: "KVectorChain",
        description: "Bend points for edges",
        default: nil,
        parser: "Elkrb::Options::KVectorChain",
      },
    }
  end

  # Returns metadata for layout option categories.
  #
  # Categories help organize the many layout options into logical groups.
  # There are 9 categories covering different aspects of layout.
  #
  # @return [Hash{String => Hash}] Hash mapping category names to metadata.
  #   Each metadata hash contains:
  #   - :name (String) - Display name
  #   - :description (String) - Brief description
  #
  # @example List categories
  #   Elkrb.known_layout_categories.each do |id, info|
  #     puts "#{id}: #{info[:description]}"
  #   end
  #
  # @example Get specific category
  #   force_category = Elkrb.known_layout_categories["force"]
  #   puts force_category[:name]  # => "Force-Directed"
  def self.known_layout_categories
    {
      "general" => {
        name: "General",
        description: "General layout options",
      },
      "spacing" => {
        name: "Spacing",
        description: "Options for controlling spacing between elements",
      },
      "alignment" => {
        name: "Alignment",
        description: "Options for controlling element alignment",
      },
      "direction" => {
        name: "Direction",
        description: "Options for controlling layout direction",
      },
      "ports" => {
        name: "Ports",
        description: "Options for port handling",
      },
      "edges" => {
        name: "Edges",
        description: "Options for edge routing",
      },
      "hierarchical" => {
        name: "Hierarchical",
        description: "Options for hierarchical layouts",
      },
      "force" => {
        name: "Force-Directed",
        description: "Options for force-directed layouts",
      },
      "optimization" => {
        name: "Optimization",
        description: "Options for layout optimization algorithms",
      },
    }
  end
end
