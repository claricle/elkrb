# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        module Bk
          # The layers of one Brandes-Koepf pass, turned so the pass always
          # sweeps from the first layer to the last and packs toward the
          # start of each layer. The four passes differ only in this view.
          class View
            # An edge toward the previous layer, with the offset of both of
            # its ports measured along the view's cross axis.
            Link = Struct.new(:neighbor_id, :own_offset, :neighbor_offset,
                              :segment)

            attr_reader :layers

            # @param orientation [Array<Symbol>] the sweep, then the cross
            #   direction. :left reads the earlier layer as the neighbour,
            #   :right the later one; :down packs toward the top of a layer,
            #   :up toward the bottom
            # @param sizes [Hash{String=>Numeric}] cross size per item id
            # @param offsets [Hash] cross offset of each port from the top
            #   of its item
            def initialize(layers, port_order, sizes, offsets, orientation)
              sweep, cross = orientation
              @port_order = port_order
              @sizes = sizes
              @offsets = offsets
              @facing = sweep == :left ? :west : :east
              @flip = cross == :up
              @layers = orient(layers, sweep)
              @position = positions
              @links = {}
            end

            def size(id)
              @sizes.fetch(id)
            end

            def position(id)
              @position.fetch(id)
            end

            def predecessor(id)
              layer = @layers[layer_of(id)]
              index = position(id)
              layer[index - 1] if index.positive?
            end

            # Edges to the previous layer ordered by the neighbour's position.
            def links(id)
              @links[id] ||= begin
                all = @port_order.visual(id, @facing).flat_map do |port|
                  port.segments.map { |segment| link(id, port, segment) }
                end
                all.each_with_index
                  .sort_by { |link, i| [position(link.neighbor_id), i] }
                  .map(&:first)
              end
            end

            private

            def orient(layers, sweep)
              ordered = sweep == :right ? layers.reverse : layers
              ordered.map do |layer|
                ids = layer.map(&:id)
                @flip ? ids.reverse : ids
              end
            end

            def positions
              @layer_by_id = {}
              @layers.each_with_index.with_object({}) do |(layer, number), map|
                layer.each_with_index do |id, index|
                  map[id] = index
                  @layer_by_id[id] = number
                end
              end
            end

            def layer_of(id)
              @layer_by_id.fetch(id)
            end

            def link(id, port, segment)
              other = segment.other_port(port)
              Link.new(other.item_id, offset(id, port),
                       offset(other.item_id, other), segment)
            end

            def offset(id, port)
              value = @offsets.fetch(port)
              @flip ? size(id) - value : value
            end
          end
        end
      end
    end
  end
end
