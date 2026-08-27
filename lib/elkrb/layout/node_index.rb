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

      # Endpoints resolved for TOPOLOGY: a nested endpoint projects onto its
      # top-level ancestor instead of vanishing. Use this wherever an edge
      # contributes to layering or cycle detection; use #endpoint_nodes when
      # you want the literal nodes of this level and nothing else.
      def endpoint_owners(ids)
        (ids || []).filter_map { |id| owner(id) }.uniq
      end

      # The node AT THIS LEVEL that owns `id`: the node itself, the node
      # whose port it is, or the top-level ancestor of a nested descendant.
      #
      # This level always wins, so a nested id can never shadow one here --
      # that shadowing is what #node exists to keep out. But a graph-owned
      # cross-hierarchy edge (`c1 -> p2`, with c1 nested under p1) is
      # supported, and dropping its nested endpoint takes the edge out of
      # the topology entirely. Projecting c1 onto p1 keeps it.
      #
      # Use this for graph-owned edges only. Child-owned nested edges stay
      # excluded by #edges_on, which is a separate concern.
      def owner(id)
        node(id) || @owners_by_descendant_id[id]
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
        @owners_by_descendant_id = {}
        children.each { |child| index_descendants(child, child) }
      end

      # Maps every id below a top-level child back to that child. Only ids
      # this level does not already own are recorded, so #owner can never
      # let a descendant displace a node or port of this level.
      def index_descendants(node, owner)
        (node.children || []).each do |descendant|
          claim_descendant(descendant.id, owner)
          descendant.ports&.each { |port| claim_descendant(port.id, owner) }
          index_descendants(descendant, owner)
        end
      end

      def claim_descendant(id, owner)
        return if id.nil? || @nodes_by_id.key?(id) || @owners_by_descendant_id.key?(id)

        @owners_by_descendant_id[id] = owner
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
