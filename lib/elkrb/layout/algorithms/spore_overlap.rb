# frozen_string_literal: true

require_relative "../spore/body"
require_relative "../spore/geometry"
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
        # ELK's own defaults for this algorithm; the shared registry values
        # are for the other algorithms.
        DEFAULT_SPACING = 8.0
        DEFAULT_PADDING = { left: 8.0, top: 8.0, right: 8.0, bottom: 8.0 }.freeze

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

        def padding
          option("elk.padding", default: DEFAULT_PADDING).to_h
        end

        def build_bodies(nodes, spacing)
          seen = {}
          nodes.map do |node|
            body = Spore::Body.new(node, spacing)
            body.nudge(rng) while seen.key?(body.origin)
            seen[body.origin] = true
            body
          end
        end

        def most_central(bodies, graph)
          cx = (graph.x.to_f + (graph.width.to_f / 2.0))
          cy = (graph.y.to_f + (graph.height.to_f / 2.0))
          bodies.min_by.with_index do |body, i|
            [Spore::Geometry.distance(body.origin_x, body.origin_y, cx, cy), i]
          end
        end

        def remove_overlaps(bodies, root, max_iterations)
          max_iterations.times do
            pairs = Spore::OverlapSweep.pairs(bodies)
            break if pairs.empty?

            tree = Spore::SpanningTree.build(
              tree_edges(bodies, pairs), root
            ) { |first, second| cost(first, second) }
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

        # Negative and growing with the overlap when the rectangles overlap,
        # so the most overlapped pairs join the tree first.
        def cost(first, second)
          distance = Spore::Geometry.shortest_distance(first, second)
          return distance if distance >= 0

          between = Spore::Geometry.distance(first.center_x, first.center_y,
                                             second.center_x, second.center_y)
          -(Spore::Geometry.overlap(first, second) - 1) * between
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

        def place(body)
          node = body.source
          node.x = body.center_x - (node.width.to_f / 2.0)
          node.y = body.center_y - (node.height.to_f / 2.0)
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
