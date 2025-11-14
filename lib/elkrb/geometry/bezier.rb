# frozen_string_literal: true

require_relative "point"

module Elkrb
  module Geometry
    # Bezier curve implementation for smooth edge routing
    #
    # This class provides cubic Bezier curve calculations for creating
    # smooth, curved edges in graph layouts. It supports calculating
    # control points and generating points along the curve.
    class Bezier
      # Calculate points along a cubic Bezier curve
      #
      # @param start_point [Point] The starting point (P0)
      # @param end_point [Point] The ending point (P3)
      # @param control1 [Point] The first control point (P1)
      # @param control2 [Point] The second control point (P2)
      # @param segments [Integer] Number of line segments to generate
      # @return [Array<Point>] Array of points along the curve
      def self.calculate_curve(start_point, end_point, control1, control2,
                               segments = 20)
        points = []
        segments.times do |i|
          t = i.to_f / (segments - 1)
          points << bezier_point(t, start_point, control1, control2, end_point)
        end
        points
      end

      # Calculate default control points for a smooth curve
      #
      # This method generates control points that create a natural-looking
      # curve between two points. The control points are positioned
      # perpendicular to the direct line between start and end points.
      #
      # @param start_point [Point] The starting point
      # @param end_point [Point] The ending point
      # @param curvature [Float] Curve strength (0.0 = straight, 1.0 = very
      #   curved)
      # @return [Array<Point>] Two control points [control1, control2]
      def self.calculate_control_points(start_point, end_point,
                                        curvature = 0.5)
        dx = end_point.x - start_point.x
        dy = end_point.y - start_point.y
        distance = Math.sqrt((dx**2) + (dy**2))

        return [start_point, end_point] if distance < 0.001

        # Control points offset perpendicular to line
        offset = distance * curvature

        # Calculate perpendicular direction
        perp_x = -dy / distance
        perp_y = dx / distance

        control1 = Point.new(
          x: start_point.x + (dx * 0.33) + (perp_x * offset),
          y: start_point.y + (dy * 0.33) + (perp_y * offset),
        )

        control2 = Point.new(
          x: start_point.x + (dx * 0.66) - (perp_x * offset),
          y: start_point.y + (dy * 0.66) - (perp_y * offset),
        )

        [control1, control2]
      end

      # Calculate a point on a cubic Bezier curve at parameter t
      #
      # Uses the cubic Bezier formula:
      # B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
      #
      # @param t [Float] Parameter value (0.0 to 1.0)
      # @param p0 [Point] Start point
      # @param p1 [Point] First control point
      # @param p2 [Point] Second control point
      # @param p3 [Point] End point
      # @return [Point] Point on the curve at parameter t
      def self.bezier_point(t, p0, p1, p2, p3)
        # Clamp t to [0, 1]
        t = [[t, 0.0].max, 1.0].min

        # Calculate Bezier coefficients
        u = 1.0 - t
        tt = t * t
        uu = u * u
        uuu = uu * u
        ttt = tt * t

        # B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
        x = (uuu * p0.x) +
          (3 * uu * t * p1.x) +
          (3 * u * tt * p2.x) +
          (ttt * p3.x)

        y = (uuu * p0.y) +
          (3 * uu * t * p1.y) +
          (3 * u * tt * p2.y) +
          (ttt * p3.y)

        Point.new(x: x, y: y)
      end

      # Calculate simple control points for horizontal-first routing
      #
      # Creates control points that produce a curve with horizontal exit
      # and entry directions, useful for left-to-right or right-to-left
      # edge routing.
      #
      # @param start_point [Point] The starting point
      # @param end_point [Point] The ending point
      # @param offset_ratio [Float] How far to offset controls (0.0 to 1.0)
      # @return [Array<Point>] Two control points [control1, control2]
      def self.horizontal_control_points(start_point, end_point,
                                         offset_ratio = 0.5)
        dx = end_point.x - start_point.x
        offset = dx.abs * offset_ratio

        control1 = Point.new(
          x: start_point.x + offset,
          y: start_point.y,
        )

        control2 = Point.new(
          x: end_point.x - offset,
          y: end_point.y,
        )

        [control1, control2]
      end

      # Calculate simple control points for vertical-first routing
      #
      # Creates control points that produce a curve with vertical exit
      # and entry directions, useful for top-to-bottom or bottom-to-top
      # edge routing.
      #
      # @param start_point [Point] The starting point
      # @param end_point [Point] The ending point
      # @param offset_ratio [Float] How far to offset controls (0.0 to 1.0)
      # @return [Array<Point>] Two control points [control1, control2]
      def self.vertical_control_points(start_point, end_point,
                                       offset_ratio = 0.5)
        dy = end_point.y - start_point.y
        offset = dy.abs * offset_ratio

        control1 = Point.new(
          x: start_point.x,
          y: start_point.y + offset,
        )

        control2 = Point.new(
          x: end_point.x,
          y: end_point.y - offset,
        )

        [control1, control2]
      end
    end
  end
end
