# frozen_string_literal: true

require_relative "../spore/placement"
require_relative "../spore/edge_cost"
require_relative "../spore/triangulation"
require_relative "../spore/spanning_tree"
require_relative "../spore/depth_first_compaction"

module Elkrb
  module Layout
    module Algorithms
      # SPOrE compaction ("ShrinkTree"): closes the gaps in an overlap-free
      # layout without changing its topology.
      #
      # The node centres are joined by a Delaunay triangulation, a spanning
      # tree of it is grown from the root node, and the tree is compacted
      # depth first: each subtree slides toward its parent until it would
      # touch another node.
      #
      # Ties between equally cheap tree edges are broken by discovery order,
      # where Java ELK breaks them by hash-set order. Nodes that start on
      # the same point are nudged apart at random, as Java does.
      class SporeCompaction < BaseAlgorithm
        include Spore::Placement

        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          self.class.normalize_nil_positions(graph.children)

          spacing = node_gap(graph)
          bodies = build_bodies(graph.children, spacing)
          compact(bodies, graph) if bodies.size > 1

          bodies.each { |body| place(body) }
          apply_padding(graph)

          graph
        end

        private

        # spore.nodeSpacing, else ELK's own spacing id, else ELK's default.
        def node_gap(graph)
          resolver.get("spore.nodeSpacing", graph, default: nil) ||
            resolver.get("elk.spacing.nodeNode", graph,
                         default: DEFAULT_SPACING)
        end

        def compact(bodies, graph)
          root = select_root(bodies, graph)
          Spore::DepthFirstCompaction.compact(grow_tree(bodies, root, graph),
                                              mode: mode(graph))
        end

        def select_root(bodies, graph)
          return most_central(bodies, graph) unless
            resolver.get("elk.processingOrder.rootSelection", graph) == "FIXED"

          wanted = resolver.get("elk.processingOrder.preferredRoot", graph)
          named = bodies.select { |body| body.source.id == wanted } if wanted
          named&.last || bodies.first
        end

        def grow_tree(bodies, root, graph)
          cost = Spore::EdgeCost.for(
            resolver.get("elk.processingOrder.spanningTreeCostFunction", graph),
            root,
          )
          sign = maximum_tree?(graph) ? -1 : 1
          Spore::SpanningTree.build(triangulated_edges(bodies), root) do |a, b|
            sign * cost.call(a, b)
          end
        end

        def maximum_tree?(graph)
          resolver.get("elk.processingOrder.treeConstruction", graph) ==
            "MAXIMUM_SPANNING_TREE"
        end

        def triangulated_edges(bodies)
          by_origin = bodies.to_h { |body| [body.origin, body] }
          Spore::Triangulation.triangulate(by_origin.keys)
            .map { |u, v| [by_origin[u], by_origin[v]] }
        end

        def mode(graph)
          direction = resolver.get("spore.compactionDirection", graph)
          return direction.to_sym unless direction == "both"

          resolver.get("elk.compaction.orthogonal", graph) ? :orthogonal : :free
        end
      end
    end
  end
end
