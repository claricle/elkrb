# frozen_string_literal: true

module Elkrb
  module Layout
    # Resolves node and port ids to their owning node, for ONE hierarchy
    # level. Node ids and port ids share one namespace at a level; the
    # same id may legitimately repeat at a different level (build a
    # fresh index per level, never reused across `layout_flat` calls).
    class NodeIndex
      def self.build(graph)
        new(graph)
      end

      def node(id)
        @nodes_by_id[id]
      end

      def endpoint_nodes(ids)
        (ids || []).filter_map { |id| node(id) }
      end

      private

      def initialize(graph)
        @nodes_by_id = {}
        (graph.children || []).each { |child| index_node(child) }
      end

      def index_node(node)
        add(node.id, node)
        node.ports&.each { |port| add(port.id, node) }
      end

      def add(id, node)
        if @nodes_by_id.key?(id)
          raise Elkrb::ValidationError, "duplicate id: #{id}"
        end

        @nodes_by_id[id] = node
      end
    end
  end
end
