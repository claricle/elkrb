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
          old_stress = calculate_stress(xpos, ypos, distances)
          iterations.times do |_i|
            optimize_positions(xpos, ypos, distances, weights)
            new_stress = calculate_stress(xpos, ypos, distances)

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

        def calculate_stress(xpos, ypos, ideal_distances)
          stress = 0.0
          n = xpos.length

          n.times do |i|
            row = ideal_distances[i]
            (i + 1).upto(n - 1) do |j|
              ideal_dist = row[j]
              next if ideal_dist == Float::INFINITY

              dx = xpos[j] - xpos[i]
              dy = ypos[j] - ypos[i]
              diff = Math.sqrt((dx * dx) + (dy * dy)) - ideal_dist
              stress += diff * diff
            end
          end

          stress
        end

        # Updates xpos and ypos in place, one node at a time, so each node sees
        # the already-moved positions of the nodes before it.
        def optimize_positions(xpos, ypos, ideal_distances, weights)
          xpos.length.times do |i|
            sum_x, sum_y, sum_weight =
              pull_sums(xpos, ypos, i, ideal_distances[i], weights[i])
            next unless sum_weight.positive?

            xpos[i] = sum_x / sum_weight
            ypos[i] = sum_y / sum_weight
          end
        end

        def pull_sums(xpos, ypos, node, row, weight_row)
          node_x = xpos[node]
          node_y = ypos[node]
          sum_x = 0.0
          sum_y = 0.0
          sum_weight = 0.0

          xpos.length.times do |j|
            next if node == j

            ideal_dist = row[j]
            next if ideal_dist == Float::INFINITY

            other_x = xpos[j]
            other_y = ypos[j]
            dx = other_x - node_x
            dy = other_y - node_y
            actual_dist = Math.sqrt((dx * dx) + (dy * dy))

            next if actual_dist.zero?

            weight = weight_row[j]
            ratio = ideal_dist / actual_dist

            sum_x += weight * (other_x - (ratio * dx))
            sum_y += weight * (other_y - (ratio * dy))
            sum_weight += weight
          end

          [sum_x, sum_y, sum_weight]
        end
      end
    end
  end
end
