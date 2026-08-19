# frozen_string_literal: true

require "set"
require_relative "base_algorithm"
require_relative "../node_index"

module Elkrb
  module Layout
    module Algorithms
      # MRTree (Multi-Rooted Tree) layout algorithm
      #
      # Arranges nodes in a tree structure that can handle multiple root nodes.
      class MRTree < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          index = NodeIndex.build(graph)

          # Identify root nodes (nodes with no incoming edges)
          roots = find_root_nodes(graph, index)

          # If no roots found, treat all nodes as roots
          roots = graph.children if roots.empty?

          # Build tree structure from roots
          trees = roots.map { |root| build_tree(root, graph, index) }

          # Calculate positions for each tree
          spacing_val = node_spacing
          x_offset = 0
          trees.each do |tree|
            layout_tree(tree, x_offset, 0)
            tree_width = calculate_tree_width(tree)
            x_offset += tree_width + spacing_val
          end

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end

        private

        def find_root_nodes(graph, index)
          nodes_with_incoming = Set.new

          graph.edges&.each do |edge|
            next if self_loop_edge?(edge, index)

            index.endpoint_nodes(edge.targets).each do |target|
              nodes_with_incoming.add(target.id)
            end
          end

          graph.children.reject { |node| nodes_with_incoming.include?(node.id) }
        end

        # Compares resolved OWNERS, not raw ids: two different port ids
        # on the same node (e.g. "p1" -> "p2") are still a self-loop.
        # Comparing raw ids here would leave a port-to-port self-loop
        # looking like real incoming traffic once find_root_nodes above
        # resolves targets through the index, which can wrongly exclude
        # a true root from `roots` whenever it also carries such a loop.
        def self_loop_edge?(edge, index)
          sources = index.endpoint_nodes(edge.sources)
          targets = index.endpoint_nodes(edge.targets)

          return false if sources.empty? || targets.empty?

          sources.first == targets.first
        end

        def build_tree(root, graph, index)
          build_subtree(root, graph, index, 0, Set.new)
        end

        def build_subtree(node, graph, index, level, visited)
          visited = visited | [node.id]

          tree = {
            node: node,
            children: [],
            level: level,
          }

          children = find_children(node, graph, index)
                     .reject { |child| visited.include?(child.id) }
          tree[:children] = children.map do |child|
            build_subtree(child, graph, index, level + 1, visited)
          end

          tree
        end

        def find_children(node, graph, index)
          children = []
          edges = graph.edges || []

          edges.each do |edge|
            next unless index.endpoint_nodes(edge.sources).include?(node)

            children.concat(index.endpoint_nodes(edge.targets))
          end

          children
        end

        def layout_tree(tree, x_offset, y_offset)
          node = tree[:node]
          spacing_val = node_spacing
          level_height = 80.0

          if tree[:children].empty?
            # Leaf node
            node.x = x_offset
            node.y = y_offset + (tree[:level] * level_height)
            return node.width + spacing_val
          end

          # Layout children first
          child_x = x_offset
          tree[:children].each do |child_tree|
            width = layout_tree(child_tree, child_x, y_offset)
            child_x += width
          end

          # Position this node centered above children
          first_child = tree[:children].first[:node]
          last_child = tree[:children].last[:node]

          center_x = (first_child.x + last_child.x + last_child.width) / 2.0
          node.x = center_x - (node.width / 2.0)
          node.y = y_offset + (tree[:level] * level_height)

          # Return total width
          last_child.x + last_child.width - x_offset + spacing_val
        end

        def calculate_tree_width(tree)
          return tree[:node].width if tree[:children].empty?

          tree[:children].sum { |child| calculate_tree_width(child) }
        end
      end
    end
  end
end
