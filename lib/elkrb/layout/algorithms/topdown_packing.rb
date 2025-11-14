# frozen_string_literal: true

require_relative "base_algorithm"

module Elkrb
  module Layout
    module Algorithms
      # TopdownPacking layout algorithm
      #
      # Arranges nodes in a grid using top-down, left-right placement.
      # Unlike RectPacking which uses shelf-based bin packing, TopdownPacking
      # arranges nodes in a uniform grid, making it ideal for:
      # - Treemap-style layouts
      # - Dashboard tile arrangements
      # - Hierarchical layouts with uniform node sizes
      #
      # The algorithm calculates grid dimensions to approximate a square
      # aspect ratio, then places nodes from left to right, top to bottom.
      class TopdownPacking < BaseAlgorithm
        def initialize(options = {})
          super
        end

        # Layout nodes in a grid using top-down packing
        #
        # @param graph [Elkrb::Graph::Graph] The graph to layout
        # @param options [Hash] Layout options
        # @return [Elkrb::Graph::Graph] The graph with updated positions
        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          if graph.children.size == 1
            # Single node at origin
            graph.children.first.x = 0.0
            graph.children.first.y = 0.0
            apply_padding(graph)
            return graph
          end

          # Calculate grid dimensions
          nodes = graph.children
          grid_dims = calculate_grid_dimensions(nodes.size)
          cols = grid_dims[:cols]
          rows = grid_dims[:rows]

          # Get node dimensions (uniform for grid layout)
          node_dims = calculate_node_dimensions(graph, nodes, cols, rows)
          node_width = node_dims[:width]
          node_height = node_dims[:height]

          # Place nodes in grid
          place_nodes_in_grid(nodes, cols, node_width, node_height)

          apply_padding(graph)

          graph
        end

        private

        # Calculate grid dimensions to approximate square aspect ratio
        #
        # Uses the formula from the Java implementation:
        # cols = ceil(sqrt(N))
        # rows = cols if N > cols^2 - cols, else cols - 1
        #
        # @param node_count [Integer] Number of nodes to arrange
        # @return [Hash] Grid dimensions with :cols and :rows
        def calculate_grid_dimensions(node_count)
          return { cols: 0, rows: 0 } if node_count.zero?

          # Calculate columns to approximate square
          cols = Math.sqrt(node_count).ceil

          # Calculate rows based on remaining nodes
          # This ensures we don't have an empty last row
          rows = if node_count > (cols * cols) - cols || cols.zero?
                   cols
                 else
                   cols - 1
                 end

          { cols: cols, rows: rows }
        end

        # Calculate uniform node dimensions for grid cells
        #
        # @param graph [Elkrb::Graph::Graph] The graph
        # @param nodes [Array<Elkrb::Graph::Node>] The nodes
        # @param cols [Integer] Number of columns
        # @param rows [Integer] Number of rows
        # @return [Hash] Node dimensions with :width and :height
        def calculate_node_dimensions(graph, nodes, cols, rows)
          if nodes.empty? || cols.zero? || rows.zero?
            return { width: 0.0,
                     height: 0.0 }
          end

          # Get options from graph layout options
          layout_opts = graph.layout_options || {}

          # Get target aspect ratio (default: 1.0 for square cells)
          target_aspect_ratio = get_option(layout_opts,
                                           "topdownpacking.aspectRatio", 1.0).to_f
          target_aspect_ratio = 1.0 if target_aspect_ratio <= 0.0

          # Calculate node dimensions based on aspect ratio
          # We can either use specified dimensions or calculate from available space
          node_width_opt = get_option(layout_opts, "topdownpacking.nodeWidth")
          if node_width_opt
            node_width = node_width_opt.to_f
            node_height = node_width / target_aspect_ratio
          else
            # Calculate from node sizes to maintain proportions
            avg_width = nodes.sum(&:width) / nodes.size.to_f
            avg_height = nodes.sum(&:height) / nodes.size.to_f

            # Use the larger dimension as base
            if avg_width >= avg_height
              node_width = avg_width
              node_height = node_width / target_aspect_ratio
            else
              node_height = avg_height
              node_width = node_height * target_aspect_ratio
            end
          end

          { width: node_width, height: node_height }
        end

        # Get option value from layout options or default
        #
        # @param layout_opts [Hash, LayoutOptions] The layout options
        # @param key [String] The option key
        # @param default [Object] The default value
        # @return [Object] The option value or default
        def get_option(layout_opts, key, default = nil)
          return default unless layout_opts

          value = if layout_opts.respond_to?(:[])
                    layout_opts[key]
                  end

          value.nil? ? default : value
        end

        # Place nodes in grid positions
        #
        # @param nodes [Array<Elkrb::Graph::Node>] The nodes to place
        # @param cols [Integer] Number of columns
        # @param node_width [Float] Width of each grid cell
        # @param node_height [Float] Height of each grid cell
        def place_nodes_in_grid(nodes, cols, node_width, node_height)
          spacing = node_spacing
          current_x = 0.0
          current_y = 0.0
          current_col = 0

          nodes.each do |node|
            # Set node dimensions
            node.width = node_width
            node.height = node_height

            # Set node position
            node.x = current_x
            node.y = current_y

            # Advance to next position
            current_col += 1
            current_x += node_width + spacing

            # Move to next row if we've filled the current row
            if current_col >= cols
              current_x = 0.0
              current_y += node_height + spacing
              current_col = 0
            end
          end
        end
      end
    end
  end
end
