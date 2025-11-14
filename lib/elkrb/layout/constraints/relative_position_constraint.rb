# frozen_string_literal: true

require_relative "base_constraint"

module Elkrb
  module Layout
    module Constraints
      # Relative position constraint
      #
      # Positions a node relative to another node with a specified offset.
      # The constrained node will be positioned at:
      #   x = reference_node.x + offset.x
      #   y = reference_node.y + offset.y
      #
      # @example
      #   api_node.constraints = NodeConstraints.new(
      #     relative_to: "backend_service",
      #     relative_offset: RelativeOffset.new(x: 150, y: 0)
      #   )
      #   # api_node will be 150px to the right of backend_service
      class RelativePositionConstraint < BaseConstraint
        # Apply relative position constraint
        #
        # Positions nodes relative to their reference nodes.
        # Processes in order of position_priority to handle chains.
        #
        # @param graph [Graph::Graph] The graph
        # @return [Graph::Graph] The modified graph
        def apply(graph)
          nodes_with_relative = all_nodes(graph).select do |node|
            node.constraints&.relative_to &&
              node.constraints.relative_offset
          end

          # Sort by priority (higher priority processed first)
          nodes_with_relative.sort_by! do |node|
            -(node.constraints.position_priority || 0)
          end

          # Apply relative positioning
          nodes_with_relative.each do |node|
            apply_relative_position(node, graph)
          end

          graph
        end

        # Validate relative position constraints
        #
        # Checks that reference nodes exist and positions are correct.
        #
        # @param graph [Graph::Graph] The graph to validate
        # @return [Array<String>] List of validation errors
        def validate(graph)
          errors = []

          all_nodes(graph).each do |node|
            next unless node.constraints&.relative_to

            ref_id = node.constraints.relative_to
            ref_node = find_node(graph, ref_id)

            if ref_node.nil?
              errors << "Node '#{node.id}' has relative_to constraint " \
                        "referencing '#{ref_id}' which doesn't exist"
              next
            end

            # Validate position if offset is specified
            if node.constraints.relative_offset
              expected_x = ref_node.x + node.constraints.relative_offset.x
              expected_y = ref_node.y + node.constraints.relative_offset.y

              tolerance = 0.01
              if (node.x - expected_x).abs > tolerance ||
                  (node.y - expected_y).abs > tolerance
                errors << "Node '#{node.id}' relative position incorrect. " \
                          "Expected (#{expected_x}, #{expected_y}), " \
                          "got (#{node.x}, #{node.y})"
              end
            end
          end

          errors
        end

        private

        # Apply relative position to a single node
        def apply_relative_position(node, graph)
          ref_id = node.constraints.relative_to
          ref_node = find_node(graph, ref_id)

          unless ref_node
            warn "Warning: Node '#{node.id}' references non-existent " \
                 "node '#{ref_id}' for relative positioning"
            return
          end

          offset = node.constraints.relative_offset
          return unless offset

          # Calculate and set new position
          node.x = ref_node.x + offset.x
          node.y = ref_node.y + offset.y
        end
      end
    end
  end
end
