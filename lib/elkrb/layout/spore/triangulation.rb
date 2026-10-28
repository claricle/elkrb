# frozen_string_literal: true

module Elkrb
  module Layout
    module Spore
      # Delaunay triangulation by incremental Bowyer-Watson insertion into a
      # super-triangle. Points are [x, y] pairs and must be distinct.
      module Triangulation
        WIGGLE_ROOM = 50.0

        # The extent of a point set.
        Bounds = Struct.new(:min_x, :max_x, :min_y, :max_y) do
          def width
            max_x - min_x
          end

          def half_height
            (max_y - min_y) / 2
          end

          def frame_top
            [min_x - WIGGLE_ROOM, min_y - width - WIGGLE_ROOM]
          end

          def frame_bottom
            [min_x - WIGGLE_ROOM, max_y + width + WIGGLE_ROOM]
          end

          def frame_tip
            [max_x + half_height + WIGGLE_ROOM, min_y + half_height]
          end
        end

        # Vector arithmetic on [x, y] pairs.
        module Pair
          module_function

          def delta(from, to)
            [to[0] - from[0], to[1] - from[1]]
          end

          def sum(first, second)
            [first[0] + second[0], first[1] + second[1]]
          end

          def dot(first, second)
            (first[0] * second[0]) + (first[1] * second[1])
          end

          def cross(first, second)
            (first[0] * second[1]) - (first[1] * second[0])
          end

          def distance(from, to)
            Math.sqrt(dot(delta(from, to), delta(from, to)))
          end
        end

        # A triangle with its circumcentre cached.
        Triangle = Struct.new(:a, :b, :c) do
          def vertices
            [a, b, c]
          end

          def edges
            [[a, b], [b, c], [c, a]]
          end

          def contains_edge?(edge)
            edges.any? { |own| Triangulation.same_edge?(own, edge) }
          end

          def circumcenter
            @circumcenter ||= compute_circumcenter
          end

          def in_circumcircle?(point)
            Geometry.fuzzy_compare(Pair.distance(circumcenter, point),
                                   Pair.distance(circumcenter, a),
                                   Geometry::FUZZINESS).negative?
          end

          private

          def compute_circumcenter
            ab = Pair.delta(a, b)
            ac = Pair.delta(a, c)
            e, f, g = circumcenter_terms(ab, ac)
            [term(1, ac, e, ab, f) / g, term(0, ab, f, ac, e) / g]
          end

          def circumcenter_terms(ab_vec, ac_vec)
            [Pair.dot(ab_vec, Pair.sum(a, b)),
             Pair.dot(ac_vec, Pair.sum(a, c)),
             2 * Pair.cross(ab_vec, Pair.delta(b, c))]
          end

          def term(index, first, first_scale, second, second_scale)
            (first[index] * first_scale) - (second[index] * second_scale)
          end
        end

        module_function

        def same_edge?(first, second)
          first == second || first == second.reverse
        end

        # @param points [Array<Array(Float, Float)>]
        # @return [Array<Array(Array, Array)>] each edge once
        def triangulate(points)
          return [] if points.empty?

          frame = enclosing_triangle(points)
          triangles = points.reduce([frame]) do |current, point|
            insert(current, point)
          end
          inner_edges(triangles, frame).uniq(&:sort)
        end

        def inner_edges(triangles, frame)
          triangles.flat_map(&:edges).reject do |edge|
            edge.any? { |vertex| frame.vertices.include?(vertex) }
          end
        end

        # Large enough that no point sits near its border, which would give
        # circumcircles too big for a double to compare.
        def enclosing_triangle(points)
          bounds = Bounds.new(*points.map(&:first).minmax,
                              *points.map(&:last).minmax)
          Triangle.new(bounds.frame_top, bounds.frame_bottom,
                       bounds.frame_tip)
        end

        def insert(triangles, point)
          invalid, valid = triangles.partition do |triangle|
            triangle.in_circumcircle?(point)
          end
          boundary(invalid).each do |from, to|
            valid << Triangle.new(point, from, to)
          end
          valid
        end

        # Edges of the invalid triangles that no other invalid triangle has.
        def boundary(invalid)
          invalid.flat_map do |triangle|
            triangle.edges.select do |edge|
              invalid.none? do |other|
                !other.equal?(triangle) && other.contains_edge?(edge)
              end
            end
          end
        end
      end
    end
  end
end
