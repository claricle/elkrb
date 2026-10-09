# frozen_string_literal: true

require_relative "footprint"
require_relative "packer"
require_relative "../../geometry/rectangle"
require_relative "../../geometry/dimension"

module Elkrb
  module Layout
    module Polyomino
      # Packs disconnected components the way ELK's DisCoPolyominoCompactor
      # does: each component becomes a low-resolution polyomino, the
      # polyominoes are packed, and each component gets the offset that moves
      # it to its polyomino's place.
      #
      # A component is an Array of shapes, a shape an Array of [x, y] corners.
      class ComponentCompactor
        # ELK's bound on the cell count per component that the cell size
        # is solved for.
        UPPER_BOUND = 100.0
        private_constant :UPPER_BOUND

        # @param components [Array<Array<Array<Array<Float>>>>]
        # @param aspect_ratio [Float] target width/height, above zero
        # @param fill [Boolean]
        def initialize(components, aspect_ratio:, fill: true)
          @components = components
          @aspect_ratio = aspect_ratio
          @fill = fill
        end

        # @return [Array<Array(Float, Float)>] the [dx, dy] to add to each
        #   component's coordinates, in the order the components were given
        def offsets
          return [] if @components.empty?

          @boxes = @components.map { |shapes| bounding_box(shapes) }
          @cell = cell_size
          placed, origin = pack_pieces
          placed.sort_by(&:payload).map { |piece| offset_of(piece, origin) }
        end

        private

        def bounding_box(shapes)
          xs, ys = shapes.flatten(1).transpose
          Geometry::Rectangle.new(xs.min, ys.min,
                                  xs.max - xs.min, ys.max - ys.min)
        end

        # The packed pieces and the [col, row] of the packing's top-left.
        def pack_pieces
          pieces = @components.each_index.map { |index| build_piece(index) }
          placed, grid = Packer.pack(pieces, aspect_ratio: @aspect_ratio,
                                             fill: @fill)
          [placed, (grid.filled_bounds || [0, 0]).first(2)]
        end

        def offset_of(piece, origin)
          box = @boxes[piece.payload]
          [horizontal_offset(piece, box, origin[0]),
           vertical_offset(piece, box, origin[1])]
        end

        def horizontal_offset(piece, box, origin_col)
          axis_offset(piece.col - origin_col, piece.width, @cell.width,
                      box.x, box.width)
        end

        def vertical_offset(piece, box, origin_row)
          axis_offset(piece.row - origin_row, piece.height, @cell.height,
                      box.y, box.height)
        end

        # Cells from the packing's edge to the piece, plus half the space the
        # piece has over the component, less where the component starts.
        def axis_offset(cells_from_edge, piece_cells, cell, start, size)
          (cells_from_edge * cell) + margin(size, piece_cells, cell) - start
        end

        # The polyomino is at least as large as the component; half the
        # difference is the space either side of it.
        def margin(size, cells, cell)
          ((cells * cell) - size) / 2.0
        end

        # The cell size at which packing every component with at most
        # UPPER_BOUND cells of slack stays tight (ELK's computeCellSize),
        # stretched by the aspect ratio.
        def cell_size
          base = solve_cell_size
          if @aspect_ratio > 1.0
            Geometry::Dimension.new(base * @aspect_ratio, base)
          else
            Geometry::Dimension.new(base, base / @aspect_ratio)
          end
        end

        def solve_cell_size
          size = cell_formula(@boxes.sum { |box| box.width + box.height },
                              @boxes.sum { |box| box.width * box.height },
                              UPPER_BOUND * @boxes.size)
          size.positive? ? size : 1.0
        end

        def cell_formula(sum, product, cells)
          root = Math.sqrt((4.0 * cells * product) - (4.0 * product) +
                           (sum * sum))
          (root + sum) / (2.0 * (cells - 1.0))
        end

        def build_piece(index)
          box = @boxes[index]
          piece = Piece.new((box.width / @cell.width).ceil,
                            (box.height / @cell.height).ceil, index)
          block_touched_cells(piece, first_footprint(box, piece),
                              @components[index])
          piece
        end

        def first_footprint(box, piece)
          Footprint.new(
            box.x - margin(box.width, piece.width, @cell.width),
            box.y - margin(box.height, piece.height, @cell.height),
            @cell.width, @cell.height
          )
        end

        def block_touched_cells(piece, first, shapes)
          piece.positions.each do |col, row|
            cell = first.step(col, row)
            piece.block(col, row) if shapes.any? { |s| cell.touched_by?(s) }
          end
        end
      end
    end
  end
end
