# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Where the ports of one side sit along an item's cross axis: spread
        # evenly, as ELK spaces free ports.
        module PortSpread
          # Cross offset of each port's centre from the start of its item.
          #
          # @param layers [Array<Array>] items per layer
          # @param port_order [PortOrder]
          # @param sizes [Hash{String=>Numeric}] cross size per item id
          # @param port_size_of [#call] cross size of a port
          # @return [Hash] offset per port, keyed by identity
          def self.offsets(layers, port_order, sizes, port_size_of)
            offsets = {}.compare_by_identity
            layers.flatten.product(PortOrder::SIDES) do |item, side|
              ports = port_order.visual(item.id, side)
              spread(ports, sizes.fetch(item.id), port_size_of)
                .each { |port, mid| offsets[port] = mid }
            end
            offsets
          end

          def self.spread(ports, extent, port_size_of)
            widths = ports.map { |port| port_size_of.call(port) }
            ports.zip(centres(widths, extent))
          end

          def self.centres(widths, extent)
            gap = (extent - widths.sum) / (widths.length + 1)
            widths.each_with_index.map do |width, i|
              widths.first(i).sum + (gap * (i + 1)) + (width / 2.0)
            end
          end
        end
      end
    end
  end
end
