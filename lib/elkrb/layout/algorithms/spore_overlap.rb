# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      # SPOrE Overlap Removal algorithm
      #
      # Removes node overlaps while preserving the overall structure
      # of the layout by applying constrained positioning.
      class SporeOverlap < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.empty?

          # Iteratively remove overlaps
          max_iterations = graph.layout_options&.[]("spore.maxIterations") || 50
          min_spacing = graph.layout_options&.[]("spore.nodeSpacing") || 10.0

          max_iterations.times do
            overlaps = find_overlaps(graph.children, min_spacing)
            break if overlaps.empty?

            resolve_overlaps(overlaps, min_spacing)
          end

          # Apply padding
          apply_padding(graph)

          graph
        end

        private

        def find_overlaps(nodes, min_spacing)
          overlaps = []

          nodes.each_with_index do |node1, i|
            nodes[(i + 1)..].each do |node2|
              if overlapping?(node1, node2, min_spacing)
                overlaps << [node1, node2]
              end
            end
          end

          overlaps
        end

        def overlapping?(node1, node2, min_spacing)
          # Calculate bounding boxes with spacing
          left1 = node1.x - (min_spacing / 2.0)
          right1 = node1.x + node1.width + (min_spacing / 2.0)
          top1 = node1.y - (min_spacing / 2.0)
          bottom1 = node1.y + node1.height + (min_spacing / 2.0)

          left2 = node2.x - (min_spacing / 2.0)
          right2 = node2.x + node2.width + (min_spacing / 2.0)
          top2 = node2.y - (min_spacing / 2.0)
          bottom2 = node2.y + node2.height + (min_spacing / 2.0)

          # Check for overlap
          !(right1 <= left2 || left1 >= right2 || bottom1 <= top2 || top1 >= bottom2)
        end

        def resolve_overlaps(overlaps, min_spacing)
          overlaps.each do |node1, node2|
            # Calculate overlap amounts
            center1_x = node1.x + (node1.width / 2.0)
            center1_y = node1.y + (node1.height / 2.0)
            center2_x = node2.x + (node2.width / 2.0)
            center2_y = node2.y + (node2.height / 2.0)

            dx = center2_x - center1_x
            dy = center2_y - center1_y

            # Calculate minimum required distance
            min_dist_x = ((node1.width + node2.width) / 2.0) + min_spacing
            min_dist_y = ((node1.height + node2.height) / 2.0) + min_spacing

            # Determine movement direction
            if dx.abs > dy.abs
              # Move horizontally
              if dx.positive?
                # node2 is to the right
                overlap = min_dist_x - dx
                if overlap.positive?
                  node2.x += overlap / 2.0
                  node1.x -= overlap / 2.0
                end
              else
                # node2 is to the left
                overlap = min_dist_x + dx
                if overlap.positive?
                  node2.x -= overlap / 2.0
                  node1.x += overlap / 2.0
                end
              end
            elsif dy.positive?
              # Move vertically
              overlap = min_dist_y - dy
              if overlap.positive?
                node2.y += overlap / 2.0
                node1.y -= overlap / 2.0
              end
            # node2 is below
            else
              # node2 is above
              overlap = min_dist_y + dy
              if overlap.positive?
                node2.y -= overlap / 2.0
                node1.y += overlap / 2.0
              end
            end
          end
        end
      end
    end
  end
end
