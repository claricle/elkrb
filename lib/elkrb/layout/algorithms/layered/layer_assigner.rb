# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Assigns nodes to layers in the graph
        #
        # This is the second phase of the Sugiyama framework.
        # Uses longest path layering to create a balanced layout.
        class LayerAssigner
          attr_reader :layers

          def initialize(graph, index)
            @graph = graph
            @index = index
            @layers = []
            @node_layers = {}
          end

          def assign_layers
            return [] unless @graph.children

            # Calculate layer for each node
            @graph.children.each do |node|
              calculate_layer(node)
            end

            # Group nodes by layer
            max_layer = @node_layers.values.max || 0
            @layers = Array.new(max_layer + 1) { [] }

            @node_layers.each do |node_id, layer|
              node = @index.node(node_id)
              @layers[layer] << node if node
            end

            @layers
          end

          def get_layer(node_id)
            @node_layers[node_id]
          end

          private

          def calculate_layer(node)
            return @node_layers[node.id] if @node_layers.key?(node.id)

            # Find incoming edges
            incoming = get_incoming_edges(node)

            if incoming.empty?
              # Root node - assign to layer 0
              @node_layers[node.id] = 0
            else
              # Assign to one layer below the maximum of predecessors
              max_pred_layer = incoming.filter_map do |edge|
                source_id = edge.sources.first
                next 0 unless source_id

                source = @index.node(source_id)
                next 0 unless source

                calculate_layer(source)
              end.max || 0

              @node_layers[node.id] = max_pred_layer + 1
            end

            @node_layers[node.id]
          end

          def get_incoming_edges(node)
            edges = []

            # Get all edges that target this node
            @graph.edges&.each do |edge|
              next if self_loop_edge?(edge)

              edges << edge if @index.endpoint_nodes(edge.targets).include?(node)
            end

            # Also check edges from other nodes
            @graph.children&.each do |other_node|
              next unless other_node.edges

              other_node.edges.each do |edge|
                next if self_loop_edge?(edge)

                edges << edge if @index.endpoint_nodes(edge.targets).include?(node)
              end
            end

            edges
          end

          # Compares resolved OWNERS, not raw ids: two different port ids
          # on the same node (e.g. "p1" -> "p2") are still a self-loop.
          # Comparing raw ids here would leave a port-to-port self-loop
          # looking like real incoming traffic once get_incoming_edges
          # above resolves targets through the index, and
          # calculate_layer would recurse on the same node forever
          # before it is memoized (SystemStackError).
          #
          # Checks EVERY resolved source/target, not just the first pair:
          # comparing only the first source against the first target
          # would misclassify a hyperedge whose first target happens to
          # be the source's own port (e.g. a -> [a's port, b]) as an
          # entire self-loop, hiding the real a -> b edge from
          # get_incoming_edges. S8 will reject hyperedges before phase 1
          # runs; until then this keeps the check correct.
          def self_loop_edge?(edge)
            sources = @index.endpoint_nodes(edge.sources)
            targets = @index.endpoint_nodes(edge.targets)

            return false if sources.empty? || targets.empty?

            (sources + targets).uniq.size == 1
          end
        end
      end
    end
  end
end
