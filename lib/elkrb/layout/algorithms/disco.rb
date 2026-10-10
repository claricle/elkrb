# frozen_string_literal: true

require_relative "../node_index"
require_relative "../polyomino/component_compactor"

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
        # ELK's default edge thickness, which widens an edge's footprint.
        EDGE_THICKNESS = 1.0
        # DisCo packs for a square unless the graph names an aspect ratio;
        # the registry default of elk.aspectRatio belongs to other algorithms.
        DEFAULT_ASPECT_RATIO = 1.0
        private_constant :EDGE_THICKNESS, :DEFAULT_ASPECT_RATIO

        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          # Find connected components
          components = find_connected_components(graph)

          # Layout each component independently
          component_algo = resolver.get("disco.componentAlgorithm", graph)
          components.each do |component|
            layout_component(component, component_algo)
          end

          # Arrange components
          spacing = resolver.get("disco.componentSpacing", graph)
          arrange_components(components, graph, spacing)

          # Apply padding
          apply_padding(graph)

          graph
        end

        private

        def find_connected_components(graph)
          index = NodeIndex.build(graph)
          visited = Set.new
          components = []

          graph.children.each do |node|
            next if visited.include?(node.id)

            nodes = []

            # BFS to find all connected nodes
            queue = [node]
            while queue.any?
              current = queue.shift
              next if visited.include?(current.id)

              visited.add(current.id)
              nodes << current

              (graph.edges || []).each do |edge|
                endpoints = index.endpoint_nodes(edge.sources) +
                  index.endpoint_nodes(edge.targets)
                next unless endpoints.include?(current)

                endpoints.each { |n| queue << n unless visited.include?(n.id) }
              end
            end

            # Compute this component's edges once the whole node set is
            # known, rather than per visited node — accumulating them
            # incrementally during the walk records each edge twice
            # (once from its source side, once from its target side).
            node_ids = Set.new(nodes.map(&:id))
            edges = (graph.edges || []).select do |edge|
              endpoints = index.endpoint_nodes(edge.sources) +
                index.endpoint_nodes(edge.targets)
              endpoints.any? { |n| node_ids.include?(n.id) }
            end

            components << { nodes: nodes, edges: edges }
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
          raise Elkrb::AlgorithmNotFoundError, algorithm_name unless algorithm_class

          # Apply layout algorithm to component
          algorithm = algorithm_class.new
          algorithm.layout(temp_graph)

          # The component was routed in its own coordinate space and is about
          # to be shifted into place, so those sections are stale the moment
          # it moves. The outer routing pass is the authoritative one — hand
          # it a clean slate instead of letting it append to pre-offset bends.
          component[:edges].each { |edge| edge.sections = nil }
        end

        # disco.componentCompaction.strategy is ELK's key; its one value,
        # POLYOMINO, is also the default. disco.componentArrangement is the
        # older elkrb key and takes ROW, COLUMN or GRID, and so does the
        # strategy key. The graph names either key before the call does: the
        # first reader sees the graph alone. A graph that names
        # disco.componentArrangement and not the strategy gets that
        # arrangement.
        def component_arrangement(graph)
          keys = %w[disco.componentCompaction.strategy disco.componentArrangement]
          raw = [Options::Resolver.new, resolver].product(keys)
            .filter_map { |reader, key| reader.get(key, graph, default: nil) }
            .first || resolver.get(keys.first, graph)
          raw.to_s.downcase
        end

        def arrange_components(components, graph, spacing)
          return if components.empty?

          arrangement = component_arrangement(graph)

          case arrangement
          when "polyomino"
            arrange_by_polyomino(components, graph, spacing)
          when "grid"
            arrange_in_grid(components, spacing)
          when "column"
            arrange_in_column(components, spacing)
          else
            arrange_in_row(components, spacing)
          end
        end

        # Packs the components the way ELK's DisCo does. A component's edges
        # have no route yet (the outer pass routes them), so each counts as the
        # straight line between its end nodes, as wide as the spacing.
        def arrange_by_polyomino(components, graph, spacing)
          aspect_ratio = resolver.get("elk.aspectRatio", graph, default: DEFAULT_ASPECT_RATIO)
          unless aspect_ratio.positive?
            raise ValidationError, "elk.aspectRatio must be above zero, got #{aspect_ratio}"
          end

          index = NodeIndex.build(graph)
          shapes = components.map { |component| component_shapes(component, index, spacing) }
          offsets = Polyomino::ComponentCompactor.new(shapes, aspect_ratio: aspect_ratio).offsets

          components.zip(offsets).each do |component, (dx, dy)|
            component[:nodes].each do |node|
              node.x = (node.x || 0.0) + dx
              node.y = (node.y || 0.0) + dy
            end
          end
        end

        def component_shapes(component, index, spacing)
          nodes = component[:nodes]
          shapes = nodes.flat_map { |node| node_shapes(node, spacing) }
          component[:edges].each do |edge|
            ends = (index.endpoint_nodes(edge.sources) + index.endpoint_nodes(edge.targets)).uniq
            next unless ends.size == 2 && ends.all? { |n| nodes.include?(n) }

            shapes << edge_shape(ends[0], ends[1], EDGE_THICKNESS + spacing)
          end
          shapes
        end

        # The node, and each label and port that has a position, grown by half
        # the spacing on every side.
        def node_shapes(node, spacing)
          x = node.x || 0.0
          y = node.y || 0.0
          boxes = [[x, y, node.width, node.height]]
          boxes += positioned(node.labels, x, y)
          (node.ports || []).each do |port|
            next unless port.x && port.y

            px = x + port.x
            py = y + port.y
            boxes << [px, py, port.width, port.height]
            boxes += positioned(port.labels, px, py)
          end
          boxes.map { |bx, by, w, h| grown_rectangle(bx, by, w || 0.0, h || 0.0, spacing / 2.0) }
        end

        def positioned(labels, left, top)
          (labels || []).select { |label| label.x && label.y }
            .map { |label| [left + label.x, top + label.y, label.width, label.height] }
        end

        def grown_rectangle(left_edge, top_edge, width, height, margin)
          left = left_edge - margin
          top = top_edge - margin
          right = left_edge + width + margin
          bottom = top_edge + height + margin
          [[left, top], [left, bottom], [right, bottom], [right, top]]
        end

        def edge_shape(from, to, thickness)
          ax = (from.x || 0.0) + ((from.width || 0.0) / 2.0)
          ay = (from.y || 0.0) + ((from.height || 0.0) / 2.0)
          bx = (to.x || 0.0) + ((to.width || 0.0) / 2.0)
          by = (to.y || 0.0) + ((to.height || 0.0) / 2.0)
          length = Math.hypot(bx - ax, by - ay)
          return grown_rectangle(ax, ay, 0.0, 0.0, thickness / 2.0) if length.zero?

          nx = (by - ay) / length * (thickness / 2.0)
          ny = (ax - bx) / length * (thickness / 2.0)
          [[ax + nx, ay + ny], [bx + nx, by + ny], [bx - nx, by - ny], [ax - nx, ay - ny]]
        end

        def arrange_in_row(components, spacing)
          x_offset = 0.0

          components.each do |component|
            box = calculate_bounding_box(component[:nodes])

            # Offset all nodes in component
            offset_x = x_offset - box.x
            component[:nodes].each do |node|
              node.x += offset_x
            end

            x_offset += box.width + spacing
          end
        end

        def arrange_in_column(components, spacing)
          y_offset = 0.0

          components.each do |component|
            box = calculate_bounding_box(component[:nodes])

            # Offset all nodes in component
            offset_y = y_offset - box.y
            component[:nodes].each do |node|
              node.y += offset_y
            end

            y_offset += box.height + spacing
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

              box = calculate_bounding_box(component[:nodes])

              # Offset nodes
              component[:nodes].each do |node|
                node.x += x_offset - box.x
                node.y += y_offset - box.y
              end

              x_offset += box.width + spacing
              max_row_height = [max_row_height, box.height].max
            end

            row_heights << max_row_height
            y_offset += max_row_height + spacing
          end
        end
      end
    end
  end
end
