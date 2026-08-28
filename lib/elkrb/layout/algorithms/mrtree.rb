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
        # Both readers of the adjacency map ask for every child of the
        # graph, sinks included, so a missing key has to answer something
        # enumerable rather than raise or grow the map.
        NO_CHILDREN = [].freeze
        private_constant :NO_CHILDREN

        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          index = NodeIndex.build(graph)

          # Identify root nodes (nodes with no incoming edges)
          roots = find_root_nodes(graph, index)

          # If no roots found, treat all nodes as roots
          roots = graph.children if roots.empty?

          trees = build_forest(roots, graph, adjacency(graph, index))

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
            sources = index.endpoint_nodes(edge.sources)

            # Count a target as having incoming traffic only when at
            # least one resolved source is a DIFFERENT node: a real
            # self-loop ("p1" -> "p2" on one node) and the
            # self-referencing leg of a mixed hyperedge
            # (a -> [a's port, b]) are not incoming traffic from
            # elsewhere, but a target that ALSO appears among the
            # sources (e.g. [a, b] -> b) still has genuine incoming
            # traffic from the other source.
            index.endpoint_nodes(edge.targets).each do |target|
              next unless sources.any? { |source| source != target }

              nodes_with_incoming.add(target.id)
            end
          end

          graph.children.reject { |node| nodes_with_incoming.include?(node.id) }
        end

        # Child nodes per source id, resolved once for the whole graph.
        # Rebuilding this per node would rescan every edge inside the
        # relaxation loop.
        #
        # Reads `graph.edges`, matching #find_root_nodes, NOT `index.edges`.
        # The index folds in the edges declared on childless top-level nodes,
        # so it is a strict superset: reading it here while root finding reads
        # the narrower set would let a node whose only incoming edge sits on a
        # sibling leaf be a root AND somebody's child at the same time.
        #
        # Ids identify nodes here where #find_root_nodes compares objects. The
        # two agree: NodeIndex keeps ids unique within a level and answers the
        # same object for the same id.
        def adjacency(graph, index)
          map = {}

          (graph.edges || []).each do |edge|
            targets = index.endpoint_nodes(edge.targets)

            index.endpoint_nodes(edge.sources).each do |source|
              # A hyperedge can target one of its source's own ports
              # alongside a real child (a -> [a's port, b]). Resolving that
              # port back to the source would make the node its own child,
              # and stepping down it would let the node keep deepening its
              # own level until it hit the relaxation bound.
              children = targets.reject { |target| target.id == source.id }
              (map[source.id] ||= []).concat(children)
            end
          end

          map.each_value { |children| children.uniq!(&:id) }
          # Set AFTER the loop above, not before it. With the default already
          # in place `(map[source.id] ||= [])` reads the frozen constant, finds
          # it truthy, and concats into it — FrozenError on the first edge.
          map.default = NO_CHILDREN
          map
        end

        # Every child has to end up in some tree. A component that is wholly
        # cyclic (a -> b -> a) contains no root, so it is never reached from
        # the graph's roots and its nodes keep nil coordinates until padding
        # trips over them. Whenever a pass leaves nodes unplaced, seed one of
        # them as a fallback root and keep going.
        def build_forest(roots, graph, adjacent)
          # A node reachable by two paths belongs at the DEEPER one, or it
          # ends up above its own parent. Levels are settled for the whole
          # graph before any tree is built, so placement order stops mattering.
          # That is a DAG guarantee: a cyclic component gets bounded fallback
          # numbers instead, and #build_subtree's floor is what re-orders those.
          levels = {}
          seeds = roots.dup
          relax_levels(seeds, graph, adjacent, levels)

          loop do
            remaining = graph.children.reject { |node| levels.key?(node.id) }
            break if remaining.empty?

            seed = remaining.first
            seeds << seed
            relax_levels([seed], graph, adjacent, levels)
          end

          # `placed` doubles as the walk's visited set, so a later tree cannot
          # reach back into a node an earlier tree already owns — placing a
          # node twice lets the second placement win and drags it above its own
          # parent. Nothing reads `placed` mid-walk except the walk itself.
          placed = Set.new
          seeds.filter_map do |seed|
            next if placed.include?(seed.id)

            build_subtree(seed, adjacent, placed, levels, 0)
          end
        end

        # On a DAG this settles on the LONGEST path to each node, which is what
        # puts a node reachable by two routes below its deepest parent. Walking
        # every simple path to find that is factorial — a complete 8-node cycle
        # took 2.5s and each extra node multiplied it by roughly ten. Relax
        # instead: a longest path visits each node at most once, so one sweep
        # per node settles every level a DAG can produce.
        #
        # A cyclic component has no longest path, so what its nodes get here is
        # a bounded fallback number rather than a depth — `max_level` stops it
        # climbing, it does not make it mean anything. Ordering inside such a
        # component is restored afterwards by #build_subtree's floor.
        #
        # Mutates `levels` in place and returns nothing useful.
        def relax_levels(seeds, graph, adjacent, levels)
          seeds.each { |seed| levels[seed.id] = 0 }
          node_count = graph.children.size

          node_count.times do
            break unless relax_pass(graph, adjacent, levels, node_count)
          end

          nil
        end

        # One relaxation sweep. Answers whether any level moved.
        def relax_pass(graph, adjacent, levels, max_level)
          changed = false

          graph.children.each do |node|
            depth = levels[node.id]
            next if depth.nil?

            adjacent[node.id].each do |child|
              candidate = depth + 1
              next if candidate > max_level
              next if candidate <= (levels[child.id] || -1)

              levels[child.id] = candidate
              changed = true
            end
          end

          changed
        end

        # `visited` is one mutable set for the whole walk, not a per-path copy.
        # Copying it per path means a node reachable by many routes is expanded
        # once per route, which is factorial on a dense graph — and it would
        # place that node more than once anyway.
        #
        # `floor` is the level this node may not sit above: one below its parent
        # in the tree being built. A cyclic component gets bounded fallback
        # levels rather than path depths, so a back edge can hand a node a level
        # deeper than its own child's and draw the parent underneath it. Taking
        # the floor forces every edge the forest actually picked to point down.
        # The edge that CLOSES a cycle is not one of those, and still points
        # upward — no tree can honour it, so it stays a violation.
        def build_subtree(node, adjacent, visited, levels, floor)
          visited << node.id

          tree = {
            node: node,
            children: [],
            level: [levels.fetch(node.id), floor].max,
          }

          children = adjacent[node.id]
                     .reject { |child| visited.include?(child.id) }
          # The whole child list is settled before any of it is recursed into,
          # so each sibling is claimed now — otherwise the first sibling's
          # subtree can reach a later one and place it a second time.
          children.each { |child| visited << child.id }

          tree[:children] = children.map do |child|
            build_subtree(child, adjacent, visited, levels, tree[:level] + 1)
          end

          tree
        end

        def layout_tree(tree, x_offset, y_offset)
          node = tree[:node]
          spacing_val = node_spacing
          level_height = 80.0

          if tree[:children].empty?
            # Leaf node
            node.x = x_offset
            node.y = y_offset + (tree[:level] * level_height)
            return (node.width || 0.0) + spacing_val
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

          last_child_width = last_child.width || 0.0

          center_x = (first_child.x + last_child.x + last_child_width) / 2.0
          node.x = center_x - ((node.width || 0.0) / 2.0)
          node.y = y_offset + (tree[:level] * level_height)

          # Return total width
          last_child.x + last_child_width - x_offset + spacing_val
        end

        def calculate_tree_width(tree)
          return tree[:node].width || 0.0 if tree[:children].empty?

          tree[:children].sum { |child| calculate_tree_width(child) }
        end
      end
    end
  end
end
