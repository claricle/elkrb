# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      # DISCO (Disconnected Graph Layout) algorithm
      #
      # Handles graphs with disconnected components by:
      # 1. Identifying connected components
      # 2. Laying out each component independently
      # 3. Arranging components in a grid or row
      class Disco < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          # Find connected components
          components = find_connected_components(graph)

          # Layout each component independently
          component_algo = graph.layout_options&.[]("disco.componentAlgorithm") || "layered"
          components.each do |component|
            layout_component(component, component_algo)
          end

          # Arrange components
          spacing = graph.layout_options&.[]("disco.componentSpacing") || 20.0
          arrange_components(components, graph, spacing)

          # Apply padding
          apply_padding(graph)

          graph
        end

        private

        def find_connected_components(graph)
          visited = Set.new
          components = []

          graph.children.each do |node|
            next if visited.include?(node)

            component = {
              nodes: [],
              edges: [],
            }

            # BFS to find all connected nodes
            queue = [node]
            while queue.any?
              current = queue.shift
              next if visited.include?(current)

              visited.add(current)
              component[:nodes] << current

              # Find connected nodes through edges
              connected_edges = graph.edges.select do |edge|
                edge_nodes = []
                edge.sources&.each do |port|
                  edge_nodes << (port.respond_to?(:node) ? port.node : port)
                end
                edge.targets&.each do |port|
                  edge_nodes << (port.respond_to?(:node) ? port.node : port)
                end
                edge_nodes.include?(current)
              end

              component[:edges].concat(connected_edges)

              connected_edges.each do |edge|
                nodes = []
                edge.sources&.each do |port|
                  nodes << (port.respond_to?(:node) ? port.node : port)
                end
                edge.targets&.each do |port|
                  nodes << (port.respond_to?(:node) ? port.node : port)
                end
                nodes.each { |n| queue << n unless visited.include?(n) }
              end
            end

            components << component
          end

          components
        end

        def layout_component(component, algorithm_name)
          return if component[:nodes].empty?

          # Create a temporary graph for this component
          temp_graph = Graph::Graph.new
          temp_graph.children = component[:nodes]
          temp_graph.edges = component[:edges]

          # Get algorithm from registry
          algorithm_class = Layout::AlgorithmRegistry.get(algorithm_name)
          return unless algorithm_class

          # Apply layout algorithm to component
          algorithm = algorithm_class.new
          algorithm.layout(temp_graph)
        end

        def arrange_components(components, graph, spacing)
          return if components.empty?

          arrangement = graph.layout_options&.[]("disco.componentArrangement") || "row"

          case arrangement
          when "grid"
            arrange_in_grid(components, spacing)
          when "column"
            arrange_in_column(components, spacing)
          else
            arrange_in_row(components, spacing)
          end
        end

        def arrange_in_row(components, spacing)
          x_offset = 0.0

          components.each do |component|
            # Calculate component bounds
            min_x = component[:nodes].map(&:x).min || 0.0
            max_x = component[:nodes].map { |n| n.x + n.width }.max || 0.0
            component_width = max_x - min_x

            # Offset all nodes in component
            offset_x = x_offset - min_x
            component[:nodes].each do |node|
              node.x += offset_x
            end

            x_offset += component_width + spacing
          end
        end

        def arrange_in_column(components, spacing)
          y_offset = 0.0

          components.each do |component|
            # Calculate component bounds
            min_y = component[:nodes].map(&:y).min || 0.0
            max_y = component[:nodes].map { |n| n.y + n.height }.max || 0.0
            component_height = max_y - min_y

            # Offset all nodes in component
            offset_y = y_offset - min_y
            component[:nodes].each do |node|
              node.y += offset_y
            end

            y_offset += component_height + spacing
          end
        end

        def arrange_in_grid(components, spacing)
          return if components.empty?

          # Calculate grid dimensions
          cols = Math.sqrt(components.size).ceil
          rows = (components.size.to_f / cols).ceil

          y_offset = 0.0
          row_heights = []

          rows.times do |row|
            x_offset = 0.0
            max_row_height = 0.0

            cols.times do |col|
              index = (row * cols) + col
              break if index >= components.size

              component = components[index]

              # Calculate component bounds
              min_x = component[:nodes].map(&:x).min || 0.0
              min_y = component[:nodes].map(&:y).min || 0.0
              max_x = component[:nodes].map { |n| n.x + n.width }.max || 0.0
              max_y = component[:nodes].map { |n| n.y + n.height }.max || 0.0

              component_width = max_x - min_x
              component_height = max_y - min_y

              # Offset nodes
              component[:nodes].each do |node|
                node.x += x_offset - min_x
                node.y += y_offset - min_y
              end

              x_offset += component_width + spacing
              max_row_height = [max_row_height, component_height].max
            end

            row_heights << max_row_height
            y_offset += max_row_height + spacing
          end
        end
      end
    end
  end
end
