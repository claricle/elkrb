# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../node_index"
require_relative "layered/cycle_breaker"
require_relative "layered/layer_assigner"
require_relative "layered/node_placer"

module Elkrb
  module Layout
    module Algorithms
      # Layered (Sugiyama) layout algorithm
      #
      # The flagship algorithm for hierarchical graph layout.
      # Implements the Sugiyama framework in phases:
      # 1. Cycle breaking - make the graph acyclic
      # 2. Layer assignment - assign nodes to horizontal layers
      # 3. Node placement - position nodes within layers
      #
      # Ideal for:
      # - UML class diagrams
      # - Call graphs
      # - Data flow diagrams
      # - Organization charts
      # - Any directed acyclic graph
      class LayeredAlgorithm < BaseAlgorithm
        # BaseAlgorithm intentionally skips layout_flat when a deserialized
        # graph omits `children`. Validate that public entry point here so an
        # unsupported edge cannot silently pass through untouched.
        def layout(graph)
          validate_edges(NodeIndex.build(graph)) unless graph.children
          super
        end

        def layout_flat(graph, _options = {})
          index = NodeIndex.build(graph)
          validate_edges(index)
          return graph if graph.children.nil? || graph.children.empty?

          # Phase 1: Break cycles
          cycle_breaker = Layered::CycleBreaker.new(graph, index)
          reversed_edge_ids = cycle_breaker.break_cycles

          # Phase 2: Assign layers
          layer_assigner = Layered::LayerAssigner.new(
            graph, index, reversed_edge_ids
          )
          layers = layer_assigner.assign_layers

          # Phase 3: Place nodes
          node_placer = Layered::NodePlacer.new(graph, layers, @options)
          node_placer.place_nodes

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end

        private

        def validate_edges(index)
          seen_ids = {}

          index.edges.each do |edge|
            validate_unique_edge_id!(seen_ids, edge)
            validate_simple_edge!(edge)
          end
        end

        def validate_unique_edge_id!(seen_ids, edge)
          if seen_ids.key?(edge.id)
            raise Elkrb::ValidationError, "duplicate edge id: #{edge.id}"
          end

          seen_ids[edge.id] = true
        end

        def validate_simple_edge!(edge)
          return if (edge.sources || []).length == 1 &&
            (edge.targets || []).length == 1

          raise Elkrb::UnsupportedConfigurationException.new(
            "layered does not support hyperedges (edge #{edge.id})",
            option: "edge",
            value: edge.id,
          )
        end
      end
    end
  end
end
