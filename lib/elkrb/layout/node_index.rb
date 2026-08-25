# frozen_string_literal: true

require_relative "../errors"

module Elkrb
  module Layout
    # Resolves node and port ids to their owning node, for ONE hierarchy
    # level. Node ids and port ids share one namespace at a level; the
    # same id may legitimately repeat at a different level (build a
    # fresh index per level, never reused across `layout_flat` calls).
    #
    # `.build` is the entry point; construct every index through it.
    class NodeIndex
      # The edges of this level, in graph-then-children order.
      attr_reader :edges

      def self.build(graph)
        new(graph)
      end

      def node(id)
        @nodes_by_id[id]
      end

      def endpoint_nodes(ids)
        (ids || []).filter_map { |id| node(id) }
      end

      # The edges `child` declares that belong to THIS level. A
      # hierarchical child's `edges` address its own namespace --
      # `HierarchicalProcessor#create_child_graph` hands them to the
      # child's level, which is where their ids resolve. Ids are unique
      # only within a level, so reading them here aliases a nested
      # endpoint onto an unrelated node or port of this level.
      def edges_on(child)
        return [] if child.hierarchical?

        child.edges || []
      end

      private

      def initialize(graph)
        @nodes_by_id = {}
        children = graph.children || []
        children.each { |child| index_node(child) }
        @edges = ((graph.edges || []) +
          children.flat_map { |child| edges_on(child) }).freeze
      end

      def index_node(node)
        add(node.id, node, "node")
        node.ports&.each { |port| add(port.id, node, "port") }
      end

      def add(id, node, kind)
        raise Elkrb::ValidationError, "#{kind} without id" if id.nil?

        if @nodes_by_id.key?(id)
          raise Elkrb::ValidationError, "duplicate id: #{id}"
        end

        @nodes_by_id[id] = node
      end
    end
  end
end
