# frozen_string_literal: true

module Elkrb
  module Layout
    module Polyomino
      # A rectangular grid of blocked and empty cells, addressed either from
      # the top-left corner or from the cell at (center_col, center_row).
      #
      # Port of the two-valued core of ELK's PlanarGrid. Out-of-range reads
      # raise IndexError; Ruby arrays would otherwise wrap negative indexes
      # around to the far edge.
      class Grid
        attr_reader :width, :height, :center_col, :center_row

        def initialize(width, height)
          @width = width
          @height = height
          @center_col = (width - 1) >> 1
          @center_row = (height - 1) >> 1
          @cells = Array.new(height) { Array.new(width, false) }
        end

        def blocked?(col, row)
          check_bounds(col, row)
          @cells[row][col]
        end

        def block(col, row)
          check_bounds(col, row)
          @cells[row][col] = true
        end

        def in_bounds?(col, row)
          col.between?(0, width - 1) && row.between?(0, height - 1)
        end

        # Each blocked cell as (col, row), top row first.
        def each_blocked
          return enum_for(:each_blocked) unless block_given?

          @cells.each_with_index do |line, row|
            line.each_with_index { |cell, col| yield col, row if cell }
          end
        end

        # Every (col, row) of the grid.
        def positions
          (0...width).to_a.product((0...height).to_a)
        end

        # The cells as rows of booleans, and as columns of booleans.
        def rows
          @cells.map(&:dup)
        end

        def columns
          Array.new(width) { |col| @cells.map { |line| line[col] } }
        end

        # The [left, top] of +other+ on this grid when its center cell sits
        # at (+shift_col+, +shift_row+) from this grid's center cell.
        def origin_for(other, shift_col, shift_row)
          [shift_col - other.center_col + center_col,
           shift_row - other.center_row + center_row]
        end

        # True when placing +other+ at that shift would put a blocked cell of
        # +other+ on a blocked cell of this grid or outside it.
        def intersects?(other, shift_col, shift_row)
          left, top = origin_for(other, shift_col, shift_row)
          other.each_blocked.any? do |col, row|
            taken?(left + col, top + row)
          end
        end

        # Blocks the cells +other+ blocks when placed at that shift.
        def add_blocked_cells_from(other, shift_col, shift_row)
          left, top = origin_for(other, shift_col, shift_row)
          other.each_blocked { |col, row| block(left + col, top + row) }
        end

        # The bounding box of the blocked cells as [min_col, min_row, width,
        # height], or nil when nothing is blocked.
        def filled_bounds
          cols, rows = each_blocked.to_a.transpose
          return nil unless cols

          [cols.min, rows.min,
           cols.max - cols.min + 1, rows.max - rows.min + 1]
        end

        private

        def taken?(col, row)
          !in_bounds?(col, row) || @cells[row][col]
        end

        def check_bounds(col, row)
          return if in_bounds?(col, row)

          raise IndexError, "(#{col}, #{row}) is outside #{width}x#{height}"
        end
      end
    end
  end
end
