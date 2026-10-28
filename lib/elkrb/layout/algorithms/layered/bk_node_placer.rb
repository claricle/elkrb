# frozen_string_literal: true

require_relative "port_order"
require_relative "port_spread"
require_relative "bk/view"
require_relative "bk/aligner"
require_relative "bk/compactor"

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Brandes-Koepf node placement along the cross axis. Four passes
        # run (each sweep direction packed toward each end). By default the
        # narrowest pass wins, the first of them on a tie, which is what
        # ELK does when no fixed alignment is set. With `place(alignment:
        # :balanced)` the passes are aligned on the narrowest and every node
        # takes the mean of its two middle coordinates.
        class BkNodePlacer
          PASSES = [%i[left down], %i[left up],
                    %i[right down], %i[right up]].freeze

          # @param layers [Array<Array>] nodes and DummySlots per layer
          # @param port_order [PortOrder]
          # @param spacing [#call] gap between two neighbours in a layer,
          #   given their ids
          # @param size_of [#call] cross size of a layer item
          # @param port_size_of [#call] cross size of a port
          def initialize(layers, port_order, spacing:, size_of:,
                         port_size_of:)
            @layers = layers
            @port_order = port_order
            @spacing = spacing
            @sizes = layers.flatten.to_h do |item|
              [item.id, size_of.call(item)]
            end
            @offsets = PortSpread.offsets(layers, port_order, @sizes,
                                          port_size_of)
            @marked = type_one_conflicts
          end

          # @param alignment [Symbol] :smallest or :balanced
          # @return [Hash{String=>Float}] cross coordinate of each item,
          #   starting at zero
          def place(alignment: :smallest)
            return {} if @sizes.empty?

            passes = PASSES.map { |orientation| pass(orientation) }
            tops = alignment == :balanced ? balance(passes) : narrowest(passes)
            low = tops.values.min
            tops.transform_values { |top| top - low }
          end

          private

          def pass(orientation)
            view = Bk::View.new(@layers, @port_order, @sizes, @offsets,
                                orientation)
            aligner = Bk::Aligner.new(view, @marked)
            starts = Bk::Compactor.new(view, aligner, @spacing).place
            return starts unless orientation.last == :up

            starts.to_h { |id, start| [id, -(start + @sizes[id])] }
          end

          def narrowest(passes)
            passes.min_by { |tops| width(span(tops)) }
          end

          def balance(passes)
            aligned = align_to_narrowest(passes)
            @sizes.keys.to_h { |id| [id, median(aligned.map { |t| t[id] })] }
          end

          # Shifts every pass so it shares the narrowest pass's start (packed
          # downward) or end (packed upward).
          def align_to_narrowest(passes)
            spans = passes.map { |tops| span(tops) }
            narrow = spans.min_by { |bounds| width(bounds) }
            passes.zip(spans, PASSES).map do |tops, bounds, orientation|
              delta = anchor(narrow, orientation) - anchor(bounds, orientation)
              tops.transform_values { |top| top + delta }
            end
          end

          def anchor(bounds, orientation)
            orientation.last == :down ? bounds.first : bounds.last
          end

          def width(bounds)
            bounds.last - bounds.first
          end

          def span(tops)
            [tops.map { |_, top| top }.min,
             tops.map { |id, top| top + @sizes[id] }.max]
          end

          def median(values)
            middle = values.sort[1..2]
            middle.sum / 2.0
          end

          # Type 1 conflicts: a segment crossing an inner segment (both ends
          # dummies) must never join a block, or the long edge would bend.
          def type_one_conflicts
            marked = {}.compare_by_identity
            @layers.each_cons(2) do |left, right|
              mark_pair(left, right, marked)
            end
            marked
          end

          def mark_pair(left, right, marked)
            positions = left.each_with_index.to_h { |item, i| [item.id, i] }
            low = 0
            scanned = 0
            right.each_with_index do |item, index|
              high = run_end(item, index == right.length - 1, left, positions)
              next unless high

              mark_run(right[scanned..index], positions, low..high, marked)
              scanned = index + 1
              low = high
            end
          end

          # Where the run of nodes ending at `item` may attach in the layer
          # before it; nil while the run continues.
          def run_end(item, last, left, positions)
            inner = inner_segment(item)
            return positions.fetch(inner.from_port.item_id) if inner

            left.length - 1 if last
          end

          def mark_run(run, positions, allowed, marked)
            run.each do |item|
              segments_toward_west(item).each do |segment|
                above = positions.fetch(segment.from_port.item_id)
                marked[segment] = true unless allowed.cover?(above) ||
                  inner?(segment)
              end
            end
          end

          def segments_toward_west(item)
            @port_order.visual(item.id, :west).flat_map(&:segments)
          end

          def inner_segment(item)
            return unless dummy?(item)

            segments_toward_west(item).find { |segment| inner?(segment) }
          end

          def inner?(segment)
            @dummy_ids ||= @layers.flatten.select { |i| dummy?(i) }.to_set(&:id)
            @dummy_ids.include?(segment.from_port.item_id) &&
              @dummy_ids.include?(segment.to_port.item_id)
          end

          def dummy?(item)
            item.respond_to?(:dummy?) && item.dummy?
          end
        end
      end
    end
  end
end
