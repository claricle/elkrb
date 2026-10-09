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
        def initialize
          super
          @originals = {}
        end

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

            @originals[node.id] = [node.x, node.y]
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
            original = fixed_original(node)
            next unless original

            node.x, node.y = original
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
            original_x, original_y = fixed_original(node)
            next unless original_x

            if node.x != original_x || node.y != original_y
              errors << "Node '#{node.id}' has fixed_position constraint " \
                        "but was moved from (#{original_x}, #{original_y}) " \
                        "to (#{node.x}, #{node.y})"
            end
          end

          errors
        end

        private

        # The recorded position of a node that is still fixed, or nil. The
        # constraint is read from the node every time, so clearing
        # fixed_position releases a node recorded earlier.
        def fixed_original(node)
          return unless node.constraints&.fixed_position

          @originals[node.id]
        end
      end
    end
  end
end
