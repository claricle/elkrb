# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Places nodes within their assigned layers
        #
        # This phase calculates the x and y coordinates for each node
        # based on their layer assignment and spacing requirements.
        class NodePlacer
          attr_writer :index

          # @param layer_spacing [Numeric] gap between consecutive layers
          # @param node_spacing [Numeric] gap between nodes in one layer
          def initialize(_graph, layers, direction: "RIGHT",
                         layer_spacing: 20.0, node_spacing: 20.0)
            @layers = layers
            @direction = direction
            @layer_spacing = layer_spacing
            @node_spacing = node_spacing
          end

          def place_nodes
            return unless @layers && !@layers.empty?

            size_dummy_slots
            cross_extents = calculate_directional_cross_extents
            layer_extents = calculate_layer_extents
            layer_positions = calculate_layer_positions(layer_extents)

            place_all_layers(cross_extents, layer_positions)
            align_fan_out_parents(cross_extents.max || 0)
            mirror_layers(layer_positions, layer_extents)
          end

          private

          def size_dummy_slots
            layer_dimension = horizontal? ? :width : :height
            cross_dimension = horizontal? ? :height : :width
            @layers.each do |items|
              size_dummy_layer(items, layer_dimension, cross_dimension)
            end
          end

          def size_dummy_layer(items, layer_dimension, cross_dimension)
            nodes = items.reject { |item| dummy?(item) }
            layer_extent = maximum_size(nodes, layer_dimension)
            cross_extent = maximum_size(nodes, cross_dimension)
            items.select { |item| dummy?(item) }.each do |slot|
              slot.public_send("#{layer_dimension}=", layer_extent)
              slot.public_send("#{cross_dimension}=", cross_extent)
            end
          end

          def maximum_size(nodes, dimension)
            nodes.map { |node| size(node, dimension) }.max || 0
          end

          def dummy?(item)
            item.respond_to?(:dummy?) && item.dummy?
          end

          def calculate_layer_widths
            calculate_cross_extents(:width)
          end

          def calculate_layer_heights
            calculate_cross_extents(:height)
          end

          def calculate_directional_cross_extents
            horizontal? ? calculate_layer_heights : calculate_layer_widths
          end

          def calculate_cross_extents(dimension)
            @layers.map do |nodes|
              next 0 if nodes.empty?

              gaps = (nodes.length - 1) * @node_spacing
              nodes.sum { |node| size(node, dimension) } + gaps
            end
          end

          def place_all_layers(cross_extents, layer_positions)
            max_cross_extent = cross_extents.max || 0
            @layers.each_with_index do |layer_nodes, layer_index|
              cross_offset =
                (max_cross_extent - cross_extents[layer_index]) / 2.0
              place_layer(layer_nodes, layer_positions[layer_index],
                          cross_offset)
            end
          end

          def calculate_layer_extents
            dimension = horizontal? ? :width : :height
            @layers.map do |nodes|
              nodes.map { |node| size(node, dimension) }.max || 0
            end
          end

          def calculate_layer_positions(extents)
            position = 0
            extents.map do |extent|
              position.tap { position += extent + @layer_spacing }
            end
          end

          def place_layer(nodes, layer_position, cross_position)
            nodes.each do |node|
              place_node(node, layer_position, cross_position)
              cross_position += cross_size(node) + @node_spacing
            end
          end

          def place_node(node, layer_position, cross_position)
            if horizontal?
              node.x = layer_position
              node.y = cross_position
            else
              node.x = cross_position
              node.y = layer_position
            end
          end

          def align_fan_out_parents(cross_extent)
            return unless @index

            targets_by_source = fan_out_targets_by_source
            @layers.each_cons(2) do |parents, children|
              align_parent_layer(
                parents, children, targets_by_source, cross_extent
              )
            end
          end

          def align_parent_layer(parents, children, targets_by_source,
                                 cross_extent)
            child_ids = children.to_h { |node| [node.id, node] }
            parents.each do |parent|
              targets = targets_by_source[parent.id].filter_map do |target_id|
                child_ids[target_id]
              end.uniq(&:id)
              next unless targets.length > 1

              align_parent(parent, targets, parents, cross_extent)
            end
          end

          def fan_out_targets_by_source
            @index.edges.each_with_object(Hash.new do |hash, id|
              hash[id] = []
            end) do |edge, targets|
              source = endpoint_owner(edge.sources)
              target = endpoint_owner(edge.targets)
              targets[source] << target if source && target
            end
          end

          def endpoint_owner(endpoints)
            id = (endpoints || []).first
            @index.owner(id)&.id if id
          end

          def align_parent(parent, children, siblings, cross_extent)
            centroid = children.sum do |child|
              cross_center(child)
            end / children.length
            desired = centroid - (cross_size(parent) / 2.0)
            return unless desired.between?(0, cross_extent - cross_size(parent))
            return unless room_for?(parent, desired, siblings)

            set_cross_position(parent, desired)
          end

          def room_for?(parent, desired, siblings)
            siblings.reject { |node| node.equal?(parent) }.all? do |sibling|
              sibling_start = cross_position(sibling)
              sibling_end = sibling_start + cross_size(sibling)
              desired + cross_size(parent) + @node_spacing <= sibling_start ||
                sibling_end + @node_spacing <= desired
            end
          end

          def cross_center(node)
            cross_position(node) + (cross_size(node) / 2.0)
          end

          def cross_position(node)
            horizontal? ? node.y : node.x
          end

          def set_cross_position(node, position)
            node.public_send("#{horizontal? ? :y : :x}=", position)
          end

          def mirror_layers(layer_positions, layer_extents)
            return unless %w[LEFT UP].include?(@direction)

            bound = layer_positions.zip(layer_extents)
              .map { |position, extent| position + extent }.max
            coordinate, dimension = mirror_axis

            @layers.flatten.each do |node|
              mirror_node(node, coordinate, dimension, bound)
            end
          end

          def mirror_axis
            @direction == "LEFT" ? %i[x width] : %i[y height]
          end

          def mirror_node(node, coordinate, dimension, bound)
            mirrored = bound - node.public_send(coordinate) -
              size(node, dimension)
            node.public_send("#{coordinate}=", mirrored)
          end

          def horizontal?
            %w[RIGHT LEFT].include?(@direction)
          end

          def cross_size(node)
            size(node, horizontal? ? :height : :width)
          end

          def size(node, dimension)
            node.public_send(dimension) || 0
          end
        end
      end
    end
  end
end
