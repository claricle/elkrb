# frozen_string_literal: true

require_relative "gap"
require_relative "geometry"

module Elkrb
  module Layout
    module Spore
      # Compacts a spanning tree depth first: once a node's subtrees are
      # compacted, each is slid as one piece toward the node until it would
      # touch something, so the gaps between tree neighbours close.
      class DepthFirstCompaction
        # :free slides along the line between the two centres; the others
        # slide along one axis only. :orthogonal picks the axis the centres
        # are further apart on.
        MODES = %i[free orthogonal horizontal vertical].freeze

        # @param tree [SpanningTree::Branch] the tree, rooted at the branch
        #   that stays put
        # @param mode [Symbol] one of MODES
        def self.compact(tree, mode: :free)
          new(tree, mode).compact
        end

        def initialize(tree, mode)
          @root = tree
          @mode = mode
        end

        def compact
          compact_branch(@root)
        end

        private

        def compact_branch(branch)
          branch.children.each { |child| compact_branch(child) }
          close_gaps(branch)
        end

        def close_gaps(branch)
          branch.children.each { |child| close_gap(branch.body, child) }
        end

        def close_gap(parent, child)
          slide = slide_toward(parent, child.body)
          limit = limit_by_others(@root, child, slide, length(slide))
          translate(child, scale_to(slide, limit))
        end

        # The way and the distance the child would slide to meet its parent.
        def slide_toward(parent, child)
          slide = [parent.center_x - child.center_x,
                   parent.center_y - child.center_y]
          return scale_to(slide, Gap.underlap(parent, child)) if @mode == :free

          slide_along(along_x?(slide) ? 0 : 1, parent, child, slide)
        end

        def along_x?(slide)
          case @mode
          when :horizontal then true
          when :vertical then false
          else slide[0].abs >= slide[1].abs
          end
        end

        # Slides along axis +index+ (0 = x, 1 = y) only; the child stops at
        # the parent's side when they share a stretch of the other axis.
        def slide_along(index, parent, child, slide)
          line = [0.0, 0.0].tap { |vector| vector[index] = slide[index] }
          along, across = Geometry.axes(parent, child).rotate(index)
          return line unless shares_stretch?(across)

          scale_to(line, along.separation)
        end

        def shares_stretch?(axis)
          axis.low_b + axis.size_b > axis.low_a &&
            axis.low_b < axis.low_a + axis.size_a
        end

        # The shortest of +limit+ and the distance from every body outside
        # the child's own subtree to the bodies below the child.
        def limit_by_others(branch, child, slide, limit)
          limit = [limit, limit_by_below(branch.body, child, slide, limit)].min
          branch.children.each do |sub|
            next if sub.equal?(child)

            limit = [limit, limit_by_others(sub, child, slide, limit)].min
          end
          limit
        end

        # Looks at the bodies below +branch+, not at +branch+ itself.
        def limit_by_below(other, branch, slide, limit)
          branch.children.each do |sub|
            if Gap.touch?(other, sub.body)
              return 0 if Gap.pressed?(other, sub.body, slide)
            else
              limit = [limit, Gap.distance(other, sub.body, slide)].min
            end
            limit = [limit, limit_by_below(other, sub, slide, limit)].min
          end
          limit
        end

        def translate(branch, shift)
          branch.body.translate(*shift)
          branch.children.each { |sub| translate(sub, shift) }
        end

        def length(vector)
          Math.sqrt((vector[0] * vector[0]) + (vector[1] * vector[1]))
        end

        # Same direction, new length (a zero vector stays zero).
        def scale_to(vector, new_length)
          size = length(vector)
          return vector unless size.positive?

          [vector[0] / size * new_length, vector[1] / size * new_length]
        end
      end
    end
  end
end
