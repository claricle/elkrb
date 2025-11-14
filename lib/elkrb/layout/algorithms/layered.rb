# frozen_string_literal: true

require_relative "base_algorithm"
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
        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          # Phase 1: Break cycles
          cycle_breaker = Layered::CycleBreaker.new(graph)
          cycle_breaker.break_cycles

          # Phase 2: Assign layers
          layer_assigner = Layered::LayerAssigner.new(graph)
          layers = layer_assigner.assign_layers

          # Phase 3: Place nodes
          node_placer = Layered::NodePlacer.new(graph, layers, @options)
          node_placer.place_nodes

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end
      end
    end
  end
end
