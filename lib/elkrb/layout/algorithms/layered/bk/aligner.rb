# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        module Bk
          # Vertical alignment of Brandes-Koepf: chains nodes into blocks
          # along median edges, then offsets each block's nodes so the edges
          # that joined them leave straight.
          class Aligner
            # @return [Hash] first node of each block, per node id
            attr_reader :root
            # @return [Hash] next node of the block; the last points at the
            #   root
            attr_reader :align
            # @return [Hash] distance of a node below the top of its block
            attr_reader :inner

            # @param marked [Hash] segments type 1 conflicts forbid aligning
            def initialize(view, marked)
              @view = view
              @marked = marked
              @root = {}
              @align = {}
              @via = {}
              @inner = Hash.new(0.0)
              view.layers.flatten.each { |id| start_block(id) }
              align_layers
              shift_blocks
            end

            def block(root_id)
              chain = [root_id]
              node = @align[root_id]
              until node == root_id
                chain << node
                node = @align[node]
              end
              chain
            end

            private

            def start_block(id)
              @root[id] = id
              @align[id] = id
            end

            def align_layers
              @view.layers.drop(1).each do |layer|
                previous = -1
                layer.each do |id|
                  link = alignable_link(id, previous)
                  next unless link

                  join(id, link)
                  previous = @view.position(link.neighbor_id)
                end
              end
            end

            def alignable_link(id, previous)
              links = @view.links(id)
              return if links.empty?

              links[((links.length - 1) / 2)..(links.length / 2)].find do |link|
                !@marked[link.segment] &&
                  previous < @view.position(link.neighbor_id)
              end
            end

            def join(id, link)
              upper = link.neighbor_id
              @align[upper] = id
              @root[id] = @root[upper]
              @align[id] = @root[id]
              @via[id] = link
            end

            def shift_blocks
              @root.each_key { |id| shift_block(id) if @root[id] == id }
            end

            def shift_block(root_id)
              chain = block(root_id)
              chain.each_cons(2) do |upper, lower|
                @inner[lower] = @inner[upper] + drop(@via.fetch(lower))
              end
              top = chain.map { |member| @inner[member] }.min
              chain.each { |member| @inner[member] -= top }
            end

            # How far below its upper neighbour a node sits so the edge
            # joining them leaves straight.
            def drop(link)
              link.neighbor_offset - link.own_offset
            end
          end
        end
      end
    end
  end
end
