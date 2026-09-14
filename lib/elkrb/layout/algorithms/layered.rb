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
      # 1. Cycle breaking - find the back edges, WITHOUT making the graph
      #    acyclic. The caller's edges are handed back exactly as written;
      #    the reversal is a private orientation the next phase borrows.
      # 2. Layer assignment - assign nodes to horizontal layers, reading
      #    each back edge in its reversed direction
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

          # Phase 1: Find the back edges
          cycle_breaker = Layered::CycleBreaker.new(graph, index)
          reversed_edges = cycle_breaker.break_cycles

          # Phase 2: Assign layers
          layer_assigner = Layered::LayerAssigner.new(
            graph, index, reversed_edges
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
          return if anonymous?(edge)

          if seen_ids.key?(edge.id)
            raise Elkrb::ValidationError,
                  "duplicate edge id: #{edge_label(edge)}"
          end

          seen_ids[edge.id] = true
        end

        # An id is optional on an edge. An edge without one is ANONYMOUS: it
        # carries no handle, so there is nothing for it to be a duplicate of
        # and uniqueness cannot apply to it. Only edges that actually carry
        # an id are checked.
        #
        # `""` counts as no id, and this is the ONE place that decides it --
        # `edge_label` asks the same predicate, so the validator and the
        # message can never disagree about which edges have a name. They did
        # disagree once, in the other direction: nil and "" were two separate
        # keys to the validator and one name, "(none)", to the reader.
        #
        # Anonymous edges are free to repeat because nothing downstream keys
        # on an edge id any more. CycleBreaker hands LayerAssigner the edge
        # OBJECTS it reversed, compared by identity. While it handed over
        # ids, every anonymous edge shared one handle, and this validator
        # refused the second anonymous edge to cover that -- which rejected
        # `a -> b, b -> c` written without ids, a graph v2 lays out.
        def anonymous?(edge)
          edge.id.to_s.empty?
        end

        def validate_simple_edge!(edge)
          sources = edge.sources || []
          targets = edge.targets || []

          raise_missing_endpoint!(edge) if missing_endpoint?(sources, targets)

          return if sources.length == 1 && targets.length == 1

          raise_hyperedge!(edge)
        end

        def missing_endpoint?(sources, targets)
          [sources, targets].any? do |endpoints|
            endpoints.empty? || !endpoint_present?(endpoints.first)
          end
        end

        def endpoint_present?(endpoint)
          !endpoint.nil?
        end

        # An edge id is optional in ELK, so every message below could read
        # "(edge )" with nothing after it. The endpoints are the fallback
        # handle -- not because an edge always has them (the very next
        # method is raised when it does not, and `endpoint_list` answers
        # "(no endpoints)" for that case), but because they are the only
        # other thing a reader can use to find the edge in their input.
        # Keep the three messages using one helper: fixing only some of
        # them makes the rest look deliberate.
        def edge_label(edge)
          # `""` is truthy in Ruby, so a plain `if edge.id` here puts the
          # empty message straight back. `anonymous?` is the single
          # definition of "no id"; the uniqueness validator asks it too.
          return edge.id unless anonymous?(edge)

          "(none), #{endpoint_list(edge.sources)} -> " \
            "#{endpoint_list(edge.targets)}"
        end

        def endpoint_list(endpoints)
          named = (endpoints || []).compact
          return "(no endpoints)" if named.empty?

          named.map(&:inspect).join(", ")
        end

        def raise_missing_endpoint!(edge)
          raise Elkrb::UnsupportedConfigurationException.new(
            "layered requires non-empty edge endpoints " \
            "(edge #{edge_label(edge)})",
            option: "edge",
            value: edge.id,
          )
        end

        def raise_hyperedge!(edge)
          raise Elkrb::UnsupportedConfigurationException.new(
            "layered does not support hyperedges " \
            "(edge #{edge_label(edge)})",
            option: "edge",
            value: edge.id,
          )
        end
      end
    end
  end
end
