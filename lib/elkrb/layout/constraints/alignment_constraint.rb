# frozen_string_literal: true

require_relative "base_constraint"

module Elkrb
  module Layout
    module Constraints
      # Alignment constraint
      #
      # Aligns nodes horizontally (same y) or vertically (same x) based on
      # their align_group setting.
      #
      # @example Horizontal alignment
      #   db1.constraints = NodeConstraints.new(
      #     align_group: "databases",
      #     align_direction: "horizontal"
      #   )
      #   db2.constraints = NodeConstraints.new(
      #     align_group: "databases",
      #     align_direction: "horizontal"
      #   )
      #   # Both nodes will have same y coordinate
      #
      # @example Vertical alignment
      #   ui1.constraints = NodeConstraints.new(
      #     align_group: "ui_layer",
      #     align_direction: "vertical"
      #   )
      #   ui2.constraints = NodeConstraints.new(
      #     align_group: "ui_layer",
      #     align_direction: "vertical"
      #   )
      #   # Both nodes will have same x coordinate
      #
      # Members that the average would stack on top of each other are moved
      # apart along the other axis, in their current order.
      class AlignmentConstraint < BaseConstraint
        # @param spacing [Numeric] minimum gap kept between group members
        #   along the axis that is not aligned
        def initialize(spacing: 0.0)
          super()
          @spacing = spacing
        end

        # Apply alignment constraint
        #
        # Groups nodes by align_group and aligns them according to
        # align_direction.
        #
        # @param graph [Graph::Graph] The graph
        # @return [Graph::Graph] The modified graph
        def apply(graph)
          # Group nodes by alignment group and direction
          alignment_groups = group_by_alignment(all_nodes(graph))

          # Apply alignment to each group
          alignment_groups.each do |key, nodes|
            next if nodes.length < 2

            _group_name, direction = key
            align_nodes(nodes, direction)
          end

          graph
        end

        # Validate alignment constraints
        #
        # Checks that aligned nodes have matching coordinates.
        #
        # @param graph [Graph::Graph] The graph to validate
        # @return [Array<String>] List of validation errors
        def validate(graph)
          errors = []
          alignment_groups = group_by_alignment(all_nodes(graph))

          alignment_groups.each do |key, nodes|
            next if nodes.length < 2

            group_name, direction = key
            errors.concat(validate_group_alignment(nodes, group_name,
                                                   direction))
          end

          errors
        end

        private

        # Group nodes by align_group and align_direction
        def group_by_alignment(nodes)
          nodes_with_alignment = nodes.select do |node|
            node.constraints&.align_group &&
              node.constraints.align_direction
          end

          nodes_with_alignment.group_by do |node|
            [node.constraints.align_group,
             node.constraints.align_direction]
          end
        end

        # Align nodes in a group
        def align_nodes(nodes, direction)
          return if nodes.empty?

          case direction
          when Graph::NodeConstraints::HORIZONTAL
            align_horizontally(nodes)
          when Graph::NodeConstraints::VERTICAL
            align_vertically(nodes)
          end
        end

        # Align nodes horizontally (same y), then space them along x
        def align_horizontally(nodes)
          placed = align_to_average(nodes, :y)
          space_apart(placed, :x, :width)
        end

        # Align nodes vertically (same x), then space them along y
        def align_vertically(nodes)
          placed = align_to_average(nodes, :x)
          space_apart(placed, :y, :height)
        end

        # Moves every node that has a coordinate on +axis+ to the average of
        # them. A node without one is left alone: it has nothing to align.
        #
        # @return [Array<Graph::Node>] the nodes that were aligned
        def align_to_average(nodes, axis)
          placed = nodes.reject { |node| node.public_send(axis).nil? }
          return placed if placed.empty?

          average = placed.sum { |node| node.public_send(axis) } /
            placed.length.to_f
          placed.each { |node| node.public_send(:"#{axis}=", average) }
        end

        # Pushes members apart along +axis+ so none overlaps the one before
        # it. Order is the nodes' current order along the axis; ties keep
        # the order they were given in.
        def space_apart(nodes, axis, size)
          ordered = nodes.each_with_index.sort_by do |node, index|
            [coordinate(node, axis), index]
          end.map(&:first)

          ordered.each_cons(2) do |previous, node|
            floor = coordinate(previous, axis) +
              coordinate(previous, size) + @spacing
            next unless coordinate(node, axis) < floor

            node.public_send(:"#{axis}=", floor)
          end
        end

        # A coordinate or size that has not been set counts as 0.
        def coordinate(node, attribute)
          node.public_send(attribute) || 0.0
        end

        # Validate group alignment
        def validate_group_alignment(nodes, group_name, direction)
          errors = []
          return errors if nodes.empty?

          case direction
          when Graph::NodeConstraints::HORIZONTAL
            y_values = nodes.filter_map(&:y).uniq
            if y_values.length > 1
              errors << "Alignment group '#{group_name}' (horizontal) " \
                        "has nodes with different y coordinates: #{y_values}"
            end
          when Graph::NodeConstraints::VERTICAL
            x_values = nodes.filter_map(&:x).uniq
            if x_values.length > 1
              errors << "Alignment group '#{group_name}' (vertical) " \
                        "has nodes with different x coordinates: #{x_values}"
            end
          end

          errors
        end
      end
    end
  end
end
