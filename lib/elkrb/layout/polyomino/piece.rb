# frozen_string_literal: true

require_relative "grid"

module Elkrb
  module Layout
    module Polyomino
      # A grid plus the position the packer gave it, in cells of the packing
      # grid. +payload+ is whatever the caller wants back (a component).
      class Piece < Grid
        attr_accessor :col, :row
        attr_reader :payload

        def initialize(width, height, payload = nil)
          super(width, height)
          @payload = payload
          @col = 0
          @row = 0
        end

        # Blocks every empty cell that has a blocked cell somewhere to its
        # north, south, east and west, so a small piece cannot be packed into
        # the hole of a large one. Profile Fill of Freivalds et al. (2002).
        def fill_enclosed_cells
          enclosed_cells.each { |col, row| block(col, row) }
        end

        private

        def enclosed_cells
          north, south = extents(columns)
          east, west = extents(rows)
          positions.select do |col, row|
            between?(col, east[row], west[row]) &&
              between?(row, north[col], south[col])
          end
        end

        # Per line, the index of its first and of its last blocked cell; an
        # empty line gets the values that no cell can lie between.
        def extents(lines)
          [lines.map { |line| line.index(true) || line.size },
           lines.map { |line| line.rindex(true) || -1 }]
        end

        def between?(value, low, high)
          low < value && value < high
        end
      end
    end
  end
end
