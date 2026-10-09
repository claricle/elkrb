# frozen_string_literal: true

require_relative "hyper_edge_segment"

module Elkrb
  module Layout
    module Algorithms
      module Layered
        module Orthogonal
          # Decides which bend points of one gap are junction points: those
          # where an edge meets others of its hyperedge segment mid-run. A
          # point is reported once, for the first edge that bends there.
          class JunctionPoints
            TOLERANCE = HyperEdgeSegment::TOLERANCE

            def initialize
              @taken = Set.new
            end

            # @param segment [HyperEdgeSegment]
            # @param points [Array<Array(Float, Float)>] [along, cross] bends
            # @return [Array<Array(Float, Float)>] those that are junctions
            def among(segment, points)
              points.select do |point|
                next false if @taken.include?(point)
                next false unless junction?(segment, point.last)

                @taken << point
                true
              end
            end

            private

            # Inside the segment's run, or at an end of it where another
            # edge joins at the same cross coordinate.
            def junction?(segment, cross)
              inside = cross > segment.start_coordinate &&
                cross < segment.end_coordinate
              inside || joined_at_end?(segment, cross)
            end

            def joined_at_end?(segment, cross)
              return false if segment.incoming.empty? ||
                segment.outgoing.empty?

              %i[first last].any? do |end_of|
                [segment.incoming, segment.outgoing].all? do |list|
                  (cross - list.public_send(end_of)).abs < TOLERANCE
                end
              end
            end
          end
        end
      end
    end
  end
end
