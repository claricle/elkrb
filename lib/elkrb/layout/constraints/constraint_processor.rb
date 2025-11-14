# frozen_string_literal: true

require_relative "base_constraint"
require_relative "fixed_position_constraint"
require_relative "alignment_constraint"
require_relative "layer_constraint"
require_relative "relative_position_constraint"

module Elkrb
  module Layout
    module Constraints
      # Constraint processor
      #
      # Orchestrates the application and validation of all layout constraints.
      # Constraints are applied in a specific order to handle dependencies:
      # 1. Fixed position (locks nodes)
      # 2. Layer constraints (assigns layers)
      # 3. Relative position (depends on reference nodes)
      # 4. Alignment (adjusts positions)
      #
      # @example
      #   processor = ConstraintProcessor.new
      #   processor.apply_all(graph)  # Apply before layout
      #   # ... layout algorithm runs ...
      #   processor.validate_all(graph)  # Validate after layout
      class ConstraintProcessor
        # Pre-layout constraints (mark nodes for algorithm)
        PRE_LAYOUT_CONSTRAINTS = [
          FixedPositionConstraint,
          LayerConstraint,
        ].freeze

        # Post-layout constraints (enforce after algorithm runs)
        POST_LAYOUT_CONSTRAINTS = [
          RelativePositionConstraint,
          AlignmentConstraint,
        ].freeze

        def initialize
          @pre_constraints = PRE_LAYOUT_CONSTRAINTS.map(&:new)
          @post_constraints = POST_LAYOUT_CONSTRAINTS.map(&:new)
          @all_constraints = (@pre_constraints + @post_constraints)
        end

        # Apply pre-layout constraints
        #
        # These constraints mark nodes for special handling by algorithms.
        #
        # @param graph [Graph::Graph] The graph to constrain
        # @return [Graph::Graph] The constrained graph
        def apply_pre_layout(graph)
          return graph unless has_constraints?(graph)

          @pre_constraints.each do |constraint|
            constraint.apply(graph)
          end

          graph
        end

        # Enforce post-layout constraints
        #
        # These constraints adjust positions after layout completes.
        # Also restores fixed positions that may have been moved.
        #
        # @param graph [Graph::Graph] The graph to constrain
        # @return [Graph::Graph] The constrained graph
        def enforce_post_layout(graph)
          return graph unless has_constraints?(graph)

          # First restore any fixed positions
          fixed_constraint = @pre_constraints.find do |c|
            c.is_a?(FixedPositionConstraint)
          end
          fixed_constraint&.restore_fixed_positions(graph)

          # Then apply post-layout constraints
          @post_constraints.each do |constraint|
            constraint.apply(graph)
          end

          graph
        end

        # Apply all constraints (legacy method)
        #
        # @deprecated Use apply_pre_layout and enforce_post_layout instead
        # @param graph [Graph::Graph] The graph to constrain
        # @return [Graph::Graph] The constrained graph
        def apply_all(graph)
          apply_pre_layout(graph)
          enforce_post_layout(graph)
        end

        # Validate all constraints after layout
        #
        # Checks that layout algorithm respected all constraints.
        #
        # @param graph [Graph::Graph] The graph to validate
        # @return [Array<String>] List of validation errors
        def validate_all(graph)
          return [] unless has_constraints?(graph)

          @all_constraints.flat_map do |constraint|
            constraint.validate(graph)
          end
        end

        # Check if graph has any constraints
        #
        # @param graph [Graph::Graph] The graph to check
        # @return [Boolean] True if any node has constraints
        def has_constraints?(graph)
          return false unless graph.children

          graph.children.any? do |node|
            has_constraints_recursive?(node)
          end
        end

        private

        # Check if node or its children have constraints
        def has_constraints_recursive?(node)
          return true if node.constraints

          return false unless node.children

          node.children.any? { |child| has_constraints_recursive?(child) }
        end
      end
    end
  end
end
