# frozen_string_literal: true

require_relative "base_algorithm"

module Elkrb
  module Layout
    module Algorithms
      # VertiFlex layout algorithm
      #
      # A vertical flexible layout algorithm that arranges nodes in vertical
      # columns with optimized spacing. Ideal for timeline-style layouts,
      # Kanban boards, and vertical flowcharts.
      #
      # The algorithm distributes nodes into vertical columns and positions
      # them with flexible column widths based on the widest node in each
      # column.
      #
      # This is an experimental algorithm matching the Java ELK implementation.
      class VertiFlex < BaseAlgorithm
        def initialize(options = {})
          super
        end

        # Layout nodes in vertical columns
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

          nodes = graph.children
          layout_opts = graph.layout_options || {}

          # Get layout options
          column_count = get_option(layout_opts, "vertiflex.columnCount",
                                    3).to_i
          column_count = 1 if column_count < 1

          column_spacing = get_option(
            layout_opts,
            "vertiflex.columnSpacing",
            50.0,
          ).to_f

          vertical_spacing = get_option(
            layout_opts,
            "vertiflex.verticalSpacing",
            30.0,
          ).to_f

          # Override with elk.spacing.nodeNode if present
          node_node_spacing = get_option(layout_opts, "elk.spacing.nodeNode")
          vertical_spacing = node_node_spacing.to_f if node_node_spacing

          balance_columns = get_option(
            layout_opts,
            "vertiflex.balanceColumns",
            true,
          )

          # Distribute nodes into columns
          columns = distribute_nodes(nodes, column_count, balance_columns)

          # Position columns horizontally
          position_columns(columns, column_spacing, vertical_spacing)

          apply_padding(graph)

          graph
        end

        private

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

        # Distribute nodes into columns
        #
        # @param nodes [Array<Elkrb::Graph::Node>] Nodes to distribute
        # @param column_count [Integer] Number of columns
        # @param balance [Boolean] Whether to balance distribution
        # @return [Array<Array<Elkrb::Graph::Node>>] Array of columns
        def distribute_nodes(nodes, column_count, balance)
          # Initialize columns
          columns = Array.new(column_count) { [] }

          if balance
            # Balanced distribution: round-robin assignment
            nodes.each_with_index do |node, index|
              column_index = index % column_count
              columns[column_index] << node
            end
          else
            # Sequential distribution: fill columns in order
            nodes_per_column = (nodes.size.to_f / column_count).ceil
            nodes.each_slice(nodes_per_column).with_index do |slice, index|
              columns[index] = slice if index < column_count
            end
          end

          # Remove empty columns
          columns.reject(&:empty?)
        end

        # Position columns horizontally with flexible widths
        #
        # @param columns [Array<Array<Elkrb::Graph::Node>>] Columns of nodes
        # @param column_spacing [Float] Spacing between columns
        # @param vertical_spacing [Float] Vertical spacing within columns
        def position_columns(columns, column_spacing, vertical_spacing)
          current_x = 0.0

          columns.each do |column_nodes|
            # Calculate column width based on widest node
            column_width = column_nodes.map(&:width).max || 100.0

            # Position nodes vertically in this column
            position_column_nodes(
              column_nodes,
              current_x,
              column_width,
              vertical_spacing,
            )

            # Advance to next column position
            current_x += column_width + column_spacing
          end
        end

        # Position nodes vertically within a column
        #
        # @param nodes [Array<Elkrb::Graph::Node>] Nodes in the column
        # @param column_x [Float] X position of the column
        # @param column_width [Float] Width of the column (unused, kept for API)
        # @param vertical_spacing [Float] Vertical spacing between nodes
        def position_column_nodes(nodes, column_x, _column_width,
vertical_spacing)
          current_y = 0.0

          nodes.each do |node|
            # Position node at column x (no centering for simpler layout)
            node.x = column_x
            node.y = current_y

            # Advance to next vertical position
            current_y += node.height + vertical_spacing
          end
        end
      end
    end
  end
end
