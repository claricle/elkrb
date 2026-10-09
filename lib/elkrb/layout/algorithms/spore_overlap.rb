# frozen_string_literal: true

require_relative "../spore/placement"
require_relative "../spore/edge_cost"
require_relative "../spore/overlap_sweep"
require_relative "../spore/triangulation"
require_relative "../spore/spanning_tree"

module Elkrb
  module Layout
    module Algorithms
      # SPOrE overlap removal ("Node Overlap Removal by Growing a Tree").
      #
      # Each pass sweeps for overlapping pairs, joins the node centres by a
      # minimum spanning tree over the overlap edges plus a Delaunay
      # triangulation, then walks the tree from the most central node and
      # stretches every tree edge just far enough that the two rectangles
      # stop overlapping. Passes repeat until a pass stretches nothing or
      # the cap is reached.
      #
      # Ties between equally cheap tree edges are broken by discovery order,
      # where Java ELK breaks them by hash-set order.
      class SporeOverlap < BaseAlgorithm
        include Spore::Placement

        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          self.class.normalize_nil_positions(graph.children)

          max_iterations = resolver.get("spore.maxIterations", graph)
          spacing = resolver.get("spore.nodeSpacing", graph,
                                 default: DEFAULT_SPACING)

          bodies = build_bodies(graph.children, spacing)
          root = most_central(bodies, graph)
          remove_overlaps(bodies, root, max_iterations)
          warn_if_overlaps_remain(bodies, max_iterations)

          bodies.each { |body| place(body) }
          apply_padding(graph)

          graph
        end

        private

        def remove_overlaps(bodies, root, max_iterations)
          max_iterations.times do
            pairs = Spore::OverlapSweep.pairs(bodies)
            break if pairs.empty?

            tree = Spore::SpanningTree.build(
              tree_edges(bodies, pairs), root
            ) { |first, second| Spore::EdgeCost.inverted_overlap(first, second) }
            grown = grow(tree)
            bodies.each(&:rebase)
            break unless grown
          end
        end

        def tree_edges(bodies, pairs)
          by_origin = bodies.to_h { |body| [body.origin, body] }
          triangulated = Spore::Triangulation.triangulate(by_origin.keys)
            .map { |u, v| [by_origin[u], by_origin[v]] }
          (pairs + triangulated).uniq { |edge| edge.map(&:object_id).sort }
        end

        # Walks the tree from the root, moving each child to where its
        # parent's move put it and then stretching the edge to the parent.
        # @return [Boolean] whether any edge needed stretching
        def grow(tree)
          stretched = false
          pending = [tree]
          until pending.empty?
            parent = pending.pop
            parent.children.each do |child|
              stretched |= stretch(parent.body, child.body) > 1.0
            end
            pending.concat(parent.children.reverse)
          end
          stretched
        end

        # @return [Float] the factor the edge was stretched by
        def stretch(parent, child)
          child.translate(parent.center_x - parent.origin_x,
                          parent.center_y - parent.origin_y)
          factor = Spore::Geometry.overlap(parent, child)
          child.center_at(
            parent.center_x + ((child.origin_x - parent.origin_x) * factor),
            parent.center_y + ((child.origin_y - parent.origin_y) * factor),
          )
          factor
        end

        def warn_if_overlaps_remain(bodies, max_iterations)
          # Sides that only touch can still sweep as overlapping through
          # rounding, so the warning counts real intersections only.
          remaining = Spore::OverlapSweep.pairs(bodies).select do |pair|
            Spore::Geometry.intersect?(*pair)
          end
          return if remaining.empty?

          warn "SporeOverlap: max_iterations (#{max_iterations}) exhausted " \
               "with #{remaining.size} overlap(s) still remaining"
        end
      end
    end
  end
end
