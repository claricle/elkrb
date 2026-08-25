# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../node_index"

module Elkrb
  module Layout
    module Algorithms
      # Force-directed layout algorithm
      #
      # Creates organic, symmetric layouts using force simulation.
      # Nodes repel each other while edges act as springs pulling
      # connected nodes together.
      #
      # Ideal for:
      # - Network diagrams
      # - Social graphs
      # - Mind maps
      # - General undirected graphs
      class Force < BaseAlgorithm
        DEFAULT_ITERATIONS = 300
        DEFAULT_REPULSION = 5.0
        DEFAULT_TEMPERATURE = 0.001

        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          # Get configuration
          iterations = option("iterations", DEFAULT_ITERATIONS).to_i
          repulsion = option("repulsion", DEFAULT_REPULSION).to_f
          temperature = option("temperature", DEFAULT_TEMPERATURE).to_f

          # Initialize positions randomly if not set
          initialize_positions(graph)

          # Resolve edge endpoints to force-array positions once, before
          # the iteration loop (not per edge per iteration)
          resolved_edges = resolve_edge_positions(graph)

          # Run force simulation
          iterations.times do |i|
            apply_forces(graph, resolved_edges, repulsion, temperature, i,
                         iterations)
          end

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end

        private

        def initialize_positions(graph)
          # Calculate approximate area needed
          total_area = graph.children.sum do |n|
            ((n.width || 0.0) + 20) * ((n.height || 0.0) + 20)
          end
          side = Math.sqrt(total_area)

          graph.children.each do |node|
            # Set random position if not already set
            unless node.x && node.y
              node.x = rand * side
              node.y = rand * side
            end
          end
        end

        # Resolves each edge's source/target ids (which may be port ids)
        # to their owning node's position in graph.children, once, so
        # the iteration loop below never re-scans ids per edge.
        def resolve_edge_positions(graph)
          index = NodeIndex.build(graph)
          positions = graph.children.each_with_index.to_h { |n, i| [n.id, i] }

          index.edges.filter_map do |edge|
            source_id = edge.sources&.first
            target_id = edge.targets&.first
            next unless source_id && target_id

            source_node = index.node(source_id)
            target_node = index.node(target_id)
            next unless source_node && target_node

            [positions[source_node.id], positions[target_node.id]]
          end
        end

        def apply_forces(graph, resolved_edges, repulsion, temperature,
                         iteration, max_iterations)
          # Calculate temperature decay
          temp = temperature * (1.0 - (iteration.to_f / max_iterations))

          # Calculate forces for each node
          forces = calculate_forces(graph, resolved_edges, repulsion)

          # Apply forces with temperature
          graph.children.each_with_index do |node, i|
            force = forces[i]
            magnitude = Math.sqrt((force[:x]**2) + (force[:y]**2))

            next if magnitude.zero?

            # Apply displacement with temperature
            displacement = [magnitude, temp].min
            node.x += (force[:x] / magnitude) * displacement
            node.y += (force[:y] / magnitude) * displacement
          end
        end

        def calculate_forces(graph, resolved_edges, repulsion)
          forces = graph.children.map { { x: 0.0, y: 0.0 } }

          # Repulsive forces between all pairs
          graph.children.each_with_index do |node1, i|
            graph.children.each_with_index do |node2, j|
              next if i >= j

              apply_repulsive_force(node1, node2, forces[i], forces[j],
                                    repulsion)
            end
          end

          # Attractive forces for edges
          resolved_edges.each do |source_idx, target_idx|
            apply_attractive_force(
              graph.children[source_idx],
              graph.children[target_idx],
              forces[source_idx],
              forces[target_idx],
            )
          end

          forces
        end

        def apply_repulsive_force(node1, node2, force1, force2, repulsion)
          dx = node2.x - node1.x
          dy = node2.y - node1.y
          distance_sq = (dx**2) + (dy**2)

          # Avoid division by zero
          return if distance_sq < 0.01

          # Repulsive force inversely proportional to distance
          force = repulsion / distance_sq
          force1[:x] -= (dx / Math.sqrt(distance_sq)) * force
          force1[:y] -= (dy / Math.sqrt(distance_sq)) * force
          force2[:x] += (dx / Math.sqrt(distance_sq)) * force
          force2[:y] += (dy / Math.sqrt(distance_sq)) * force
        end

        def apply_attractive_force(node1, node2, force1, force2)
          dx = node2.x - node1.x
          dy = node2.y - node1.y
          distance = Math.sqrt((dx**2) + (dy**2))

          return if distance.zero?

          # Spring force proportional to distance
          force = distance / 10.0
          force1[:x] += (dx / distance) * force
          force1[:y] += (dy / distance) * force
          force2[:x] -= (dx / distance) * force
          force2[:y] -= (dy / distance) * force
        end
      end
    end
  end
end
