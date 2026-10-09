# frozen_string_literal: true

require_relative "../edge_router"
require_relative "../hierarchical_processor"
require_relative "../label_placer"
require_relative "../port_constraint_processor"
require_relative "../constraints/constraint_processor"
require_relative "../../options/resolver"

module Elkrb
  module Layout
    module Algorithms
      # Base class for all layout algorithms
      #
      # Layout algorithms are responsible for computing positions for nodes
      # and routing paths for edges in a graph. Each algorithm implements
      # a specific layout strategy (e.g., hierarchical, force-directed, etc.)
      class BaseAlgorithm
        include EdgeRouter
        include HierarchicalProcessor
        include LabelPlacer
        include PortConstraintProcessor

        attr_reader :options, :resolver

        def initialize(options = {})
          @options = options
          @resolver = Options::Resolver.new(options)
        end

        # Default a node's unset x/y to 0.0, matching Java ELK's treatment
        # of an unset position. Shared by algorithms (currently SporeOverlap
        # and SporeCompaction) that read node.x/node.y arithmetically before
        # any other pass has had a chance to assign them. A class method
        # because it depends only on its argument, never on an instance's
        # state (reek: UtilityFunction fires on the instance-method form).
        #
        # @param nodes [Array<Elkrb::Graph::Node>] The nodes to normalize
        def self.normalize_nil_positions(nodes)
          nodes.each do |node|
            node.x ||= 0.0
            node.y ||= 0.0
          end
        end

        # Main layout method - handles hierarchical graphs and labels.
        #
        # Subclasses should implement #layout_flat for their specific
        # algorithm logic. This method sizes compound children bottom-up, then
        # lays out this level and places its labels.
        #
        # @param graph [Elkrb::Graph::Graph] The graph to layout
        # @return [Elkrb::Graph::Graph] The graph with updated positions
        def layout(graph)
          @graph = graph

          # Compound sizes must be known before their own ports or the parent
          # level are laid out. Each child algorithm recursively sizes deeper
          # compounds before returning.
          size_compound_children(graph) if graph.hierarchical?

          apply_port_constraints(graph)
          processor = apply_pre_layout_constraints(graph)

          # Only nil (children key absent from deserialized
          # input) skips dispatch — an explicit empty array still reaches
          # layout_flat, preserving its documented NotImplementedError
          # contract for subclasses that don't override it.
          layout_flat(graph, @options) if graph.children
          enforce_post_layout_constraints(graph, processor)
          apply_edge_routing(graph)
          route_cross_level_edges(graph)
          place_labels(graph) unless
            option("label.placement.disabled", default: false)

          graph
        end

        # Layout a flat (non-hierarchical) graph
        #
        # This method must be implemented by subclasses with their specific
        # layout algorithm logic.
        #
        # @param graph [Elkrb::Graph::Graph] The graph to layout
        # @param options [Hash] Layout options
        # @return [Elkrb::Graph::Graph] The graph with updated positions
        def layout_flat(graph, options = {})
          raise NotImplementedError,
                "#{self.class.name} must implement #layout_flat method"
        end

        protected

        # Get an option value, resolved against the graph being laid out and
        # then the call-level options (see Options::Resolver for the rule).
        #
        # @param key [String, Symbol] The option id, alias, or custom key
        # @param default [Object] Returned when nothing names the option;
        #   :registry means the registry default, nil means nil
        # @return [Object] The option value or default
        def option(key, default: :registry)
          @resolver.get(key, @graph, default: default)
        end

        def rng
          @rng ||= ::Random.new(option("elk.randomSeed").to_i)
        end

        # Get spacing between nodes
        #
        # @return [Float] The node spacing value
        def node_spacing
          option("elk.spacing.nodeNode").to_f
        end

        # Get padding values
        #
        # @return [Hash] Padding values for top, bottom, left, right
        def padding
          option("elk.padding").to_h
        end

        # Calculate the bounding box for a set of nodes
        #
        # @param nodes [Array<Elkrb::Graph::Node>] The nodes
        # @return [Elkrb::Geometry::Rectangle] The bounding rectangle
        def calculate_bounding_box(nodes)
          return Elkrb::Geometry::Rectangle.new(0, 0, 0, 0) if nodes.empty?

          min_x = nodes.map { |n| n.x || 0.0 }.min
          min_y = nodes.map { |n| n.y || 0.0 }.min
          max_x = nodes.map { |n| (n.x || 0.0) + (n.width || 0.0) }.max
          max_y = nodes.map { |n| (n.y || 0.0) + (n.height || 0.0) }.max

          Elkrb::Geometry::Rectangle.new(
            min_x,
            min_y,
            max_x - min_x,
            max_y - min_y,
          )
        end

        # Apply padding to graph dimensions
        #
        # @param graph [Elkrb::Graph::Graph] The graph
        def apply_padding(graph)
          return if graph.children.nil? || graph.children.empty?

          pad = padding
          bbox = calculate_bounding_box(graph.children)

          # Shift all nodes by padding
          graph.children.each do |node|
            node.x = node.x - bbox.x + pad[:left]
            node.y = node.y - bbox.y + pad[:top]
          end

          # Set graph dimensions
          graph.width = bbox.width + pad[:left] + pad[:right]
          graph.height = bbox.height + pad[:top] + pad[:bottom]
        end

        # Apply edge routing based on routing style option
        #
        # @param graph [Elkrb::Graph::Graph] The graph
        def apply_edge_routing(graph)
          route_edges(graph)
        end

        # Defined in EdgeRouter. Released as a protected method here, so
        # subclasses override it and call super.
        protected :get_edge_routing_style

        # Apply pre-layout constraints
        #
        # @param graph [Elkrb::Graph::Graph] The graph
        # @return [Constraints::ConstraintProcessor] the processor holding the
        #   state #enforce_post_layout_constraints needs
        def apply_pre_layout_constraints(graph)
          # Only read the spacing option when a constraint needs it, so a
          # graph without constraints never resolves an option it did not
          # resolve before.
          constrained = graph.children&.any?(&:constraints)
          processor = Constraints::ConstraintProcessor.new(
            spacing: constrained ? node_spacing : 0.0,
          )
          processor.apply_pre_layout(graph)
          processor
        end

        # Enforce post-layout constraints
        #
        # These constraints adjust positions after layout algorithm runs.
        #
        # @param graph [Elkrb::Graph::Graph] The graph
        # @param processor [Constraints::ConstraintProcessor] the processor
        #   returned by #apply_pre_layout_constraints
        def enforce_post_layout_constraints(graph, processor)
          processor.enforce_post_layout(graph)

          processor.validate_all(graph).each do |error|
            Elkrb.logger.warn("Layout constraint violation: #{error}")
          end
        end
      end
    end
  end
end
