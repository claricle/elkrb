# frozen_string_literal: true

require_relative "piece"

module Elkrb
  module Layout
    module Polyomino
      # Packs pieces onto one grid, largest first, each at the first free
      # position of a line-by-line walk out from the grid's center.
      #
      # Port of ELK's PolyominoCompactor with the defaults DisCo runs with:
      # QUADRANTS_LINE_BY_LINE traversal, BY_SIZE_AND_SHAPE ordering, and
      # Profile Fill. Pieces have no extensions, so ELK's extension-based
      # orderings and quadrant restrictions are all no-ops and are not ported.
      module Packer
        module_function

        # Places every piece and returns the pieces in packing order. Each
        # piece's col and row become its top-left cell on the returned grid.
        #
        # @param pieces [Array<Piece>]
        # @param aspect_ratio [Float] target width/height of the packing
        # @param fill [Boolean] apply Profile Fill before packing
        # @return [Array(Array<Piece>, Grid)] pieces in packing order, grid
        def pack(pieces, aspect_ratio:, fill: true)
          pieces.each(&:fill_enclosed_cells) if fill
          grid = Grid.new(*grid_size(pieces, aspect_ratio))
          ordered = packing_order(pieces)
          ordered.each { |piece| place(grid, piece) }
          [ordered, grid]
        end

        # Largest first; equal pieces keep the order they were given in.
        def packing_order(pieces)
          pieces.each_with_index
            .sort_by { |piece, index| [-shape_cost(piece), index] }
            .map(&:first)
        end

        def grid_size(pieces, aspect_ratio)
          width = doubled_extent(pieces, :width)
          height = doubled_extent(pieces, :height)
          return [(width * aspect_ratio).ceil, height] if aspect_ratio > 1.0

          [width, (height / aspect_ratio).ceil]
        end

        def doubled_extent(pieces, side)
          first = pieces.first&.public_send(side) || 0
          2 * (pieces.sum(&side) + first)
        end

        # Squared short side plus long side: ELK's
        # MinPerimeterComparatorWithShape.
        def shape_cost(piece)
          short, long = [piece.width, piece.height].minmax
          (short * short) + long
        end

        def place(grid, piece)
          shift = free_shift(grid, piece)
          grid.add_blocked_cells_from(piece, *shift)
          piece.col, piece.row = grid.origin_for(piece, *shift)
        end

        def free_shift(grid, piece)
          limit = [grid.width, grid.height].max
          shift = [0, 0]
          while grid.intersects?(piece, *shift)
            shift = next_shift(*shift)
            next if shift.all? { |step| step.abs <= limit }

            raise Elkrb::Error, "polyomino packing found no free position"
          end
          shift
        end

        # ELK's SuccessorLineByLine: the walk 0,0 -> 1,0 -> ... along each
        # row of an expanding square, rows top to bottom.
        def next_shift(col, row)
          return corner_shift(col, row) if col >= 0 && col.abs == row.abs
          return [col + 1, row] unless col.abs > row.abs

          [-col, col.negative? ? row : row + 1]
        end

        def corner_shift(col, row)
          return [-col - 1, -col - 1] if col == row

          [-col, row + 1]
        end
      end
    end
  end
end
