# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # The port slots every layer item exposes toward its neighbouring
        # layers, and the order they sit in.
        #
        # An edge crossing one layer gap is a Segment from an EAST slot of the
        # item in the earlier layer to a WEST slot of the item in the later
        # one. A slot is an explicit port, or the one slot a port-less
        # endpoint gets per edge.
        #
        # A list is kept in the order ELK keeps it: EAST lists run top to
        # bottom, WEST lists bottom to top. #visual always answers top to
        # bottom. Sorting a WEST list ascending therefore places the lowest
        # value at the bottom; the sweep in CrossingMinimizer depends on
        # that.
        class PortOrder
          # One slot on the EAST or WEST side of a layer item.
          class Port
            attr_reader :item_id, :side, :declared, :sequence, :segments

            def initialize(item_id:, side:, declared:, sequence:)
              @item_id = item_id
              @side = side
              @declared = declared
              @sequence = sequence
              @segments = []
            end

            def others
              segments.map { |segment| segment.other_port(self) }
            end
          end

          # One edge crossing one layer gap, `from_port` in the earlier layer.
          Segment = Struct.new(:edge, :from_port, :to_port) do
            def other_port(port)
              port.equal?(from_port) ? to_port : from_port
            end
          end

          SIDES = %i[east west].freeze

          attr_reader :segments

          # @param layers [Array<Array>] nodes and DummySlots per layer
          # @param index [NodeIndex, nil] resolves edge endpoints to nodes
          def initialize(layers, index)
            @layer_of = layer_map(layers)
            @slots = dummy_slots_by_edge(layers)
            @ports = {}
            @segments = []
            @index = index
            (index ? index.edges : []).each_with_index do |edge, order|
              add_edge(edge, order)
            end
            @lists = build_lists
          end

          # Ports of one side, top to bottom.
          def visual(item_id, side)
            list = list(item_id, side)
            side == :west ? list.reverse : list
          end

          # Reorders a list ascending by the block's value. The sort is
          # stable, so equal values keep their order.
          def sort!(item_id, side)
            list = list(item_id, side)
            @lists[[item_id, side]] =
              list.each_with_index.sort_by do |port, position|
                [yield(port), position]
              end.map(&:first)
          end

          # The port lists as they are now, for #restore.
          def snapshot
            @lists.transform_values(&:dup)
          end

          def restore(snapshot)
            @lists = snapshot.transform_values(&:dup)
          end

          private

          def list(item_id, side)
            @lists.fetch([item_id, side], [])
          end

          def layer_map(layers)
            layers.each_with_index.with_object({}) do |(layer, number), map|
              layer.each { |item| map[item.id] = number }
            end
          end

          def dummy_slots_by_edge(layers)
            slots = {}.compare_by_identity
            layers.flatten.select { |item| item.respond_to?(:layer_index) }
              .sort_by(&:layer_index).each do |slot|
                (slots[slot.edge] ||= []) << slot
              end
            slots
          end

          def add_edge(edge, order)
            source = owner(edge.sources)
            target = owner(edge.targets)
            return unless placed?(source) && placed?(target)

            add_chain(edge, order, *earlier_first(edge, source, target))
          end

          # The two nodes, earlier layer first, with the endpoint ids the
          # edge names on each.
          def earlier_first(edge, source, target)
            named = [edge.sources.first, edge.targets.first]
            if @layer_of[source.id] < @layer_of[target.id]
              [[source, target], named]
            else
              [[target, source], named.reverse]
            end
          end

          def placed?(node)
            node && @layer_of.key?(node.id)
          end

          # `named` holds the endpoint ids the edge gives on the earlier and
          # the later layer.
          def add_chain(edge, order, ends, named)
            chain = [ends.first, *Array(@slots[edge]), ends.last]
            chain.each_cons(2).with_index do |pair, position|
              next unless adjacent?(*pair)

              add_segment(edge, order, pair,
                          [position.zero? && named.first,
                           position == chain.length - 2 && named.last])
            end
          end

          def adjacent?(from, to)
            @layer_of[to.id] - @layer_of[from.id] == 1
          end

          def add_segment(edge, order, items, endpoints)
            segment = Segment.new(
              edge,
              port(items.first, :east, order, endpoints.first),
              port(items.last, :west, order, endpoints.last),
            )
            segment.from_port.segments << segment
            segment.to_port.segments << segment
            @segments << segment
          end

          def port(item, side, order, endpoint)
            declared = declared_port(item, endpoint)
            key = declared ? declared.id : [:edge, order]
            @ports[[item.id, side, key]] ||= Port.new(
              item_id: item.id, side: side, declared: declared,
              sequence: declared ? [0, item.ports.index(declared)] : [1, order]
            )
          end

          def declared_port(item, endpoint)
            return unless endpoint && item.respond_to?(:ports)

            item.ports&.find { |candidate| candidate.id == endpoint }
          end

          def owner(endpoints)
            id = (endpoints || []).first
            @index.owner(id) if id
          end

          def build_lists
            @ports.values.group_by { |port| [port.item_id, port.side] }
              .transform_values { |ports| ports.sort_by(&:sequence) }
          end
        end
      end
    end
  end
end
