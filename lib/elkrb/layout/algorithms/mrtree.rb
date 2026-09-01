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

        LEVEL_HEIGHT = 80.0
        private_constant :LEVEL_HEIGHT

        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          index = NodeIndex.build(graph)

          # Identify root nodes (nodes with no incoming edges)
          roots = find_root_nodes(graph, index)

          # If no roots found, treat all nodes as roots
          roots = graph.children if roots.empty?

          trees = build_forest(roots, graph, adjacency(graph, index))

          # Calculate positions for each tree
          x_offset = 0
          # `layout_tree` returns the width it actually consumed, spacing
          # included. Recomputing that separately is what let two trees collide:
          # `calculate_tree_width` summed leaf widths and omitted the gap
          # between siblings, so a tree was reported narrower than it was drawn.
          trees.each do |tree|
            consumed, = layout_tree(tree, x_offset, 0)
            x_offset += consumed
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

          # Relaxation is scoped to ONE component at a time. It used to run
          # graph-wide per seed, and the level bound was the whole graph's node
          # count, so a two-node cycle kept incrementing a <-> b until it hit
          # that bound: O(n) passes over O(n) nodes for every component, which
          # is cubic. Measured on disjoint two-cycles before this change --
          # 160 nodes 0.45s, 320 nodes 3.21s, 480 nodes 10.58s.
          members = components(graph, adjacent)

          relax_component_of(roots, members, adjacent, levels)

          # Walk the children once. Rescanning for the first unlevelled node on
          # every iteration was itself quadratic.
          graph.children.each do |node|
            next if levels.key?(node.id)

            seeds << node
            relax_component_of([node], members, adjacent, levels)
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

        # Undirected connected components, computed once. Returns node id ->
        # the array of nodes sharing its component, so a relaxation can bound
        # itself by its own component's size instead of the whole graph's.
        def components(graph, adjacent)
          neighbours = undirected(graph, adjacent)

          by_id = {}
          graph.children.each do |node|
            next if by_id.key?(node.id)

            group = reachable_from(node, neighbours)
            group.each { |member| by_id[member.id] = group }
          end

          by_id
        end

        # An edge constrains level in one direction but joins a component in
        # both, so connectivity is walked undirected.
        def undirected(graph, adjacent)
          neighbours = Hash.new { |hash, key| hash[key] = [] }

          graph.children.each do |node|
            adjacent[node.id].each do |child|
              neighbours[node.id] << child
              neighbours[child.id] << node
            end
          end

          neighbours
        end

        def reachable_from(node, neighbours)
          group = []
          stack = [node]
          seen = { node.id => true }

          until stack.empty?
            current = stack.pop
            group << current
            neighbours[current.id].each do |other|
              next if seen[other.id]

              seen[other.id] = true
              stack << other
            end
          end

          group
        end

        # Seed the given nodes at level 0 and relax only the components they
        # belong to, bounded by those components' sizes. Seeds may span
        # SEVERAL components -- the roots do on a forest -- so the groups are
        # deduplicated and each is relaxed once.
        #
        # `filter_map` drops a seed with no component, which cannot happen:
        # `members` is built from the same `graph.children` the seeds come
        # from. It is written this way so a future disagreement between the
        # two skips that seed rather than raising mid-layout.
        def relax_component_of(seeds, members, adjacent, levels)
          seeds.each { |seed| levels[seed.id] = 0 }

          seeds
            .filter_map { |seed| members[seed.id] }
            .uniq(&:object_id)
            .each { |group| relax_levels(group, adjacent, levels) }

          nil
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
        # `nodes` is ONE component, so the bound is that component's size. It
        # used to be the whole graph's node count, which is what let a two-node
        # cycle climb for O(n) passes.
        #
        # Mutates `levels` in place and returns nothing useful.
        def relax_levels(nodes, adjacent, levels)
          bound = nodes.size

          bound.times do
            break unless relax_pass(nodes, adjacent, levels, bound)
          end

          nil
        end

        # One relaxation sweep. Answers whether any level moved.
        def relax_pass(nodes, adjacent, levels, max_level)
          changed = false

          nodes.each do |node|
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
        #
        # A floored level can exceed the relaxation bound: r0 -> a -> b -> c
        # with c -> a closing it puts c at level 6 across four nodes. Cyclic
        # components therefore come out taller than they need to be.
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

        # `placed` collects every node of the tree being laid out, in post
        # order, appended exactly once. A subtree therefore occupies a
        # CONTIGUOUS slice, and its parent can read or shift that slice by
        # index without walking the tree again.
        #
        # It matters: reading the extent by re-walking the subtree at every
        # level is quadratic on a deep tree. Instrumented on a chain before
        # this change -- 20,099 visits for 200 nodes and 320,399 for 800.
        # That is (n+2)(n-1)/2, not n^2/2; the shape is what matters, and
        # doubling n multiplies the visits by four.
        def layout_tree(tree, x_offset, y_offset, placed = [])
          node = tree[:node]
          start = placed.size

          if tree[:children].empty?
            return place_leaf(tree, x_offset, y_offset,
                              placed)
          end

          left, right = layout_children(tree, x_offset, y_offset, placed)
          centre_over_children(tree, y_offset)
          placed << node

          # The width CONSUMED, measured from where the nodes actually landed.
          # `child_x` alone is not it: it accounts only for the children's
          # allocation, and a node WIDER than its children protrudes past them
          # on both sides. A 200px parent over two 10px children reported 60
          # while occupying 200, and the next tree started 60px inside it.
          # Centring can also push the parent left of `x_offset`, so the
          # subtree is nudged back before its extent is read.
          own_right = node.x + (node.width || 0.0)
          left = node.x if node.x < left
          right = own_right if own_right > right

          # Only when the parent actually protrudes LEFT does this touch the
          # subtree again, and then only that subtree's own slice. Reading the
          # extent by re-walking every level instead cost n^2/2 node visits on
          # a deep tree -- measured on a chain: 320,399 visits for 800 nodes,
          # now 0, and the layout went from 0.443s to 0.244s.
          if left < x_offset
            shift = x_offset - left
            shift_slice(placed, start, shift)
            left += shift
            right += shift
          end

          [right - x_offset + node_spacing, left, right]
        end

        # A leaf sits where it was told to, and occupies exactly its own box.
        def place_leaf(tree, x_offset, y_offset, placed)
          node = tree[:node]
          node.x = x_offset
          node.y = y_offset + (tree[:level] * LEVEL_HEIGHT)
          placed << node
          width = node.width || 0.0

          [width + node_spacing, node.x, node.x + width]
        end

        # Centres a node over the children already placed beneath it.
        def centre_over_children(tree, y_offset)
          node = tree[:node]
          first_child = tree[:children].first[:node]
          last_child = tree[:children].last[:node]
          last_child_width = last_child.width || 0.0
          center_x = (first_child.x + last_child.x + last_child_width) / 2.0

          node.x = center_x - ((node.width || 0.0) / 2.0)
          node.y = y_offset + (tree[:level] * LEVEL_HEIGHT)
        end

        # Places every child left to right and answers the interval they
        # occupy between them.
        def layout_children(tree, x_offset, y_offset, placed)
          child_x = x_offset
          left = nil
          right = nil

          tree[:children].each do |child_tree|
            consumed, child_left, child_right =
              layout_tree(child_tree, child_x, y_offset, placed)
            child_x += consumed
            left = child_left if left.nil? || child_left < left
            right = child_right if right.nil? || child_right > right
          end

          [left, right]
        end

        def shift_slice(placed, start, shift)
          index = start
          while index < placed.size
            placed[index].x += shift
            index += 1
          end
        end
      end
    end
  end
end
