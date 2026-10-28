# frozen_string_literal: true

require_relative "hyper_edge_segment"
require_relative "segment_order"

module Elkrb
  module Layout
    module Algorithms
      module Layered
        module Orthogonal
          # Assigns routing slots to the edge runs between two adjacent
          # layers, ordering them so edges cross and run beside each other as
          # little as possible. Works on cross coordinates only.
          #
          # Not ported: splitting a segment that sits in a cycle of critical
          # dependencies. Such a cycle is broken like a regular one, so two
          # edges may overlap where Java ELK would add a detour.
          class GapSolver
            CONFLICT_THRESHOLD_FACTOR = 0.5
            CRITICAL_CONFLICT_THRESHOLD_FACTOR = 0.2
            CONFLICT_PENALTY = 1
            CROSSING_PENALTY = 16
            CRITICAL = :critical

            # @param edge_spacing [Numeric] distance between neighbouring slots
            def initialize(edge_spacing)
              @conflict_threshold = CONFLICT_THRESHOLD_FACTOR * edge_spacing
            end

            # @param source_ports [Array<PortOrder::Port>] ports of the earlier
            #   layer in layer order, top to bottom within a node
            # @param coordinate [#call] cross coordinate of a port
            # @return [Array<HyperEdgeSegment>] with `slot` set
            def solve(source_ports, coordinate)
              segments = build_segments(source_ports, coordinate)
              @critical_threshold =
                CRITICAL_CONFLICT_THRESHOLD_FACTOR * minimum_distance(segments)
              link(segments)
              break_cycles(segments)
              number(segments)
              segments
            end

            # Number of slots the non-straight segments occupy.
            def self.slot_count(segments)
              ranks = segments.reject(&:straight?).map(&:slot)
              ranks.empty? ? 0 : ranks.max + 1
            end

            private

            def build_segments(source_ports, coordinate)
              owner = {}.compare_by_identity
              source_ports.each_with_object([]) do |port, segments|
                next if owner.key?(port)

                segment = HyperEdgeSegment.new
                segments << segment
                collect(port, segment, owner, coordinate)
              end
            end

            def collect(port, segment, owner, coordinate)
              return if owner.key?(port)

              owner[port] = segment
              if port.side == :east
                segment.add_source(port, coordinate.call(port))
              else
                segment.add_target(port, coordinate.call(port))
              end
              port.others.each do |other|
                collect(other, segment, owner, coordinate)
              end
            end

            def minimum_distance(segments)
              [segments.flat_map(&:incoming), segments.flat_map(&:outgoing)]
                .map { |values| minimum_difference(values) }.min
            end

            def minimum_difference(values)
              distinct = values.uniq.sort
              return Float::MAX if distinct.length < 2

              distinct.each_cons(2).map { |low, high| high - low }.min
            end

            # Dependencies between every pair of segments that need ordering.
            def link(segments)
              segments.combination(2) do |first, second|
                create_dependency(first, second)
              end
            end

            def create_dependency(first, second)
              return if first.straight? || second.straight?

              first_first = conflicts(first.outgoing, second.incoming)
              second_first = conflicts(second.outgoing, first.incoming)
              if [first_first, second_first].include?(CRITICAL)
                critical_dependencies(first, second, first_first, second_first)
              else
                regular_dependency(first, second, first_first, second_first)
              end
            end

            def critical_dependencies(first, second, first_first, second_first)
              Dependency.new(second, first, 1, critical: true) if
                first_first == CRITICAL
              Dependency.new(first, second, 1, critical: true) if
                second_first == CRITICAL
            end

            def regular_dependency(first, second, first_first, second_first)
              left = penalty(first, second, first_first)
              right = penalty(second, first, second_first)
              if left < right
                Dependency.new(first, second, right - left)
              elsif left > right
                Dependency.new(second, first, left - right)
              elsif left.positive?
                Dependency.new(first, second, 0)
                Dependency.new(second, first, 0)
              end
            end

            # Cost of putting `before` in a lower slot than `after`.
            def penalty(before, after, conflicts)
              crossings =
                crossings(before.outgoing, after.start_coordinate,
                          after.end_coordinate) +
                crossings(after.incoming, before.start_coordinate,
                          before.end_coordinate)
              (CONFLICT_PENALTY * conflicts) + (CROSSING_PENALTY * crossings)
            end

            # Conflicts between two sorted coordinate lists, or CRITICAL as
            # soon as two coordinates are almost equal.
            def conflicts(first, second)
              return 0 if first.empty? || second.empty?

              count = 0
              walk_pairs(first, second) do |one, two|
                return CRITICAL if near?(one, two, @critical_threshold)

                count += 1 if near?(one, two, @conflict_threshold)
              end
              count
            end

            # Yields the pairs met when stepping through two sorted lists
            # in step with each other.
            def walk_pairs(first, second)
              at = [0, 0]
              loop do
                yield first[at[0]], second[at[1]]
                at = next_pair(first, second, at) || break
              end
            end

            def next_pair(first, second, at)
              left, right = at
              if first[left] <= second[right] && left + 1 < first.length
                [left + 1, right]
              elsif second[right] <= first[left] && right + 1 < second.length
                [left, right + 1]
              end
            end

            def near?(first, second, threshold)
              first > second - threshold && first < second + threshold
            end

            def crossings(positions, from, to)
              positions.count { |position| position.between?(from, to) }
            end

            def break_cycles(segments)
              detect_cycles(segments).each do |dependency|
                if dependency.weight.zero?
                  dependency.remove
                else
                  dependency.reverse
                end
              end
            end

            def detect_cycles(segments)
              SegmentOrder.new(segments).assign_marks
              segments.flat_map do |segment|
                segment.out_dependencies.select do |dependency|
                  segment.mark > dependency.target.mark
                end
              end
            end

            def number(segments)
              queue = segments.select { |s| s.in_dependencies.empty? }
              remaining = segments.to_h { |s| [s, s.in_dependencies.length] }
              queue.concat(relax(queue.shift, remaining)) until queue.empty?
            end

            # Puts the targets one slot beyond `segment`; returns those that
            # now have all their predecessors numbered.
            def relax(segment, remaining)
              segment.out_dependencies.filter_map do |dependency|
                target = dependency.target
                target.raise_slot(segment.slot)
                remaining[target] -= 1
                target if remaining[target].zero?
              end
            end
          end
        end
      end
    end
  end
end
