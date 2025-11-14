# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      # SPOrE Compaction algorithm
      #
      # Compacts the layout by removing whitespace while preserving
      # the relative ordering and structure of nodes.
      class SporeCompaction < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          # Compact in both directions
          direction = graph.layout_options&.[]("spore.compactionDirection") || "both"
          min_spacing = graph.layout_options&.[]("spore.nodeSpacing") || 10.0

          case direction
          when "horizontal"
            compact_horizontal(graph.children, min_spacing)
          when "vertical"
            compact_vertical(graph.children, min_spacing)
          else
            compact_horizontal(graph.children, min_spacing)
            compact_vertical(graph.children, min_spacing)
          end

          # Normalize to start at origin
          normalize_positions(graph.children)

          # Apply padding
          apply_padding(graph)

          graph
        end

        private

        def compact_horizontal(nodes, min_spacing)
          # Sort nodes by x coordinate
          sorted_nodes = nodes.sort_by(&:x)

          # Compact from left to right
          sorted_nodes.each_with_index do |node, index|
            next if index.zero?

            # Find the rightmost x position among nodes to the left
            # that don't vertically overlap with current node
            max_left_x = find_max_left_x(node, sorted_nodes[0...index],
                                         min_spacing)

            # Move node left if there's space
            if max_left_x && max_left_x < node.x
              node.x = max_left_x
            end
          end
        end

        def find_max_left_x(node, left_nodes, min_spacing)
          # Find nodes that vertically overlap with current node
          overlapping = left_nodes.select do |left_node|
            vertically_overlaps?(node, left_node)
          end

          return 0.0 if overlapping.empty?

          # Find the rightmost position among overlapping nodes
          rightmost = overlapping.map { |n| n.x + n.width }.max
          rightmost + min_spacing
        end

        def compact_vertical(nodes, min_spacing)
          # Sort nodes by y coordinate
          sorted_nodes = nodes.sort_by(&:y)

          # Compact from top to bottom
          sorted_nodes.each_with_index do |node, index|
            next if index.zero?

            # Find the bottommost y position among nodes above
            # that don't horizontally overlap with current node
            max_top_y = find_max_top_y(node, sorted_nodes[0...index],
                                       min_spacing)

            # Move node up if there's space
            if max_top_y && max_top_y < node.y
              node.y = max_top_y
            end
          end
        end

        def find_max_top_y(node, top_nodes, min_spacing)
          # Find nodes that horizontally overlap with current node
          overlapping = top_nodes.select do |top_node|
            horizontally_overlaps?(node, top_node)
          end

          return 0.0 if overlapping.empty?

          # Find the bottommost position among overlapping nodes
          bottommost = overlapping.map { |n| n.y + n.height }.max
          bottommost + min_spacing
        end

        def vertically_overlaps?(node1, node2)
          top1 = node1.y
          bottom1 = node1.y + node1.height
          top2 = node2.y
          bottom2 = node2.y + node2.height

          !(bottom1 <= top2 || bottom2 <= top1)
        end

        def horizontally_overlaps?(node1, node2)
          left1 = node1.x
          right1 = node1.x + node1.width
          left2 = node2.x
          right2 = node2.x + node2.width

          !(right1 <= left2 || right2 <= left1)
        end

        def normalize_positions(nodes)
          return if nodes.empty?

          # Find minimum x and y
          min_x = nodes.map(&:x).min
          min_y = nodes.map(&:y).min

          # Shift all nodes to start at origin
          nodes.each do |node|
            node.x -= min_x
            node.y -= min_y
          end
        end
      end
    end
  end
end
