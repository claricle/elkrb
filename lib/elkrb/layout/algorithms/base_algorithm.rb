# frozen_string_literal: true

require_relative "../edge_router"
require_relative "../hierarchical_processor"
require_relative "../label_placer"
require_relative "../port_constraint_processor"
require_relative "../constraints/constraint_processor"

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

        attr_reader :options

        def initialize(options = {})
          @options = options
        end

        # Main layout method - automatically handles hierarchical graphs and labels
        #
        # Subclasses should implement #layout_flat for their specific
        # algorithm logic. This method will automatically handle hierarchical
        # graphs by calling layout_hierarchical when needed, and place labels
        # after layout is complete.
        #
        # @param graph [Elkrb::Graph::Graph] The graph to layout
        # @return [Elkrb::Graph::Graph] The graph with updated positions
        def layout(graph)
          # Apply port constraints before layout
          apply_port_constraints(graph)

          # Apply pre-layout constraints (marks nodes)
          apply_pre_layout_constraints(graph)

          # Perform layout
          if option("hierarchical", false) || graph.hierarchical?
            layout_hierarchical(graph, @options)
          else
            layout_flat(graph, @options)
          end

          # Enforce post-layout constraints (adjust positions)
          enforce_post_layout_constraints(graph)

          # Apply edge routing
          apply_edge_routing(graph)

          # Place labels after layout (unless disabled)
          unless option("label.placement.disabled", false)
            place_labels(graph)
          end

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

        # Get an option value with a default fallback
        #
        # @param key [String, Symbol] The option key
        # @param default [Object] The default value if option is not set
        # @return [Object] The option value or default
        def option(key, default = nil)
          key_str = key.to_s
          @options[key_str] || @options[key.to_sym] || default
        end

        # Get spacing between nodes
        #
        # @return [Float] The node spacing value
        def node_spacing
          option("spacing_node_node", 20.0).to_f
        end

        # Get padding values
        #
        # @return [Hash] Padding values for top, bottom, left, right
        def padding
          default_padding = { top: 12, bottom: 12, left: 12, right: 12 }
          padding_opt = option("padding", default_padding)

          if padding_opt.is_a?(Hash)
            default_padding.merge(padding_opt)
          else
            default_padding
          end
        end

        # Calculate the bounding box for a set of nodes
        #
        # @param nodes [Array<Elkrb::Graph::Node>] The nodes
        # @return [Elkrb::Geometry::Rectangle] The bounding rectangle
        def calculate_bounding_box(nodes)
          return Elkrb::Geometry::Rectangle.new(0, 0, 0, 0) if nodes.empty?

          min_x = nodes.map(&:x).min
          min_y = nodes.map(&:y).min
          max_x = nodes.map { |n| n.x + n.width }.max
          max_y = nodes.map { |n| n.y + n.height }.max

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
          routing_style = get_edge_routing_style(graph)
          route_edges(graph, nil, routing_style)
        end

        # Get edge routing style from graph options
        #
        # @param graph [Elkrb::Graph::Graph] The graph
        # @return [String] Routing style (ORTHOGONAL, POLYLINE, SPLINES)
        def get_edge_routing_style(graph)
          return "ORTHOGONAL" unless graph.layout_options

          style = graph.layout_options["elk.edgeRouting"] ||
            graph.layout_options["edgeRouting"] ||
            graph.layout_options.edge_routing ||
            option("elk.edgeRouting") ||
            option("edgeRouting")

          style ? style.to_s.upcase : "ORTHOGONAL"
        end

        # Apply pre-layout constraints
        #
        # These constraints mark nodes for special algorithm handling.
        #
        # @param graph [Elkrb::Graph::Graph] The graph
        def apply_pre_layout_constraints(graph)
          processor = Constraints::ConstraintProcessor.new
          processor.apply_pre_layout(graph)
        end

        # Enforce post-layout constraints
        #
        # These constraints adjust positions after layout algorithm runs.
        #
        # @param graph [Elkrb::Graph::Graph] The graph
        def enforce_post_layout_constraints(graph)
          processor = Constraints::ConstraintProcessor.new
          processor.enforce_post_layout(graph)

          # Validate all constraints
          errors = processor.validate_all(graph)

          return if errors.empty?

          # Log warnings for constraint violations
          errors.each do |error|
            warn "Layout constraint violation: #{error}"
          end
        end
      end
    end
  end
end
