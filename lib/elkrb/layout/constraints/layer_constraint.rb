# frozen_string_literal: true

require_relative "base_constraint"

module Elkrb
  module Layout
    module Constraints
      # Layer constraint
      #
      # Forces nodes into specific layers for layered (Sugiyama) algorithm.
      # Primarily useful for hierarchical diagrams where certain nodes must
      # appear in specific tiers.
      #
      # @example Three-tier architecture
      #   frontend.constraints = NodeConstraints.new(layer: 0)   # Top
      #   backend.constraints = NodeConstraints.new(layer: 1)    # Middle
      #   database.constraints = NodeConstraints.new(layer: 2)   # Bottom
      #   # Enforces tier structure
      class LayerConstraint < BaseConstraint
        # Apply layer constraint
        #
        # Marks nodes with layer assignment that layered algorithm
        # must respect.
        #
        # @param graph [Graph::Graph] The graph
        # @return [Graph::Graph] The modified graph
        def apply(graph)
          all_nodes(graph).each do |node|
            next unless node.constraints&.layer

            # Mark node with its required layer
            node.properties ||= {}
            node.properties["_constraint_layer"] = node.constraints.layer
          end

          graph
        end

        # Validate layer constraints
        #
        # Checks that nodes assigned to layers are in correct layers.
        # Note: This validation only applies if the layered algorithm
        # was used and layer information is available.
        #
        # @param graph [Graph::Graph] The graph to validate
        # @return [Array<String>] List of validation errors
        def validate(graph)
          errors = []

          # Check if layer information is available
          # (only present if layered algorithm was used)
          all_nodes(graph).each do |node|
            next unless node.constraints&.layer
            next unless node.properties&.[]("_assigned_layer")

            expected_layer = node.constraints.layer
            actual_layer = node.properties["_assigned_layer"]

            if expected_layer != actual_layer
              errors << "Node '#{node.id}' constrained to layer " \
                        "#{expected_layer} but assigned to layer " \
                        "#{actual_layer}"
            end
          end

          errors
        end
      end
    end
  end
end
