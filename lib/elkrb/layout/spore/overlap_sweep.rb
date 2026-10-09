# frozen_string_literal: true

module Elkrb
  module Layout
    module Spore
      # Top-to-bottom scanline that reports the pairs of bodies whose
      # rectangles overlap. Mirrors the Java sweep, including its early stop:
      # once a newly inserted body has met an overlapping neighbour, the scan
      # of the left-sorted active set ends at the next non-overlapping one.
      class OverlapSweep
        # @return [Array<Array(Body, Body)>] each pair once, in sweep order
        def self.pairs(bodies)
          new.pairs(bodies)
        end

        def pairs(bodies)
          @active = []
          @pairs = []
          events(bodies).each do |body, low|
            low ? insert(body) : remove(body)
          end
          @pairs
        end

        private

        # Each body twice (top border, bottom border), by row.
        def events(bodies)
          stamps = bodies.flat_map { |body| [[body, true], [body, false]] }
          stamps.each_with_index.sort do |(first, i), (second, j)|
            compare(first, second).nonzero? || (i <=> j)
          end.map(&:first)
        end

        # At equal rows the bottom borders come first.
        def compare(first, second)
          by_row = row(first) <=> row(second)
          return by_row unless by_row.zero?

          (first.last ? 1 : 0) <=> (second.last ? 1 : 0)
        end

        def row(stamp)
          body, low = stamp
          low ? body.y : body.y + body.height
        end

        def remove(body)
          @active.delete_if { |other| other.equal?(body) }
        end

        def insert(body)
          at = @active.bsearch_index do |other|
            (sort_key(other) <=> sort_key(body)) >= 0
          end
          @active.insert(at || @active.size, body)
          collect_pairs(body)
        end

        # The active set is not guaranteed to hold the overlaps contiguously
        # (a wide body can hide behind a narrow one); the scan stops at the
        # first gap after a hit, as Java's does.
        def collect_pairs(body)
          met = false
          @active.each do |other|
            if overlapping?(body, other)
              @pairs << [body, other]
              met = true
            elsif met
              break
            end
          end
        end

        def sort_key(body)
          [body.x, body.origin_x, body.origin_y]
        end

        def overlapping?(first, second)
          return false if first.equal?(second)

          Geometry.fuzzy_compare(first.x, second.x + second.width,
                                 Geometry::FUZZINESS).negative? &&
            Geometry.fuzzy_compare(second.x, first.x + first.width,
                                   Geometry::FUZZINESS).negative?
        end
      end
    end
  end
end
