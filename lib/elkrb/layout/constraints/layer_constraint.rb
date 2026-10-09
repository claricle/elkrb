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
        # Nothing to do before layout: the layered algorithm reads
        # `constraints.layer` itself when it assigns layers.
        #
        # @param graph [Graph::Graph] The graph
        # @return [Graph::Graph] The graph, unchanged
        def apply(graph)
          graph
        end

        # Validate layer constraints
        #
        # A layer index below 0 names no layer, so the layered algorithm
        # places such a node in layer 0.
        #
        # @param graph [Graph::Graph] The graph to validate
        # @return [Array<String>] List of validation errors
        def validate(graph)
          all_nodes(graph).filter_map do |node|
            layer = node.constraints&.layer
            next unless layer&.negative?

            "Node '#{node.id}' constrained to layer #{layer}, " \
              "which does not exist; layers start at 0"
          end
        end
      end
    end
  end
end
