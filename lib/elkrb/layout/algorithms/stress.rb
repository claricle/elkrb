# frozen_string_literal: true

require_relative "base_algorithm"

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
        DEFAULT_ITERATIONS = 500
        DEFAULT_EPSILON = 0.0001

        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          # Get configuration
          iterations = option("iterations", DEFAULT_ITERATIONS).to_i
          epsilon = option("epsilon", DEFAULT_EPSILON).to_f

          # Initialize positions
          initialize_positions(graph)

          # Calculate shortest path distances
          distances = calculate_distances(graph)

          # Iteratively minimize stress
          iterations.times do |_i|
            old_stress = calculate_stress(graph, distances)
            optimize_positions(graph, distances)
            new_stress = calculate_stress(graph, distances)

            # Stop if converged
            break if (old_stress - new_stress).abs < epsilon
          end

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end

        private

        def initialize_positions(graph)
          # Use circular initial layout
          n = graph.children.length
          radius = n * 10.0

          graph.children.each_with_index do |node, i|
            angle = 2 * Math::PI * i / n
            node.x = (radius * Math.cos(angle)) + radius
            node.y = (radius * Math.sin(angle)) + radius
          end
        end

        def calculate_distances(graph)
          n = graph.children.length
          distances = Array.new(n) { Array.new(n, Float::INFINITY) }

          # Initialize distances
          n.times { |i| distances[i][i] = 0 }

          # Set edge distances
          all_edges = collect_all_edges(graph)
          all_edges.each do |edge|
            source_id = edge.sources&.first
            target_id = edge.targets&.first
            next unless source_id && target_id

            i = graph.children.index { |n| n.id == source_id }
            j = graph.children.index { |n| n.id == target_id }

            next unless i && j

            distances[i][j] = 1.0
            distances[j][i] = 1.0
          end

          # Floyd-Warshall for shortest paths
          n.times do |k|
            n.times do |i|
              n.times do |j|
                distances[i][j] = [
                  distances[i][j],
                  distances[i][k] + distances[k][j],
                ].min
              end
            end
          end

          distances
        end

        def calculate_stress(graph, ideal_distances)
          stress = 0.0
          n = graph.children.length

          n.times do |i|
            (i + 1).upto(n - 1) do |j|
              node_i = graph.children[i]
              node_j = graph.children[j]

              dx = node_j.x - node_i.x
              dy = node_j.y - node_i.y
              actual_dist = Math.sqrt((dx**2) + (dy**2))

              ideal_dist = ideal_distances[i][j]
              next if ideal_dist == Float::INFINITY

              diff = actual_dist - ideal_dist
              stress += diff * diff
            end
          end

          stress
        end

        def optimize_positions(graph, ideal_distances)
          n = graph.children.length

          # Calculate new positions using stress majorization
          graph.children.each_with_index do |node, i|
            sum_x = 0.0
            sum_y = 0.0
            sum_weight = 0.0

            n.times do |j|
              next if i == j

              ideal_dist = ideal_distances[i][j]
              next if ideal_dist == Float::INFINITY

              other = graph.children[j]
              dx = other.x - node.x
              dy = other.y - node.y
              actual_dist = Math.sqrt((dx**2) + (dy**2))

              next if actual_dist.zero?

              weight = 1.0 / (ideal_dist * ideal_dist)
              ratio = ideal_dist / actual_dist

              sum_x += weight * (other.x - (ratio * dx))
              sum_y += weight * (other.y - (ratio * dy))
              sum_weight += weight
            end

            if sum_weight.positive?
              node.x = sum_x / sum_weight
              node.y = sum_y / sum_weight
            end
          end
        end

        def collect_all_edges(graph)
          edges = []
          edges.concat(graph.edges) if graph.edges
          graph.children&.each do |node|
            edges.concat(node.edges) if node.edges
          end
          edges
        end
      end
    end
  end
end
