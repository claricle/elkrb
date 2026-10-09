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
        # Positions nodes relative to their reference nodes, a node only
        # after the node it is relative to. Among nodes whose references are
        # settled, higher position_priority goes first, then input order.
        # Nodes on a relative_to cycle, and nodes whose reference is missing
        # or has no coordinates, are left where they are; #validate reports
        # them.
        #
        # @param graph [Graph::Graph] The graph
        # @return [Graph::Graph] The modified graph
        def apply(graph)
          resolution_order(graph).each do |node|
            position_relative(node, graph)
          end

          graph
        end

        # Validate relative position constraints
        #
        # Checks that reference nodes exist, that relative_to does not form a
        # cycle, and that positions are correct.
        #
        # @param graph [Graph::Graph] The graph to validate
        # @return [Array<String>] List of validation errors
        def validate(graph)
          cyclic = cyclic_nodes(graph)

          all_nodes(graph).flat_map do |node|
            next [] unless node.constraints&.relative_to

            if cyclic.any? { |member| member.equal?(node) }
              ["Node '#{node.id}' is on, or depends on, a relative_to cycle"]
            else
              check_relative_node(node, graph)
            end
          end
        end

        private

        def check_relative_node(node, graph)
          ref_id = node.constraints.relative_to
          ref_node = find_node(graph, ref_id)

          if ref_node.nil?
            return ["Node '#{node.id}' has relative_to constraint " \
                    "referencing '#{ref_id}' which doesn't exist"]
          end

          offset = node.constraints.relative_offset
          return [] unless offset

          unless coordinates?(node) && coordinates?(ref_node)
            return ["Node '#{node.id}' relative position cannot be checked: " \
                    "'#{node.id}' or '#{ref_id}' has no coordinates"]
          end

          expected_x = ref_node.x + offset.x
          expected_y = ref_node.y + offset.y
          return [] if within_tolerance?(node, expected_x, expected_y)

          ["Node '#{node.id}' relative position incorrect. " \
           "Expected (#{expected_x}, #{expected_y}), " \
           "got (#{node.x}, #{node.y})"]
        end

        def within_tolerance?(node, expected_x, expected_y)
          tolerance = 0.01
          (node.x - expected_x).abs <= tolerance &&
            (node.y - expected_y).abs <= tolerance
        end

        def coordinates?(node)
          !node.x.nil? && !node.y.nil?
        end

        # Apply relative position to a single node
        def position_relative(node, graph)
          ref_node = find_node(graph, node.constraints.relative_to)
          offset = node.constraints.relative_offset
          return unless ref_node && offset && coordinates?(ref_node)

          node.x = ref_node.x + offset.x
          node.y = ref_node.y + offset.y
        end

        # Nodes to position, each after the node it is relative to.
        def resolution_order(graph)
          pending = positioned_nodes(graph)
          order = []

          until pending.empty?
            ready = pending.select { |node| ready?(node, graph, pending) }
            break if ready.empty?

            node = ready.min_by do |candidate|
              [-(candidate.constraints.position_priority || 0),
               pending.index { |p| p.equal?(candidate) }]
            end
            pending.delete_if { |p| p.equal?(node) }
            order << node
          end

          order
        end

        # A node is ready when the node it is relative to is not itself
        # still waiting to be positioned.
        def ready?(node, graph, pending)
          ref_node = find_node(graph, node.constraints.relative_to)
          ref_node.nil? || pending.none? { |p| p.equal?(ref_node) }
        end

        def positioned_nodes(graph)
          all_nodes(graph).select do |node|
            node.constraints&.relative_to && node.constraints.relative_offset
          end
        end

        # Nodes that can never be ready because relative_to leads back to
        # them.
        def cyclic_nodes(graph)
          ordered = resolution_order(graph)
          positioned_nodes(graph).reject do |node|
            ordered.any? { |placed| placed.equal?(node) }
          end
        end
      end
    end
  end
end
