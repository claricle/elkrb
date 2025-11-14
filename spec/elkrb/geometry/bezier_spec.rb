# frozen_string_literal: true

require "spec_helper"
require "elkrb/geometry/bezier"
require "elkrb/geometry/point"

RSpec.describe Elkrb::Geometry::Bezier do
  describe ".bezier_point" do
    it "returns start point at t=0" do
      p0 = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      p1 = Elkrb::Geometry::Point.new(x: 10.0, y: 20.0)
      p2 = Elkrb::Geometry::Point.new(x: 30.0, y: 40.0)
      p3 = Elkrb::Geometry::Point.new(x: 50.0, y: 50.0)

      point = described_class.bezier_point(0.0, p0, p1, p2, p3)

      expect(point.x).to eq(0.0)
      expect(point.y).to eq(0.0)
    end

    it "returns end point at t=1" do
      p0 = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      p1 = Elkrb::Geometry::Point.new(x: 10.0, y: 20.0)
      p2 = Elkrb::Geometry::Point.new(x: 30.0, y: 40.0)
      p3 = Elkrb::Geometry::Point.new(x: 50.0, y: 50.0)

      point = described_class.bezier_point(1.0, p0, p1, p2, p3)

      expect(point.x).to eq(50.0)
      expect(point.y).to eq(50.0)
    end

    it "returns midpoint at t=0.5" do
      p0 = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      p1 = Elkrb::Geometry::Point.new(x: 10.0, y: 0.0)
      p2 = Elkrb::Geometry::Point.new(x: 40.0, y: 0.0)
      p3 = Elkrb::Geometry::Point.new(x: 50.0, y: 0.0)

      point = described_class.bezier_point(0.5, p0, p1, p2, p3)

      expect(point.x).to eq(25.0)
      expect(point.y).to eq(0.0)
    end

    it "clamps t values below 0" do
      p0 = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      p1 = Elkrb::Geometry::Point.new(x: 10.0, y: 20.0)
      p2 = Elkrb::Geometry::Point.new(x: 30.0, y: 40.0)
      p3 = Elkrb::Geometry::Point.new(x: 50.0, y: 50.0)

      point = described_class.bezier_point(-0.5, p0, p1, p2, p3)

      expect(point.x).to eq(0.0)
      expect(point.y).to eq(0.0)
    end

    it "clamps t values above 1" do
      p0 = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      p1 = Elkrb::Geometry::Point.new(x: 10.0, y: 20.0)
      p2 = Elkrb::Geometry::Point.new(x: 30.0, y: 40.0)
      p3 = Elkrb::Geometry::Point.new(x: 50.0, y: 50.0)

      point = described_class.bezier_point(1.5, p0, p1, p2, p3)

      expect(point.x).to eq(50.0)
      expect(point.y).to eq(50.0)
    end
  end

  describe ".calculate_curve" do
    it "generates correct number of points" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 100.0)
      control1 = Elkrb::Geometry::Point.new(x: 30.0, y: 0.0)
      control2 = Elkrb::Geometry::Point.new(x: 70.0, y: 100.0)

      points = described_class.calculate_curve(
        start_point,
        end_point,
        control1,
        control2,
        20,
      )

      expect(points.length).to eq(20)
    end

    it "starts at start_point" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 100.0)
      control1 = Elkrb::Geometry::Point.new(x: 30.0, y: 0.0)
      control2 = Elkrb::Geometry::Point.new(x: 70.0, y: 100.0)

      points = described_class.calculate_curve(
        start_point,
        end_point,
        control1,
        control2,
        20,
      )

      expect(points.first.x).to eq(0.0)
      expect(points.first.y).to eq(0.0)
    end

    it "ends at end_point" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 100.0)
      control1 = Elkrb::Geometry::Point.new(x: 30.0, y: 0.0)
      control2 = Elkrb::Geometry::Point.new(x: 70.0, y: 100.0)

      points = described_class.calculate_curve(
        start_point,
        end_point,
        control1,
        control2,
        20,
      )

      expect(points.last.x).to eq(100.0)
      expect(points.last.y).to eq(100.0)
    end

    it "generates smooth intermediate points" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 0.0)
      control1 = Elkrb::Geometry::Point.new(x: 30.0, y: 50.0)
      control2 = Elkrb::Geometry::Point.new(x: 70.0, y: 50.0)

      points = described_class.calculate_curve(
        start_point,
        end_point,
        control1,
        control2,
        10,
      )

      # Check that intermediate points have non-zero y values (curve bulges)
      middle_points = points[1..-2]
      expect(middle_points.any? { |p| p.y > 0 }).to be true
    end
  end

  describe ".calculate_control_points" do
    it "returns two control points" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 100.0)

      controls = described_class.calculate_control_points(
        start_point,
        end_point,
        0.5,
      )

      expect(controls.length).to eq(2)
      expect(controls[0]).to be_a(Elkrb::Geometry::Point)
      expect(controls[1]).to be_a(Elkrb::Geometry::Point)
    end

    it "creates perpendicular control points" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 0.0)

      controls = described_class.calculate_control_points(
        start_point,
        end_point,
        0.5,
      )

      # For horizontal line, control points should be offset vertically
      expect(controls[0].y).not_to eq(0.0)
      expect(controls[1].y).not_to eq(0.0)
    end

    it "handles zero curvature" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 100.0)

      controls = described_class.calculate_control_points(
        start_point,
        end_point,
        0.0,
      )

      # With zero curvature, control points should be on the line
      expect(controls[0].x).to be_within(1.0).of(33.33)
      expect(controls[1].x).to be_within(1.0).of(66.67)
    end

    it "handles high curvature" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 0.0)

      controls = described_class.calculate_control_points(
        start_point,
        end_point,
        1.0,
      )

      # With high curvature, control points should be far from the line
      expect(controls[0].y.abs).to be > 40.0
      expect(controls[1].y.abs).to be > 40.0
    end

    it "handles very short distances" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 0.0001, y: 0.0)

      controls = described_class.calculate_control_points(
        start_point,
        end_point,
        0.5,
      )

      # Should return start and end points
      expect(controls[0]).to eq(start_point)
      expect(controls[1]).to eq(end_point)
    end
  end

  describe ".horizontal_control_points" do
    it "creates control points with horizontal offset" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 50.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 100.0)

      controls = described_class.horizontal_control_points(
        start_point,
        end_point,
        0.5,
      )

      # First control keeps start y-coordinate
      expect(controls[0].y).to eq(start_point.y)
      expect(controls[0].x).to be > start_point.x

      # Second control keeps end y-coordinate
      expect(controls[1].y).to eq(end_point.y)
      expect(controls[1].x).to be < end_point.x
    end

    it "respects offset ratio" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 0.0)

      controls1 = described_class.horizontal_control_points(
        start_point,
        end_point,
        0.3,
      )
      controls2 = described_class.horizontal_control_points(
        start_point,
        end_point,
        0.7,
      )

      # Higher ratio should produce more offset
      offset1 = (controls1[0].x - start_point.x).abs
      offset2 = (controls2[0].x - start_point.x).abs
      expect(offset2).to be > offset1
    end
  end

  describe ".vertical_control_points" do
    it "creates control points with vertical offset" do
      start_point = Elkrb::Geometry::Point.new(x: 50.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 100.0, y: 100.0)

      controls = described_class.vertical_control_points(
        start_point,
        end_point,
        0.5,
      )

      # First control keeps start x-coordinate
      expect(controls[0].x).to eq(start_point.x)
      expect(controls[0].y).to be > start_point.y

      # Second control keeps end x-coordinate
      expect(controls[1].x).to eq(end_point.x)
      expect(controls[1].y).to be < end_point.y
    end

    it "respects offset ratio" do
      start_point = Elkrb::Geometry::Point.new(x: 0.0, y: 0.0)
      end_point = Elkrb::Geometry::Point.new(x: 0.0, y: 100.0)

      controls1 = described_class.vertical_control_points(
        start_point,
        end_point,
        0.3,
      )
      controls2 = described_class.vertical_control_points(
        start_point,
        end_point,
        0.7,
      )

      # Higher ratio should produce more offset
      offset1 = (controls1[0].y - start_point.y).abs
      offset2 = (controls2[0].y - start_point.y).abs
      expect(offset2).to be > offset1
    end
  end
end
