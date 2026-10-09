# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Layout::Polyomino::Packer do
  def piece(rows, payload = nil)
    built = Elkrb::Layout::Polyomino::Piece.new(rows.first.size, rows.size,
                                                payload)
    rows.each_with_index do |line, row|
      line.each_char.with_index do |char, col|
        built.block(col, row) if char == "#"
      end
    end
    built
  end

  def rectangle(width, height, payload = nil)
    piece(Array.new(height) { "#" * width }, payload)
  end

  def cells_of(placed)
    placed.each_blocked.map { |col, row| [placed.col + col, placed.row + row] }
  end

  def random_piece(rng, payload)
    width = rng.rand(1..6)
    height = rng.rand(1..6)
    rows = Array.new(height) do
      Array.new(width) do
        rng.rand < 0.7 ? "#" : "."
      end.join
    end
    rows[0][0] = "#"
    piece(rows, payload)
  end

  describe ".pack" do
    it "never gives two pieces one cell, over generated pieces and ratios" do
      rng = Random.new(20_241_009)
      200.times do
        pieces = Array.new(rng.rand(1..8)) { |i| random_piece(rng, i) }
        ratio = [1.0, 1.6, 0.4].sample(random: rng)
        ordered, grid = described_class.pack(pieces, aspect_ratio: ratio)
        cells = ordered.flat_map { |placed| cells_of(placed) }

        expect(cells.uniq.size).to eq(cells.size)
        expect(cells).to all(satisfy { |col, row| grid.in_bounds?(col, row) })
      end
    end

    it "keeps every piece, in packing order largest shape first" do
      pieces = [rectangle(1, 1, :small), rectangle(4, 4, :large),
                rectangle(2, 3, :medium)]

      ordered, = described_class.pack(pieces, aspect_ratio: 1.0)

      expect(ordered.map(&:payload)).to eq(%i[large medium small])
    end

    it "keeps the given order between pieces of one shape" do
      pieces = Array.new(4) { |i| rectangle(2, 2, i) }

      ordered, = described_class.pack(pieces, aspect_ratio: 1.0)

      expect(ordered.map(&:payload)).to eq([0, 1, 2, 3])
    end

    it "walks out from the center a row at a time" do
      pieces = Array.new(3) { |i| rectangle(2, 2, i) }

      ordered, = described_class.pack(pieces, aspect_ratio: 1.0)
      first = ordered.first

      expect(ordered.map { |p| [p.col - first.col, p.row - first.row] })
        .to eq([[0, 0], [-2, -2], [0, -2]])
    end

    context "when a piece has a hole" do
      let(:ring) { %w[##### #...# #...# #...# #####] }

      def hole_taken?(fill:)
        pieces = [piece(ring, :ring), rectangle(1, 1, :dot)]
        ordered, = described_class.pack(pieces, aspect_ratio: 1.0,
                                                fill: fill)
        dot = ordered.find { |placed| placed.payload == :dot }
        outer = ordered.find { |placed| placed.payload == :ring }

        inside?(dot, outer)
      end

      def inside?(dot, outer)
        [dot.col - outer.col, dot.row - outer.row].all? do |gap|
          gap.between?(1, 3)
        end
      end

      it "packs a small piece into the hole without profile fill" do
        expect(hole_taken?(fill: false)).to be(true)
      end

      it "keeps a small piece out of the hole with profile fill" do
        expect(hole_taken?(fill: true)).to be(false)
      end
    end
  end

  describe Elkrb::Layout::Polyomino::Piece do
    it "fills a cell only when blocked cells lie on all four sides of it" do
      shape = piece(%w[.#. #.. .#.])
      shape.fill_enclosed_cells

      expect(shape.blocked?(1, 1)).to be(false)

      closed = piece(%w[.#. #.# .#.])
      closed.fill_enclosed_cells

      expect(closed.blocked?(1, 1)).to be(true)
    end
  end
end
