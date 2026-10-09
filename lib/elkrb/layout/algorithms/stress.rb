# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../java_random"
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
        FORCE_ITERATIONS = 300
        FORCE_TEMPERATURE = 0.001
        FORCE_SPACING = 80.0
        FORCE_PADDING = { left: 50.0, top: 50.0, right: 50.0,
                          bottom: 50.0 }.freeze
        FORCE_ZERO_FACTOR = 100.0
        FORCE_DISPLACEMENT_FACTOR = 16
        FORCE_PAIR_INTERACTION_BUDGET = 250_000

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
          old_stress = calculate_stress(
            xpos, ypos, distances, weights, reachable
          )
          # Java ELK's do/while checks the limit after an iteration has run,
          # so a limit of N allows N + 1 iterations.
          (iterations.clamp(0..) + 1).times do
            optimize_positions(xpos, ypos, distances, weights, reachable)
            new_stress = calculate_stress(
              xpos, ypos, distances, weights, reachable
            )

            break if converged?(old_stress, new_stress, epsilon)

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

        # Same stop test as Java ELK: the stress improvement relative to the
        # previous stress, so graphs of any size stop at the same quality.
        # The default iteration limit is Java's Integer.MAX_VALUE, so this is
        # what ends the loop: a non-finite stress or an iteration that made
        # no progress also stops, whatever the epsilon, or the loop would
        # never end for an epsilon of zero or less.
        def converged?(old_stress, new_stress, epsilon)
          return true unless old_stress.finite? && new_stress.finite?
          return true if old_stress.zero?

          improvement = (old_stress - new_stress) / old_stress
          improvement <= 0 || improvement < epsilon
        end

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
          nodes = graph.children
          random = JavaRandom.new(option("elk.randomSeed").to_i)
          positions = force_seed_positions(nodes.length, random)
          connections, edge_count = force_connections(graph)

          run_force_prepass(nodes, positions, connections, edge_count, random)
          apply_force_positions(nodes, positions)
        end

        def force_seed_positions(count, random)
          x = Array.new(count)
          y = Array.new(count)
          count.times do |i|
            x[i] = random.next_double * count
            y[i] = random.next_double * count
          end
          [x, y]
        end

        def force_connections(graph)
          nodes = graph.children
          count = nodes.length
          matrix = Array.new(count * count, 0)
          positions = nodes.each_with_index.to_h { |node, i| [node.id, i] }
          index = NodeIndex.build(graph)
          edge_count = 0

          (graph.edges || []).each do |edge|
            source = index.node(edge.sources&.first)
            target = index.node(edge.targets&.first)
            next unless source && target

            source_slot = positions[source.id]
            target_slot = positions[target.id]
            next unless source_slot && target_slot
            next if source_slot == target_slot

            matrix[(source_slot * count) + target_slot] += 1
            edge_count += 1
          end

          [matrix, edge_count]
        end

        def run_force_prepass(nodes, positions, connections, edge_count,
                              random)
          count = nodes.length
          widths = nodes.map { |node| [node.width.to_f, 1.0].max }
          heights = nodes.map { |node| [node.height.to_f, 1.0].max }
          radii = widths.zip(heights).map do |width, height|
            Math.hypot(width, height) / 2.0
          end
          k = Math.sqrt((widths.sum * heights.sum) / (2.0 * count)) *
              FORCE_SPACING * 0.01
          bound = [count * FORCE_DISPLACEMENT_FACTOR + edge_count,
                   FORCE_DISPLACEMENT_FACTOR**2].max
          iterations = force_iterations(count)
          temperature = FORCE_TEMPERATURE
          threshold = temperature / iterations

          while temperature.positive?
            temperature -= threshold
            force_iteration(positions, radii, connections, k, temperature,
                            bound, random)
          end
        end

        # The exact 300-iteration prepass is cheap for the small graphs it was
        # designed for. On large graphs, bound its quadratic work and preserve
        # the same cooling curve across the deterministic reduced iteration
        # count so Stress keeps its documented performance guarantee.
        def force_iterations(node_count)
          pair_count = node_count * (node_count - 1) / 2
          return FORCE_ITERATIONS if pair_count.zero?

          budgeted = [FORCE_PAIR_INTERACTION_BUDGET / pair_count, 1].max
          [FORCE_ITERATIONS, budgeted].min
        end

        def force_iteration(positions, radii, connections, k, temperature,
                            bound, random)
          x, y = positions
          count = x.length
          dx_sum = Array.new(count, 0.0)
          dy_sum = Array.new(count, 0.0)
          i = 0

          while i < count
            j = i + 1
            while j < count
              separate_coincident_positions(positions, i, j, random)
              dx = x[i] - x[j]
              dy = y[i] - y[j]
              length = Math.sqrt((dx * dx) + (dy * dy))
              border_distance = [length - radii[i] - radii[j], 0.0].max
              force = if border_distance.positive?
                        k * k / border_distance
                      else
                        k * k * FORCE_ZERO_FACTOR
                      end
              connection = connections[(i * count) + j] +
                           connections[(j * count) + i]
              force -= border_distance * border_distance / k * connection
              scale = force * temperature / length
              force_x = dx * scale
              force_y = dy * scale
              dx_sum[i] += force_x
              dy_sum[i] += force_y
              dx_sum[j] -= force_x
              dy_sum[j] -= force_y
              j += 1
            end
            i += 1
          end

          count.times do |slot|
            x[slot] += dx_sum[slot].clamp(-bound, bound)
            y[slot] += dy_sum[slot].clamp(-bound, bound)
          end
        end

        def separate_coincident_positions(positions, first, second, random)
          x, y = positions
          while x[first] == x[second] && y[first] == y[second]
            x[second] += random.next_double - 0.5
            y[second] += random.next_double - 0.5
            x[first] += random.next_double - 0.5
            y[first] += random.next_double - 0.5
          end
        end

        def apply_force_positions(nodes, positions)
          x, y = positions
          left = nodes.each_index.map do |i|
            x[i] - ([nodes[i].width.to_f, 1.0].max / 2.0)
          end.min
          top = nodes.each_index.map do |i|
            y[i] - ([nodes[i].height.to_f, 1.0].max / 2.0)
          end.min
          pad = padding

          nodes.each_with_index do |node, i|
            node.x = x[i] + pad[:left] - left - (node.width.to_f / 2.0)
            node.y = y[i] + pad[:top] - top - (node.height.to_f / 2.0)
          end
        end

        # ELK Stress uses Force's 50px padding for its noninteractive seed
        # pass, and keeps that padding for the final stress result.
        def padding
          option("elk.padding", default: FORCE_PADDING).to_h
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
        def calculate_stress(xpos, ypos, ideal_distances, weights, reachable)
          stress = 0.0

          i = 0
          n = xpos.length
          while i < n
            row = ideal_distances[i]
            weight_row = weights[i]
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
                stress += weight_row[j] * diff * diff
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
