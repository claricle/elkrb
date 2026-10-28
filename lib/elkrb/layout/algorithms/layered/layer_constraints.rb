# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Moves nodes to the layers their constraints ask for, after the
        # longest-path pass has assigned every node a layer.
        #
        # `elk.layered.layering.layerConstraint` puts a node first or last:
        # FIRST and LAST share a layer with other nodes, FIRST_SEPARATE and
        # LAST_SEPARATE get a layer of their own. `constraints.layer` is an
        # explicit layer index, applied last, so it wins over the option.
        # Both override the edges.
        class LayerConstraints
          OPTION = "elk.layered.layering.layerConstraint"

          # @param nodes [Hash{String => Graph::Node}] the nodes by id
          # @param node_layers [Hash{String => Integer}] layer by node id,
          #   updated in place
          # @param resolver [Options::Resolver]
          def initialize(nodes, node_layers, resolver)
            @nodes = nodes
            @layers = node_layers
            @kinds = nodes.transform_values do |node|
              resolver.get(OPTION, node)
            end
          end

          def apply
            place_by_kind
            place_by_index
          end

          private

          def ids_of(kind)
            @kinds.select { |_id, value| value == kind }.keys
          end

          def place_by_kind
            first_separate = ids_of("FIRST_SEPARATE")
            last_separate = ids_of("LAST_SEPARATE")
            first_layer = first_separate.empty? ? 0 : 1

            shift(@nodes.keys - first_separate - last_separate, first_layer)
            set(ids_of("FIRST"), first_layer)
            set(first_separate, 0)

            place_last(last_separate, first_layer)
          end

          def place_last(last_separate, fallback)
            last_layer = last_movable_layer(last_separate, fallback)
            set(ids_of("LAST"), last_layer)
            set(last_separate, last_layer + 1)
          end

          def last_movable_layer(last_separate, fallback)
            movable = @nodes.keys - last_separate - ids_of("LAST")
            @layers.values_at(*movable).max || fallback
          end

          def place_by_index
            @nodes.each do |id, node|
              index = node.constraints&.layer
              @layers[id] = [index, 0].max if index
            end
          end

          def shift(ids, by)
            ids.each { |id| @layers[id] += by }
          end

          def set(ids, layer)
            ids.each { |id| @layers[id] = layer }
          end
        end
      end
    end
  end
end
