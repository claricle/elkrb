# frozen_string_literal: true

module Elkrb
  module Layout
    module Spore
      # A node as SPOrE sees it: the node's box grown by the node spacing
      # (the rectangle), its moving centre, and the centre it had when the
      # current pass started (the key that edges and tree vertices use).
      class Body
        attr_reader :source, :x, :y, :width, :height, :center_x, :center_y,
                    :origin_x, :origin_y

        def initialize(source, spacing)
          @source = source
          @width = source.width.to_f + spacing
          @height = source.height.to_f + spacing
          reposition(middle(source.x, source.width),
                     middle(source.y, source.height))
        end

        def origin
          [origin_x, origin_y]
        end

        def translate(shift_x, shift_y)
          @center_x += shift_x
          @center_y += shift_y
          @x += shift_x
          @y += shift_y
        end

        def center_at(new_x, new_y)
          translate(new_x - center_x, new_y - center_y)
        end

        # Starts the next pass from where the last one left the node.
        def rebase
          @origin_x = x + (width / 2.0)
          @origin_y = y + (height / 2.0)
        end

        # Moves the node a hair off its spot, so that two nodes that started
        # on the same point get distinct centres and every tree edge has a
        # direction to stretch along.
        def nudge(rng)
          reposition(center_x + ((rng.rand - 0.5) * 0.001),
                     center_y + ((rng.rand - 0.5) * 0.001))
        end

        private

        def middle(low, size)
          low.to_f + (size.to_f / 2.0)
        end

        def reposition(new_x, new_y)
          @center_x = @origin_x = new_x
          @center_y = @origin_y = new_y
          @x = new_x - (width / 2.0)
          @y = new_y - (height / 2.0)
        end
      end
    end
  end
end
