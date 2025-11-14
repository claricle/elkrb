# frozen_string_literal: true

require_relative "base_constraint"

module Elkrb
  module Layout
    module Constraints
      # Fixed position constraint
      #
      # Prevents nodes from being moved by the layout algorithm.
      # Nodes with fixed_position: true keep their existing x,y coordinates.
      #
      # @example
      #   node.x = 500
      #   node.y = 800
      #   node.constraints = NodeConstraints.new(fixed_position: true)
      #   # After layout, node remains at (500, 800)
      class FixedPositionConstraint < BaseConstraint
        # Apply fixed position constraint (pre-layout)
        #
        # Stores original positions of fixed nodes so they can be
        # restored after layout.
        #
        # @param graph [Graph::Graph] The graph
        # @return [Graph::Graph] The modified graph
        def apply(graph)
          all_nodes(graph).each do |node|
            next unless node.constraints&.fixed_position
            next if node.x.nil? || node.y.nil?

            # Store original position
            node.properties ||= {}
            node.properties["_constraint_fixed"] = true
            node.properties["_constraint_original_x"] = node.x
            node.properties["_constraint_original_y"] = node.y
          end

          graph
        end

        # Restore fixed positions (called post-layout as well)
        #
        # This is called both pre and post layout to ensure fixed positions
        # are preserved even if algorithms modify them.
        #
        # @param graph [Graph::Graph] The graph
        # @return [Graph::Graph] The modified graph
        def restore_fixed_positions(graph)
          all_nodes(graph).each do |node|
            next unless node.properties&.[]("_constraint_fixed")

            # Restore original position
            node.x = node.properties["_constraint_original_x"]
            node.y = node.properties["_constraint_original_y"]
          end

          graph
        end

        # Validate fixed positions were respected
        #
        # Checks that nodes marked as fixed didn't move during layout.
        #
        # @param graph [Graph::Graph] The graph to validate
        # @return [Array<String>] List of validation errors
        def validate(graph)
          errors = []

          all_nodes(graph).each do |node|
            next unless node.properties&.[]("_constraint_fixed")

            original_x = node.properties["_constraint_original_x"]
            original_y = node.properties["_constraint_original_y"]

            if node.x != original_x || node.y != original_y
              errors << "Node '#{node.id}' has fixed_position constraint " \
                        "but was moved from (#{original_x}, #{original_y}) " \
                        "to (#{node.x}, #{node.y})"
            end
          end

          errors
        end
      end
    end
  end
end
