# frozen_string_literal: true

module Elkrb
  module Layout
    module Constraints
      # Base class for all layout constraints
      #
      # Constraints modify node positions before or after layout to enforce
      # specific positioning rules. Each constraint type handles one specific
      # kind of positioning requirement.
      #
      # Subclasses must implement:
      # - apply(graph): Modify graph to enforce constraint
      # - validate(graph): Check if constraint is satisfied
      #
      # @abstract
      class BaseConstraint
        # Apply the constraint to the graph
        #
        # @param graph [Graph::Graph] The graph to apply constraint to
        # @return [Graph::Graph] The modified graph
        def apply(graph)
          raise NotImplementedError,
                "#{self.class} must implement #apply"
        end

        # Validate that the constraint is satisfied
        #
        # @param graph [Graph::Graph] The graph to validate
        # @return [Array<String>] List of validation errors (empty if valid)
        def validate(_graph)
          []
        end

        protected

        # Find node by ID in graph
        #
        # @param graph [Graph::Graph] The graph to search
        # @param node_id [String] The node ID to find
        # @return [Graph::Node, nil] The found node or nil
        def find_node(graph, node_id)
          return nil unless graph.children

          graph.children.find { |node| node.id == node_id }
        end

        # Get all nodes at this hierarchy level.
        #
        # @param graph [Graph::Graph] The graph
        # @return [Array<Graph::Node>] All nodes
        def all_nodes(graph)
          return [] unless graph.children

          graph.children
        end
      end
    end
  end
end
