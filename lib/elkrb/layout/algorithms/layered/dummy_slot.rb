# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Internal layer position reserved for one segment of a long edge.
        class DummySlot
          attr_accessor :x, :y, :width, :height
          attr_reader :edge, :edge_id, :layer_index, :edge_order, :id

          def initialize(edge:, layer_index:, edge_order:)
            @edge = edge
            @edge_id = edge.id
            @layer_index = layer_index
            @edge_order = edge_order
            @id = "__elkrb_dummy_#{edge_order}_#{layer_index}"
            @x = 0.0
            @y = 0.0
            @width = 0.0
            @height = 0.0
          end

          def dummy?
            true
          end
        end
      end
    end
  end
end
