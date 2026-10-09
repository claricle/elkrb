# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../node_index"
require_relative "layered/cycle_breaker"
require_relative "layered/crossing_minimizer"
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
      # 3. Crossing minimization - reorder nodes within assigned layers
      # 4. Node placement - position nodes within layers
      #
      # Ideal for:
      # - UML class diagrams
      # - Call graphs
      # - Data flow diagrams
      # - Organization charts
      # - Any directed acyclic graph
      #
      # The three bang validators below (raise_hyperedge!,
      # raise_missing_endpoint!, validate_simple_edge!) are argument
      # validators, not the dangerous/safe pair MissingSafeMethod expects --
      # same reasoning as GraphvizWrapper's own exemption, see that file's
      # comment. No nested class here to inherit this and need its own reset.
      # rubocop:disable Layout/LineLength
      # :reek:MissingSafeMethod { exclude: [ raise_hyperedge!, raise_missing_endpoint!, validate_simple_edge! ] }
      # rubocop:enable Layout/LineLength
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

          layers = assign_layers(graph, index)

          # Phase 3: Minimize crossings within the assigned layers
          layers = minimize_crossings(graph, layers, index)
          @dummy_slots = dummy_slots(layers)

          # Phase 4: Place nodes
          place_nodes(graph, layers, index)

          # Apply padding and set graph dimensions
          apply_padding_with_dummies(graph)

          graph
        end

        private

        def assign_layers(graph, index)
          # Phase 1: Find the back edges
          reversed_edges = Layered::CycleBreaker.new(graph, index).break_cycles

          # Phase 2: Assign layers and insert long-edge dummy slots
          Layered::LayerAssigner.new(
            graph, index, reversed_edges
          ).assign_layers
        end

        def apply_edge_routing(graph)
          super
          add_long_edge_bends(graph)
        end

        def apply_padding_with_dummies(graph)
          shift_x, shift_y = padding_shift(graph)
          shift_dummy_slots(shift_x, shift_y)
        end

        def padding_shift(graph)
          first = graph.children.first
          before = first && [first.x, first.y]
          apply_padding(graph)
          return [0.0, 0.0] unless before

          [first.x - before[0], first.y - before[1]]
        end

        def shift_dummy_slots(shift_x, shift_y)
          @dummy_slots.each do |slot|
            slot.x += shift_x
            slot.y += shift_y
          end
        end

        def dummy_slots(layers)
          layers.flatten.select { |item| item.respond_to?(:dummy?) }
        end

        def add_long_edge_bends(graph)
          slots_by_edge = {}.compare_by_identity
          @dummy_slots.to_a.each do |slot|
            (slots_by_edge[slot.edge] ||= []) << slot
          end
          graph.edges.to_a.each do |edge|
            add_edge_dummy_bends(edge, slots_by_edge[edge])
          end
        end

        def add_edge_dummy_bends(edge, slots)
          return if slots.nil? || slots.empty? || edge.sections.to_a.empty?

          section = edge.sections.first
          section.bend_points = slots.sort_by do |slot|
            squared_distance(section.start_point, slot)
          end.map { |slot| dummy_center(slot) }
        end

        def squared_distance(point, slot)
          ((slot.x + (slot.width / 2.0) - point.x)**2) +
            ((slot.y + (slot.height / 2.0) - point.y)**2)
        end

        def dummy_center(slot)
          Geometry::Point.new(
            x: slot.x + (slot.width / 2.0),
            y: slot.y + (slot.height / 2.0),
          )
        end

        def minimize_crossings(graph, layers, index)
          Layered::CrossingMinimizer.new(
            graph, layers, index, resolver
          ).minimize
        end

        def place_nodes(graph, layers, index)
          direction = option("elk.direction")
          direction = "RIGHT" if direction == "UNDEFINED"

          placer = Layered::NodePlacer.new(
            graph, layers,
            direction: direction,
            layer_spacing: option("elk.layered.spacing.nodeNodeBetweenLayers"),
            node_spacing: node_spacing
          )
          placer.index = index
          placer.place_nodes
        end

        def validate_edges(index)
          index.edges.each do |edge|
            validate_simple_edge!(edge)
          end
        end

        # An id is optional on an edge. An edge without one is ANONYMOUS: it
        # carries no handle, so `edge_label` falls back to its endpoints.
        # `""` counts as no id, and this is the ONE place that decides it.
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
          # definition of "no id".
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
