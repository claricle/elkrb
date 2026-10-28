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
        DEFAULT_SPACING = 80.0
        MIN_DISTANCE = 0.01
        PERCENTAGE_BASE = 100.0

        # The registry owns these; the constants stay for existing callers.
        DEFAULT_ITERATIONS = Options::Registry.default("elk.force.iterations")
        DEFAULT_REPULSION = Options::Registry.default("elk.force.repulsion")
        DEFAULT_TEMPERATURE = Options::Registry.default("elk.force.temperature")

        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          iterations = option("elk.force.iterations", default: 300)
          spacing = option("elk.spacing.nodeNode", default: DEFAULT_SPACING)
          area = layout_area(graph.children, spacing)
          side = Math.sqrt(area)
          ideal_length = [
            Math.sqrt(area / graph.children.length),
            MIN_DISTANCE,
          ].max

          initialize_positions(graph, side)
          resolved_edges = resolve_edge_positions(graph)
          repulsion = repulsion_scale
          initial_temperature = side / 10.0 * temperature_scale

          iterations.times do |i|
            temperature = initial_temperature * (1.0 - (i.to_f / iterations))
            apply_forces(graph.children, resolved_edges, ideal_length,
                         repulsion, temperature)
          end

          apply_padding(graph)
          graph
        end

        private

        def layout_area(nodes, spacing)
          nodes.sum do |node|
            ((node.width || 0.0) + spacing) *
              ((node.height || 0.0) + spacing)
          end
        end

        def initialize_positions(graph, side)
          graph.children.each do |node|
            unless node.x && node.y
              node.x = rng.rand * side
              node.y = rng.rand * side
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

            source_position = positions[source_node.id]
            target_position = positions[target_node.id]
            next unless source_position && target_position
            next if source_position == target_position

            [source_position, target_position]
          end
        end

        def temperature_scale
          option("elk.force.temperature", default: DEFAULT_TEMPERATURE).to_f /
            DEFAULT_TEMPERATURE
        end

        def repulsion_scale
          option("elk.force.repulsion", default: DEFAULT_REPULSION).to_f /
            PERCENTAGE_BASE
        end

        def apply_forces(nodes, resolved_edges, ideal_length, repulsion,
                         temperature)
          forces = calculate_forces(nodes, resolved_edges, ideal_length,
                                    repulsion)

          nodes.each_with_index do |node, i|
            force_x, force_y = forces[i]
            magnitude = Math.hypot(force_x, force_y)

            next if magnitude.zero?

            displacement = [magnitude, temperature].min
            node.x += (force_x / magnitude) * displacement
            node.y += (force_y / magnitude) * displacement
          end
        end

        def calculate_forces(nodes, resolved_edges, ideal_length, repulsion)
          forces = Array.new(nodes.length) { [0.0, 0.0] }

          nodes.each_index do |i|
            ((i + 1)...nodes.length).each do |j|
              apply_repulsive_force(nodes[i], nodes[j], forces[i], forces[j],
                                    ideal_length, repulsion)
            end
          end

          resolved_edges.each do |source_idx, target_idx|
            apply_attractive_force(
              nodes[source_idx],
              nodes[target_idx],
              forces[source_idx],
              forces[target_idx],
              ideal_length,
            )
          end

          forces
        end

        def apply_repulsive_force(node1, node2, force1, force2, ideal_length,
                                  repulsion)
          direction_x, direction_y, distance = border_vector(node1, node2)
          magnitude = repulsion * (ideal_length**2) / distance
          apply_force_pair(force1, force2, direction_x, direction_y,
                           -magnitude)
        end

        def apply_attractive_force(node1, node2, force1, force2, ideal_length)
          direction_x, direction_y, distance = border_vector(node1, node2)
          magnitude = (distance**2) / ideal_length
          apply_force_pair(force1, force2, direction_x, direction_y, magnitude)
        end

        def border_vector(node1, node2)
          dx = center_x(node2) - center_x(node1)
          dy = center_y(node2) - center_y(node1)

          if dx.zero? && dy.zero?
            angle = rng.rand * 2.0 * Math::PI
            dx = Math.cos(angle) * MIN_DISTANCE
            dy = Math.sin(angle) * MIN_DISTANCE
          end

          center_distance = Math.hypot(dx, dy)
          direction_x = dx / center_distance
          direction_y = dy / center_distance
          horizontal_gap = [dx.abs - half_widths(node1, node2), 0.0].max
          vertical_gap = [dy.abs - half_heights(node1, node2), 0.0].max
          distance = [
            Math.hypot(horizontal_gap, vertical_gap),
            MIN_DISTANCE,
          ].max

          [direction_x, direction_y, distance]
        end

        def apply_force_pair(force1, force2, direction_x, direction_y,
                             magnitude)
          force_x = direction_x * magnitude
          force_y = direction_y * magnitude
          force1[0] += force_x
          force1[1] += force_y
          force2[0] -= force_x
          force2[1] -= force_y
        end

        def center_x(node)
          node.x + ((node.width || 0.0) / 2.0)
        end

        def center_y(node)
          node.y + ((node.height || 0.0) / 2.0)
        end

        def half_widths(node1, node2)
          ((node1.width || 0.0) + (node2.width || 0.0)) / 2.0
        end

        def half_heights(node1, node2)
          ((node1.height || 0.0) + (node2.height || 0.0)) / 2.0
        end

        # ELK's force layout uses 50px padding even though the shared core
        # registry default is 12px. An explicit graph/call option still wins.
        def padding
          option(
            "elk.padding",
            default: { left: 50.0, top: 50.0, right: 50.0, bottom: 50.0 },
          ).to_h
        end
      end
    end
  end
end
