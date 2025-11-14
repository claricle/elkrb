# frozen_string_literal: true

module Elkrb
  module Layout
    # Module to add hierarchical graph layout support to algorithms.
    # Handles recursive layout, parent-child constraints, and cross-hierarchy
    # edges.
    module HierarchicalProcessor
      # Layout a graph and all its hierarchical children recursively.
      #
      # @param graph [Graph::Graph] The graph to layout
      # @param options [Hash] Layout options
      # @return [Graph::Graph] The laid out graph
      def layout_hierarchical(graph, options = {})
        return layout_flat(graph, options) unless graph.hierarchical?

        # First, recursively layout all child nodes
        layout_children_recursively(graph)

        # Then layout the top-level graph
        layout_flat(graph, options)

        # Apply parent constraints
        apply_parent_constraints(graph)

        # Handle cross-hierarchy edges
        handle_cross_hierarchy_edges(graph)

        # Update parent bounds
        update_parent_bounds(graph)

        graph
      end

      private

      # Layout all children of nodes in the graph recursively.
      def layout_children_recursively(graph)
        return unless graph.children

        graph.children.each do |node|
          next unless node.hierarchical?

          # Create a temporary graph for the node's children
          child_graph = create_child_graph(node)

          # Recursively layout the child graph
          layout_hierarchical(child_graph, extract_node_options(node))

          # Apply the layout back to the node
          apply_child_layout(node, child_graph)
        end
      end

      # Layout a flat (non-hierarchical) graph using the base algorithm.
      def layout_flat(graph, options = {})
        # This should be implemented by the including algorithm class
        raise NotImplementedError,
              "#{self.class.name} must implement #layout_flat"
      end

      # Create a temporary graph from a node's children.
      def create_child_graph(node)
        Graph::Graph.new(
          id: "#{node.id}_children",
          children: node.children || [],
          edges: node.edges || [],
          layout_options: node.layout_options,
        )
      end

      # Extract layout options from a node.
      def extract_node_options(node)
        return {} unless node.layout_options

        node.layout_options.properties || {}
      end

      # Apply the child graph layout back to the parent node.
      def apply_child_layout(node, child_graph)
        # Copy positions from child_graph children to node children
        return unless child_graph.children

        child_graph.children.each_with_index do |child, index|
          if node.children && node.children[index]
            node.children[index].x = child.x
            node.children[index].y = child.y
            node.children[index].width = child.width
            node.children[index].height = child.height
          end
        end
      end

      # Apply parent constraints to ensure children fit within parent bounds.
      def apply_parent_constraints(graph)
        return unless graph.children

        graph.children.each do |node|
          next unless node.hierarchical?

          # Get padding from node options
          padding = get_padding(node)

          # Adjust child positions to account for padding
          adjust_children_for_padding(node, padding)

          # Recursively apply to nested children
          if node.children
            temp_graph = Graph::Graph.new(children: node.children)
            apply_parent_constraints(temp_graph)
          end
        end
      end

      # Get padding for a node from its layout options.
      def get_padding(node)
        return default_padding unless node.layout_options

        padding_option = node.layout_options.properties&.[]("padding") ||
          node.layout_options.properties&.[]("elk.padding")

        return default_padding unless padding_option

        parse_padding(padding_option)
      end

      # Default padding values.
      def default_padding
        { top: 12.0, right: 12.0, bottom: 12.0, left: 12.0 }
      end

      # Parse padding from various formats.
      def parse_padding(padding)
        case padding
        when Hash
          {
            top: padding[:top] || padding["top"] || 12.0,
            right: padding[:right] || padding["right"] || 12.0,
            bottom: padding[:bottom] || padding["bottom"] || 12.0,
            left: padding[:left] || padding["left"] || 12.0,
          }
        when Numeric
          { top: padding, right: padding, bottom: padding, left: padding }
        else
          default_padding
        end
      end

      # Adjust children positions to account for parent padding.
      def adjust_children_for_padding(node, padding)
        return unless node.children

        node.children.each do |child|
          child.x = (child.x || 0.0) + padding[:left]
          child.y = (child.y || 0.0) + padding[:top]
        end
      end

      # Handle edges that cross hierarchy boundaries.
      def handle_cross_hierarchy_edges(graph)
        return unless graph.edges

        graph.edges.each do |edge|
          # Get source and target IDs from edge
          source_id = edge.sources&.first
          target_id = edge.targets&.first

          next unless source_id && target_id

          source_node = find_node_in_hierarchy(graph, source_id)
          target_node = find_node_in_hierarchy(graph, target_id)

          next unless source_node && target_node

          # Check if edge crosses hierarchy levels
          if crosses_hierarchy?(source_node, target_node, graph)
            adjust_edge_for_hierarchy(edge, source_node, target_node)
          end
        end
      end

      # Find a node anywhere in the graph hierarchy.
      def find_node_in_hierarchy(graph, node_id)
        return nil unless node_id

        # Handle both direct node IDs and port IDs
        node_id_str = node_id.is_a?(String) ? node_id : node_id.to_s
        graph.find_node(node_id_str)
      end

      # Check if an edge crosses hierarchy boundaries.
      def crosses_hierarchy?(source_node, target_node, graph)
        return false unless source_node && target_node

        source_depth = node_depth(source_node, graph)
        target_depth = node_depth(target_node, graph)

        source_depth != target_depth
      end

      # Calculate the depth of a node in the hierarchy.
      def node_depth(node, graph, depth = 0)
        return depth if graph.children&.include?(node)

        graph.children&.each do |child|
          if child.hierarchical? && child.children
            child_graph = Graph::Graph.new(children: child.children)
            found_depth = node_depth(node, child_graph, depth + 1)
            return found_depth if found_depth > depth
          end
        end

        depth
      end

      # Adjust edge routing for cross-hierarchy edges.
      def adjust_edge_for_hierarchy(edge, _source_node, _target_node)
        # Add additional bend points to route around parent boundaries
        # This is a simplified version - could be enhanced with proper routing
        return unless edge.sections && !edge.sections.empty?

        section = edge.sections.first

        # Calculate midpoint
        mid_x = (section.start_point.x + section.end_point.x) / 2.0
        mid_y = (section.start_point.y + section.end_point.y) / 2.0

        # Add a bend point at the midpoint
        section.add_bend_point(mid_x, mid_y)
      end

      # Update parent node bounds to contain all children.
      def update_parent_bounds(graph)
        return unless graph.children

        graph.children.each do |node|
          next unless node.hierarchical?

          # Recursively update nested children first
          if node.children
            temp_graph = Graph::Graph.new(children: node.children)
            update_parent_bounds(temp_graph)
          end

          # Calculate bounds from children
          bounds = calculate_children_bounds(node)

          # Get padding
          padding = get_padding(node)

          # Update node dimensions
          node.width = bounds[:width] + padding[:left] + padding[:right]
          node.height = bounds[:height] + padding[:top] + padding[:bottom]

          # Update position if needed (ensure children are at positive coords)
          if bounds[:min_x].negative?
            offset_x = -bounds[:min_x] + padding[:left]
            node.children&.each { |child| child.x = (child.x || 0) + offset_x }
          end

          if bounds[:min_y].negative?
            offset_y = -bounds[:min_y] + padding[:top]
            node.children&.each { |child| child.y = (child.y || 0) + offset_y }
          end
        end
      end

      # Calculate the bounding box of a node's children.
      def calculate_children_bounds(node)
        return { min_x: 0, min_y: 0, width: 0, height: 0 } unless
          node.children && !node.children.empty?

        min_x = Float::INFINITY
        min_y = Float::INFINITY
        max_x = -Float::INFINITY
        max_y = -Float::INFINITY

        node.children.each do |child|
          x = child.x || 0.0
          y = child.y || 0.0
          w = child.width || 0.0
          h = child.height || 0.0

          min_x = [min_x, x].min
          min_y = [min_y, y].min
          max_x = [max_x, x + w].max
          max_y = [max_y, y + h].max
        end

        {
          min_x: min_x,
          min_y: min_y,
          width: max_x - min_x,
          height: max_y - min_y,
        }
      end
    end
  end
end
