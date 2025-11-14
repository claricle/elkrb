# frozen_string_literal: true

require "lutaml/model"

module Elkrb
  module Graph
    class LayoutOptions < Lutaml::Model::Serializable
      attribute :algorithm, :string
      attribute :direction, :string
      attribute :spacing_node_node, :float
      attribute :spacing_edge_node, :float
      attribute :spacing_edge_edge, :float
      attribute :spacing_node_label, :float
      attribute :edge_routing, :string
      attribute :spline_curvature, :float
      attribute :spline_segments, :integer
      attribute :hierarchical, :boolean
      attribute :interactive_layout, :boolean
      attribute :aspect_ratio, :float
      attribute :node_placement_strategy, :string
      attribute :crossing_minimization_strategy, :string
      attribute :layer_constraint, :string
      attribute :cycle_breaking_strategy, :string
      attribute :properties, :hash

      json do
        map "algorithm", to: :algorithm
        map "direction", to: :direction
        map "spacing.nodeNode", to: :spacing_node_node
        map "spacing.edgeNode", to: :spacing_edge_node
        map "spacing.edgeEdge", to: :spacing_edge_edge
        map "spacing.nodeLabel", to: :spacing_node_label
        map "edgeRouting", to: :edge_routing
        map "elk.edgeRouting", to: :edge_routing
        map "spline.curvature", to: :spline_curvature
        map "elk.spline.curvature", to: :spline_curvature
        map "spline.segments", to: :spline_segments
        map "elk.spline.segments", to: :spline_segments
        map "hierarchical", to: :hierarchical
        map "interactiveLayout", to: :interactive_layout
        map "aspectRatio", to: :aspect_ratio
        map "nodePlacement.strategy", to: :node_placement_strategy
        map "crossingMinimization.strategy",
            to: :crossing_minimization_strategy
        map "layerConstraint", to: :layer_constraint
        map "cycleBreaking.strategy", to: :cycle_breaking_strategy
        map "properties", to: :properties
      end

      yaml do
        map "algorithm", to: :algorithm
        map "direction", to: :direction
        map "spacing_node_node", to: :spacing_node_node
        map "spacing_edge_node", to: :spacing_edge_node
        map "spacing_edge_edge", to: :spacing_edge_edge
        map "spacing_node_label", to: :spacing_node_label
        map "edge_routing", to: :edge_routing
        map "spline_curvature", to: :spline_curvature
        map "spline_segments", to: :spline_segments
        map "hierarchical", to: :hierarchical
        map "interactive_layout", to: :interactive_layout
        map "aspect_ratio", to: :aspect_ratio
        map "node_placement_strategy", to: :node_placement_strategy
        map "crossing_minimization_strategy",
            to: :crossing_minimization_strategy
        map "layer_constraint", to: :layer_constraint
        map "cycle_breaking_strategy", to: :cycle_breaking_strategy
        map "properties", to: :properties
      end

      def initialize(hash_or_attrs = {}, **attributes)
        # Handle both hash argument and keyword arguments
        if hash_or_attrs.is_a?(Hash) && attributes.empty?
          # Plain hash passed as first argument
          # Skip calling super and set defaults manually
          @properties = hash_or_attrs.transform_keys(&:to_s)
          @algorithm = nil
          @direction = nil
          @spacing_node_node = nil
          @spacing_edge_node = nil
          @spacing_edge_edge = nil
          @spacing_node_label = nil
          @edge_routing = nil
          @spline_curvature = nil
          @spline_segments = nil
          @hierarchical = nil
          @interactive_layout = nil
          @aspect_ratio = nil
          @node_placement_strategy = nil
          @crossing_minimization_strategy = nil
          @layer_constraint = nil
          @cycle_breaking_strategy = nil
        else
          # Keyword arguments
          super(**attributes)
          @properties ||= {}
        end
      end

      def []=(key, value)
        @properties[key.to_s] = value
      end

      def [](key)
        @properties[key.to_s]
      end

      def merge(other_options)
        return self unless other_options

        other_options.each do |key, value|
          self[key] = value
        end
        self
      end

      # Port constraint options

      # Get port constraints setting
      #
      # Port constraint values:
      # - "UNDEFINED" - No constraints (default)
      # - "FIXED_SIDE" - Port sides are fixed
      # - "FIXED_ORDER" - Port sides and order are fixed
      # - "FIXED_POS" - Port positions are completely fixed
      #
      # @return [String] The port constraints setting
      def port_constraints
        properties["elk.portConstraints"] ||
          properties["portConstraints"] ||
          "UNDEFINED"
      end

      # Set port constraints
      #
      # @param value [String] The port constraints value
      def port_constraints=(value)
        properties["elk.portConstraints"] = value
      end

      # Get port side assignment setting
      #
      # Port side assignment values:
      # - "AUTOMATIC" - Auto-detect from position (default)
      # - "MANUAL" - Use explicitly specified sides
      #
      # @return [String] The port side assignment setting
      def port_side_assignment
        properties["elk.portSideAssignment"] ||
          properties["portSideAssignment"] ||
          "AUTOMATIC"
      end

      # Set port side assignment
      #
      # @param value [String] The port side assignment value
      def port_side_assignment=(value)
        properties["elk.portSideAssignment"] = value
      end

      # Get port ordering setting
      #
      # Port ordering values:
      # - "DEFAULT" - Algorithm-specific default
      # - "INDEX" - Use port index attribute
      # - "OFFSET" - Use port offset/position
      #
      # @return [String] The port ordering setting
      def port_ordering
        properties["elk.portOrdering"] ||
          properties["portOrdering"] ||
          "DEFAULT"
      end

      # Set port ordering
      #
      # @param value [String] The port ordering value
      def port_ordering=(value)
        properties["elk.portOrdering"] = value
      end

      # Self-loop options

      # Get self-loop side setting
      #
      # Self-loop side values:
      # - "EAST" - Loop extends to the right (default)
      # - "WEST" - Loop extends to the left
      # - "NORTH" - Loop extends upward
      # - "SOUTH" - Loop extends downward
      #
      # @return [String] The self-loop side setting
      def self_loop_side
        properties["elk.selfLoopSide"] ||
          properties["selfLoopSide"] ||
          "EAST"
      end

      # Set self-loop side
      #
      # @param value [String] The self-loop side value
      def self_loop_side=(value)
        properties["elk.selfLoopSide"] = value
      end

      # Get self-loop offset setting
      #
      # Controls the base distance the self-loop extends from the node.
      # Multiple self-loops on the same node will use increasing offsets.
      #
      # @return [Float] The self-loop offset (default: 20.0)
      def self_loop_offset
        (properties["elk.selfLoopOffset"] ||
         properties["selfLoopOffset"] ||
         20.0).to_f
      end

      # Set self-loop offset
      #
      # @param value [Float] The self-loop offset value
      def self_loop_offset=(value)
        properties["elk.selfLoopOffset"] = value
      end

      # Get self-loop routing style
      #
      # Self-loop routing values:
      # - "ORTHOGONAL" - Rectangular path with 90-degree corners (default)
      # - "SPLINES" - Smooth curved path using Bezier curves
      # - "POLYLINE" - Simple polyline path
      #
      # @return [String] The self-loop routing style
      def self_loop_routing
        properties["elk.selfLoopRouting"] ||
          properties["selfLoopRouting"] ||
          "ORTHOGONAL"
      end

      # Set self-loop routing style
      #
      # @param value [String] The self-loop routing style value
      def self_loop_routing=(value)
        properties["elk.selfLoopRouting"] = value
      end
    end
  end
end
