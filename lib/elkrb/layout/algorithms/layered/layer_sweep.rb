# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # ELK's layer sweep: barycenter passes that alternate direction while
        # the crossing count falls, started from a random order of the first
        # layer and repeated, keeping the best run.
        #
        # Every draw comes from the seeded generator in the order ELK makes
        # it, because the draws are what tell two equally good orders apart.
        # The generator is shared with the greedy switch that runs after, so
        # the caller passes the one it keeps.
        class LayerSweep
          # ELK's default for elk.layered.thoroughness.
          THOROUGHNESS = 7
          FLOAT_UNIT = 1.0 / (1 << 24)
          JITTER_SPAN = 0.07000000029802322
          JITTER_OFFSET = 0.03500000014901161

          # @param layers [Array<Array>] reordered in place
          # @param port_order [PortOrder] reordered in place
          # @param random [JavaRandom] the shared generator
          # @param crossings [#call] counts the crossings of the current order
          def initialize(layers, port_order, random, crossings)
            @layers = layers
            @port_order = port_order
            @random = random
            @crossings = crossings
          end

          def minimize
            seed = @random.next_long
            @node_relative = @random.next_bits(1) != 0
            @random.seed = seed
            restore(best_of_runs)
          end

          private

          # The first run wins a tie, and a run with no crossings ends the
          # search.
          def best_of_runs
            best = nil
            THOROUGHNESS.times do
              crossings, order = run
              next if best && crossings >= best.first

              best = [crossings, order]
              break if crossings.zero?
            end
            best.last
          end

          # One random start, then sweeps while the count keeps falling. The
          # order kept is the one before the sweep that failed to improve.
          def run
            forward = @random.next_bits(1) != 0
            randomize_first_layer(forward)
            sweep(forward, true)
            improve_while_falling(forward, @crossings.call)
          end

          def improve_while_falling(forward, crossings)
            loop do
              kept = snapshot
              return [0, kept] if crossings.zero?

              forward = !forward
              sweep(forward, false)
              fewer = @crossings.call
              return [crossings, kept] unless crossings > fewer

              crossings = fewer
            end
          end

          def snapshot
            [@layers.map(&:dup), @port_order.snapshot]
          end

          def restore(snapshot)
            layers, ports = snapshot
            @layers.each_with_index { |layer, i| layer.replace(layers[i]) }
            @port_order.restore(ports)
          end

          def randomize_first_layer(forward)
            layer = @layers[forward ? 0 : -1]
            keys = layer.map { @random.next_double }
            layer.replace(stable_order(layer, keys))
          end

          def stable_order(layer, keys)
            layer.each_index.sort_by { |i| [keys[i], i] }
              .map { |i| layer[i] }
          end

          def sweep(forward, first)
            indexes = (0...@layers.length).to_a
            indexes.reverse! unless forward
            indexes.drop(1).each do |index|
              fixed = forward ? index - 1 : index + 1
              reorder(index, fixed, forward, first)
              distribute_ports(index, fixed, forward)
            end
          end

          def reorder(index, fixed, forward, first)
            ranks = ranks_of(@layers[fixed], forward ? :east : :west)
            layer = @layers[index]
            side = forward ? :west : :east
            values = layer.map { |item| barycenter(item, side, ranks) }
            values = first ? random_fill(values) : interpolate_fill(values)
            layer.replace(stable_order(layer, values))
          end

          # The mean rank of the fixed ports an item meets, nudged by a
          # draw so that equal means are told apart.
          def barycenter(item, side, ranks)
            others = @port_order.visual(item.id, side).flat_map(&:others)
            return if others.empty?

            jitter = (@random.next_bits(24) * FLOAT_UNIT * JITTER_SPAN) -
              JITTER_OFFSET
            (others.sum { |other| ranks.fetch(other) } + jitter) /
              others.length
          end

          # First sweep: an item with no edge to the fixed layer lands at a
          # random place between the known means.
          def random_fill(values)
            span = (values.compact.max || 0) + 2
            values.map do |value|
              value || ((@random.next_bits(24) * FLOAT_UNIT * span) - 1)
            end
          end

          # Later sweeps: such an item sits halfway between its neighbours.
          def interpolate_fill(values)
            last = -1
            values.each_with_index.map do |value, i|
              value ||= (last + (values[i..].compact.first || (last + 1))) / 2.0
              last = value
            end
          end

          # Orders the free layer's ports toward the fixed layer, then the
          # fixed layer's ports toward the free one.
          def distribute_ports(index, fixed, forward)
            side = forward ? :west : :east
            far = forward ? :east : :west
            [[index, side, fixed, far], [fixed, far, index, side]]
              .each do |layer, near, other, other_side|
                ranks = ranks_of(@layers[other], other_side)
                @layers[layer].each { |item| order_ports(item, near, ranks) }
              end
          end

          # WEST lists run bottom to top, so a WEST key is negated.
          def order_ports(item, side, ranks)
            sign = side == :west ? -1 : 1
            @port_order.sort!(item.id, side) do |port|
              sign * port.others.sum { |other| ranks.fetch(other) } /
                port.others.length.to_f
            end
          end

          # ELK numbers the ports of a layer one of two ways, chosen by a
          # draw: running across the whole layer, or as a fraction inside
          # each node's own slot.
          def ranks_of(layer, side)
            ranks = {}.compare_by_identity
            consumed = 0
            layer.each_with_index do |item, position|
              ports = @port_order.visual(item.id, side)
              ports.each_with_index do |port, k|
                ranks[port] = port_rank(position, consumed, k, ports.length)
              end
              consumed += ports.length
            end
            ranks
          end

          def port_rank(position, consumed, index, count)
            return consumed + index + 1 unless @node_relative

            position + ((index + 1.0) / (count + 1))
          end
        end
      end
    end
  end
end
