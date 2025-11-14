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

          def initialize(graph)
            @graph = graph
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
              node = @graph.find_node(node_id)
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

                source = @graph.find_node(source_id)
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
              edges << edge if edge.targets&.include?(node.id)
            end

            # Also check edges from other nodes
            @graph.children&.each do |other_node|
              next unless other_node.edges

              other_node.edges.each do |edge|
                edges << edge if edge.targets&.include?(node.id)
              end
            end

            edges
          end
        end
      end
    end
  end
end
