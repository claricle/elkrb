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
        # Fallback cell size when no node anywhere declares a usable width
        # or height. Mirrors node_spacing's own 20.0 default rather than
        # inventing a new constant.
        DEFAULT_CELL_SIZE = 20.0

        def initialize(options = {})
          super
        end

        # A declared width or height is only usable when it is finite and
        # positive. NaN and Infinity are valid YAML float literals (`.nan`,
        # `.inf`; JSON's parser rejects the bare form) that would otherwise
        # propagate into every downstream position and crash
        # calculate_bounding_box's Array#max, whose NaN-vs-NaN comparison
        # raises ArgumentError. A non-positive value is rejected too --
        # port_constraint_processor.rb already treats a node as size-less
        # unless both dimensions are `positive?`, and letting a negative
        # declared value reach this node's own box (rather than every
        # node's shared, uniformly-averaged cell size, as before this
        # file's declared-size-preserving change) inverts its box and
        # produces a false-negative overlap check against its neighbours.
        # No type check beyond nil-safety: Node's width/height are declared
        # `attribute :width, :float` (node.rb), so lutaml casts every
        # assignment to a Float or nil before it can ever reach here -- a
        # value that responds to #finite? and is neither nil nor a Numeric
        # is not a reachable input. A public class method -- it depends on
        # nothing but its argument, matching the pure-helper convention
        # already used elsewhere for options parsing (e.g. KVector.parse).
        # Keep this as a class method with the instance delegate below --
        # a plain private instance method here trips reek's UtilityFunction
        # check.
        #
        # @param value [Float, nil] The node's declared width or height
        # @return [Float, nil] The value if usable, nil otherwise
        def self.finite_dimension(value)
          return nil unless value&.finite? && value.positive?

          value
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

          # Get target aspect ratio (default: 1.0 for square cells). A
          # non-positive OR non-finite (NaN/Infinity, both valid YAML float
          # literals) declared ratio falls back to square rather than
          # reaching the division below, or the identical Array#max crash
          # in calculate_bounding_box that finite_dimension exists to
          # prevent for per-node sizes.
          target_aspect_ratio = get_option(layout_opts,
                                           "topdownpacking.aspectRatio", 1.0).to_f
          target_aspect_ratio = 1.0 if target_aspect_ratio <= 0.0 || !target_aspect_ratio.finite?

          # Calculate node dimensions based on aspect ratio
          # We can either use specified dimensions or calculate from available space
          node_width_opt = finite_dimension(get_option(layout_opts, "topdownpacking.nodeWidth")&.to_f)
          if node_width_opt
            node_width = node_width_opt
            node_height = node_width / target_aspect_ratio
          else
            # Calculate from node sizes to maintain proportions. A size-less,
            # non-finite (NaN/Infinity, both valid YAML float literals) or
            # non-positive node contributes 0.0 rather than crashing the
            # average, matching the nil-handling convention in box.rb.
            avg_width = nodes.sum { |node| finite_dimension(node.width) || 0.0 } / nodes.size.to_f
            avg_height = nodes.sum { |node| finite_dimension(node.height) || 0.0 } / nodes.size.to_f

            # When no node anywhere declares a usable size, both averages
            # are zero and every node would silently collapse to a 0x0
            # footprint. Fall back to a default cell size instead of
            # discarding every node.
            if avg_width.zero? && avg_height.zero?
              avg_width = DEFAULT_CELL_SIZE
              avg_height = DEFAULT_CELL_SIZE
            end

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
        # @param layout_opts [Hash] The layout options
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

        # Instance-side delegate to the class method above, so callers in
        # this file read as one private helper rather than repeating
        # `self.class` at every call site.
        #
        # @param value [Object] The node's declared width or height
        # @return [Numeric, nil] The value if usable, nil otherwise
        def finite_dimension(value)
          self.class.finite_dimension(value)
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
          row_height = 0.0

          nodes.each do |node|
            # Only a node with a usable (finite, positive, non-nil) declared
            # width/height keeps it -- which means it may be larger than
            # the cell, so advancing by the fixed cell size (rather than
            # the node's own size) would let it overlap its neighbours. A
            # size-less, non-finite (NaN/Infinity) or non-positive declared
            # value takes the grid cell size instead of reaching position
            # math as-is.
            actual_width = (node.width = finite_dimension(node.width) || node_width)
            actual_height = (node.height = finite_dimension(node.height) || node_height)

            # Set node position
            node.x = current_x
            node.y = current_y

            row_height = actual_height if actual_height > row_height

            # Advance to next position, past this node's own footprint
            current_col += 1
            current_x += actual_width + spacing

            # Move to next row if we've filled the current row, past the
            # tallest node actually placed in it
            if current_col >= cols
              current_x = 0.0
              current_y += row_height + spacing
              current_col = 0
              row_height = 0.0
            end
          end
        end
      end
    end
  end
end
