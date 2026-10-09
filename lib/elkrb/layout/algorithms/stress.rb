# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../node_index"

module Elkrb
  module Layout
    module Algorithms
      # Stress minimization layout algorithm
      #
      # Quality-focused layout that minimizes stress by optimizing
      # the placement of nodes to match ideal distances.
      # Produces aesthetically pleasing layouts with good edge lengths.
      #
      # Ideal for:
      # - High-quality graph visualization
      # - Research diagrams
      # - Publication-ready layouts
      # - Small to medium-sized graphs
      class Stress < BaseAlgorithm
        # The registry owns these; the constants stay for existing callers.
        DEFAULT_ITERATIONS =
          Options::Registry.default("elk.stress.iterationLimit")
        DEFAULT_EPSILON = Options::Registry.default("elk.stress.epsilon")
        ITERATION_LIMIT = "elk.stress.iterationLimit"

        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          # Get configuration
          iterations = call_iterations
          epsilon = option("elk.stress.epsilon")

          # Initialize positions
          initialize_positions(graph)

          # Calculate shortest path distances
          distances = calculate_distances(graph)

          # Iteratively minimize stress
          xpos = graph.children.map(&:x)
          ypos = graph.children.map(&:y)
          weights = pair_weights(distances)
          reachable = reachable_pairs(distances)
          old_stress = calculate_stress(xpos, ypos, distances, reachable)
          iterations.times do |_i|
            optimize_positions(xpos, ypos, distances, weights, reachable)
            new_stress = calculate_stress(xpos, ypos, distances, reachable)

            # Stop if converged
            break if (old_stress - new_stress).abs < epsilon

            old_stress = new_stress
          end

          graph.children.each_with_index do |node, i|
            node.x = xpos[i]
            node.y = ypos[i]
          end

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end

        private

        # The registry reads "iterations" as force's elk.force.iterations, so
        # the resolver alone would let force's option change a stress layout.
        # The call's own "iterations" key still wins, validated as stress's
        # option; otherwise elk.stress.iterationLimit is resolved.
        def call_iterations
          call = options.is_a?(Hash) ? options : {}
          given = call.fetch("iterations", nil) || call.fetch(:iterations, nil)
          unless given
            return option(ITERATION_LIMIT, default: DEFAULT_ITERATIONS)
          end

          Options::Resolver.new(ITERATION_LIMIT => given).get(ITERATION_LIMIT)
        end

        def initialize_positions(graph)
          # Use circular initial layout
          n = graph.children.length
          radius = n * option("elk.stress.desiredEdgeLength").to_f

          graph.children.each_with_index do |node, i|
            angle = 2 * Math::PI * i / n
            node.x = (radius * Math.cos(angle)) + radius
            node.y = (radius * Math.sin(angle)) + radius
          end
        end

        def calculate_distances(graph)
          n = graph.children.length
          adjacency = Array.new(n) { [] }

          # Build adjacency from endpoints resolved to their owning nodes.
          index = NodeIndex.build(graph)
          positions = graph.children.each_with_index.to_h do |node, i|
            [node.id, i]
          end

          index.edges.each do |edge|
            source_id = edge.sources&.first
            target_id = edge.targets&.first
            next unless source_id && target_id

            source_node = index.node(source_id)
            target_node = index.node(target_id)
            next unless source_node && target_node

            i = positions[source_node.id]
            j = positions[target_node.id]
            next unless i && j

            adjacency[i] << j
            adjacency[j] << i
          end

          edge_length = option("elk.stress.desiredEdgeLength").to_f
          Array.new(n) do |source|
            bfs_distances(adjacency, source, edge_length)
          end
        end

        def bfs_distances(adjacency, source, edge_length)
          distances = Array.new(adjacency.length, Float::INFINITY)
          distances[source] = 0.0
          queue = [source]
          cursor = 0

          while cursor < queue.length
            current = queue[cursor]
            cursor += 1

            adjacency[current].each do |neighbor|
              next unless distances[neighbor] == Float::INFINITY

              distances[neighbor] = distances[current] + edge_length
              queue << neighbor
            end
          end

          distances
        end

        # 1 / ideal^2 per pair, computed once instead of every iteration.
        def pair_weights(ideal_distances)
          ideal_distances.map do |row|
            row.map { |ideal| 1.0 / (ideal * ideal) }
          end
        end

        # For each node, the other nodes it has a finite ideal distance to.
        def reachable_pairs(ideal_distances)
          ideal_distances.each_with_index.map do |row, i|
            row.each_index.select { |j| j != i && row[j] != Float::INFINITY }
          end
        end

        # The loops below are plain whiles over precomputed index lists:
        # blocks here slow a 200-node layout down several times.
        def calculate_stress(xpos, ypos, ideal_distances, reachable)
          stress = 0.0

          i = 0
          n = xpos.length
          while i < n
            row = ideal_distances[i]
            node_x = xpos[i]
            node_y = ypos[i]
            others = reachable[i]
            k = 0
            count = others.length
            while k < count
              j = others[k]
              if j > i
                dx = xpos[j] - node_x
                dy = ypos[j] - node_y
                diff = Math.sqrt((dx * dx) + (dy * dy)) - row[j]
                stress += diff * diff
              end
              k += 1
            end
            i += 1
          end

          stress
        end

        # Updates xpos and ypos in place, one node at a time, so each node sees
        # the already-moved positions of the nodes before it.
        def optimize_positions(xpos, ypos, ideal_distances, weights, reachable)
          i = 0
          n = xpos.length
          while i < n
            sum_x, sum_y, sum_weight = pull_sums(
              [xpos, ypos], i, ideal_distances[i], weights[i], reachable[i]
            )
            if sum_weight.positive?
              xpos[i] = sum_x / sum_weight
              ypos[i] = sum_y / sum_weight
            end
            i += 1
          end
        end

        def pull_sums(coordinates, node, row, weight_row, others)
          xpos, ypos = coordinates
          node_x = xpos[node]
          node_y = ypos[node]
          sum_x = 0.0
          sum_y = 0.0
          sum_weight = 0.0

          k = 0
          count = others.length
          while k < count
            j = others[k]
            other_x = xpos[j]
            other_y = ypos[j]
            dx = other_x - node_x
            dy = other_y - node_y
            actual_dist = Math.sqrt((dx * dx) + (dy * dy))

            unless actual_dist.zero?
              weight = weight_row[j]
              ratio = row[j] / actual_dist

              sum_x += weight * (other_x - (ratio * dx))
              sum_y += weight * (other_y - (ratio * dy))
              sum_weight += weight
            end
            k += 1
          end

          [sum_x, sum_y, sum_weight]
        end
      end
    end
  end
end
