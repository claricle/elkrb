# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        module Orthogonal
          # Greedy feedback-arc-set ordering (Eades, Lin, Smyth) of the
          # segments of one gap. A tie between segments is broken by taking
          # the first, where Java ELK draws from its seeded generator.
          class SegmentOrder
            # @param segments [Array<HyperEdgeSegment>] with dependencies
            #   linked; each gets a `mark` giving its place in the order
            def initialize(segments)
              @segments = segments
            end

            def assign_marks
              @segments.each_with_index do |segment, index|
                segment.reset_weights(index)
              end
              seed_queues
              settle_all
              shift_sink_marks
            end

            private

            def seed_queues
              @sinks = @segments.select { |s| s.out_weight.zero? }
              @sources = initial_sources - @sinks
              @unprocessed = @segments.dup
              @next_sink = @segments.length - 1
              @next_source = @segments.length + 1
            end

            def initial_sources
              @segments.select do |s|
                s.out_weight.positive? && s.in_weight.zero?
              end
            end

            def settle_all
              until @unprocessed.empty?
                drain_sinks
                drain_sources
                promote_best
              end
            end

            def drain_sinks
              until @sinks.empty?
                settle(@sinks.shift, @next_sink)
                @next_sink -= 1
              end
            end

            def drain_sources
              until @sources.empty?
                settle(@sources.shift, @next_source)
                @next_source += 1
              end
            end

            def promote_best
              return if @unprocessed.empty?

              settle(best_candidate, @next_source)
              @next_source += 1
            end

            def settle(segment, mark)
              @unprocessed.delete(segment)
              segment.mark = mark
              release_targets(segment)
              release_origins(segment)
            end

            # Unprocessed segments are visited by ascending mark, i.e. the
            # last one created first.
            def best_candidate
              ordered = @unprocessed.sort_by(&:mark)
              forced_source(ordered) || most_outgoing(ordered)
            end

            def forced_source(ordered)
              ordered.find do |s|
                s.critical_out_weight.positive? && s.critical_in_weight <= 0
              end
            end

            def most_outgoing(ordered)
              top = ordered.map(&:balance).max
              ordered.find { |s| s.balance == top }
            end

            def release_targets(segment)
              open_dependencies(segment.out_dependencies, :target)
                .each do |dependency|
                  target = dependency.target
                  target.release_in(dependency)
                  @sources << target if target.drained_source?
                end
            end

            def release_origins(segment)
              open_dependencies(segment.in_dependencies, :source)
                .each do |dependency|
                  origin = dependency.source
                  origin.release_out(dependency)
                  @sinks << origin if origin.drained_sink?
                end
            end

            # Dependencies that still weigh on a segment not yet placed.
            def open_dependencies(dependencies, far_end)
              dependencies.select do |dependency|
                dependency.weight.positive? &&
                  dependency.public_send(far_end).unplaced?
              end
            end

            def shift_sink_marks
              base = @segments.length
              @segments.each do |segment|
                segment.mark += base + 1 if segment.mark < base
              end
            end
          end
        end
      end
    end
  end
end
