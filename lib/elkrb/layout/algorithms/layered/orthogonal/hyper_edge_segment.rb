# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        module Orthogonal
          # One run of edge between two layers that shares a single
          # perpendicular stretch: the ports joined by edges, with the cross
          # coordinates where edges leave the earlier layer (`incoming`) and
          # enter the later one (`outgoing`), both sorted and distinct.
          class HyperEdgeSegment
            TOLERANCE = 1e-3

            attr_reader :ports, :incoming, :outgoing,
                        :out_dependencies, :in_dependencies
            attr_accessor :slot, :mark, :in_weight, :out_weight,
                          :critical_in_weight, :critical_out_weight

            def initialize
              @ports = []
              @incoming = []
              @outgoing = []
              @out_dependencies = []
              @in_dependencies = []
              @slot = 0
              @mark = 0
            end

            def add_source(port, coordinate)
              ports << port
              incoming << coordinate unless incoming.include?(coordinate)
              incoming.sort!
            end

            def add_target(port, coordinate)
              ports << port
              outgoing << coordinate unless outgoing.include?(coordinate)
              outgoing.sort!
            end

            def start_coordinate
              [incoming.first, outgoing.first].compact.min
            end

            def end_coordinate
              [incoming.last, outgoing.last].compact.max
            end

            # A straight run takes no slot and needs no bend points.
            def straight?
              (start_coordinate - end_coordinate).abs < TOLERANCE
            end

            # Gives the segment the negative mark of an unplaced one, and
            # weights taken from its dependencies.
            def reset_weights(position)
              @mark = -(position + 1)
              @in_weight = in_dependencies.sum(&:weight)
              @out_weight = out_dependencies.sum(&:weight)
              @critical_in_weight = critical_weight(in_dependencies)
              @critical_out_weight = critical_weight(out_dependencies)
            end

            def balance
              out_weight - in_weight
            end

            def unplaced?
              mark.negative?
            end

            def drained_source?
              in_weight <= 0 && out_weight.positive?
            end

            def drained_sink?
              out_weight <= 0 && in_weight.positive?
            end

            # A segment that must precede this one has been placed.
            def release_in(dependency)
              @in_weight -= dependency.weight
              @critical_in_weight -= dependency.weight if dependency.critical?
            end

            # A segment that must follow this one has been placed.
            def release_out(dependency)
              @out_weight -= dependency.weight
              @critical_out_weight -= dependency.weight if
                dependency.critical?
            end

            def raise_slot(above)
              @slot = [slot, above + 1].max
            end

            private

            def critical_weight(dependencies)
              dependencies.select(&:critical?).sum(&:weight)
            end
          end

          # "`source` wants to sit before `target`": a lower routing slot,
          # nearer the earlier layer. Critical ones would overlap edges if
          # reversed.
          class Dependency
            attr_reader :source, :target, :weight

            def initialize(source, target, weight, critical: false)
              @weight = weight
              @critical = critical
              attach(source, target)
            end

            def critical?
              @critical
            end

            def remove
              detach
              @source = nil
              @target = nil
            end

            def reverse
              old_source = source
              old_target = target
              detach
              attach(old_target, old_source)
            end

            private

            def attach(new_source, new_target)
              @source = new_source
              @target = new_target
              source.out_dependencies << self
              target.in_dependencies << self
            end

            def detach
              source.out_dependencies.delete(self)
              target.in_dependencies.delete(self)
            end
          end
        end
      end
    end
  end
end
