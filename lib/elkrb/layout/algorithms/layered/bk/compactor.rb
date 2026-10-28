# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        module Bk
          # Horizontal compaction of Brandes-Koepf: places every block as
          # close to the start of its layer as the spacing allows, then
          # slides whole classes of blocks toward each other.
          class Compactor
            # @param spacing [#call] gap required between two neighbours,
            #   given their ids
            def initialize(view, aligner, spacing)
              @view = view
              @aligner = aligner
              @spacing = spacing
              @coordinate = {}
              @sink = Hash.new { |_, id| id }
              @shift = Hash.new(Float::INFINITY)
            end

            # @return [Hash{String=>Float}] start of every item along the
            #   view's cross axis
            def place
              roots = @view.layers.flatten.select do |id|
                @aligner.root[id] == id
              end
              roots.each { |root| place_block(root) }
              @view.layers.flatten.to_h { |id| [id, absolute(id)] }
            end

            private

            def absolute(id)
              root = @aligner.root[id]
              shift = @shift[@sink[root]]
              base = @coordinate[root]
              base += shift if shift.finite?
              base + @aligner.inner[id]
            end

            def place_block(root)
              return if @coordinate.key?(root)

              @coordinate[root] = 0.0
              @aligner.block(root).each do |member|
                neighbour = @view.predecessor(member)
                place_against(root, member, neighbour) if neighbour
              end
            end

            def place_against(root, member, neighbour)
              other = @aligner.root[neighbour]
              place_block(other)
              @sink[root] = @sink[other] if @sink[root] == root
              required = separation(neighbour, member)
              if @sink[root] == @sink[other]
                push_apart(root, other, required)
              else
                record_slack(root, other, required)
              end
            end

            # Distance between the tops of two blocks, so that `neighbour`
            # and `member` end up the spacing apart.
            def separation(neighbour, member)
              @aligner.inner[neighbour] + @view.size(neighbour) +
                @spacing.call(neighbour, member) - @aligner.inner[member]
            end

            def push_apart(root, other, required)
              @coordinate[root] =
                [@coordinate[root], @coordinate[other] + required].max
            end

            def record_slack(root, other, required)
              sink = @sink[other]
              slack = @coordinate[root] - @coordinate[other] - required
              @shift[sink] = [@shift[sink], slack].min
            end
          end
        end
      end
    end
  end
end
