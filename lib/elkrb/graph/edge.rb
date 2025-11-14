# frozen_string_literal: true

require "lutaml/model"
require_relative "../geometry/point"

module Elkrb
  module Graph
    # Represents a section of an edge with routing information
    class EdgeSection < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :start_point, Geometry::Point
      attribute :end_point, Geometry::Point
      attribute :bend_points, Geometry::Point, collection: true
      attribute :incoming_shape, :string
      attribute :outgoing_shape, :string

      json do
        map "id", to: :id
        map "startPoint", to: :start_point
        map "endPoint", to: :end_point
        map "bendPoints", to: :bend_points
        map "incomingShape", to: :incoming_shape
        map "outgoingShape", to: :outgoing_shape
      end

      yaml do
        map "id", to: :id
        map "start_point", to: :start_point
        map "end_point", to: :end_point
        map "bend_points", to: :bend_points
        map "incoming_shape", to: :incoming_shape
        map "outgoing_shape", to: :outgoing_shape
      end

      def initialize(**attributes)
        super
        @bend_points ||= []
      end

      # Add a bend point to this section
      def add_bend_point(x, y)
        @bend_points ||= []
        @bend_points << Geometry::Point.new(x: x, y: y)
      end

      # Get total length of this section
      def length
        return 0.0 if !start_point || !end_point

        total = 0.0
        points = [start_point] + (bend_points || []) + [end_point]

        (0...(points.length - 1)).each do |i|
          p1 = points[i]
          p2 = points[i + 1]
          dx = p2.x - p1.x
          dy = p2.y - p1.y
          total += Math.sqrt((dx * dx) + (dy * dy))
        end

        total
      end
    end

    class Edge < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :sources, :string, collection: true
      attribute :targets, :string, collection: true
      attribute :labels, Label, collection: true
      attribute :sections, EdgeSection, collection: true
      attribute :layout_options, LayoutOptions
      attribute :properties, :hash

      json do
        map "id", to: :id
        map "sources", to: :sources
        map "targets", to: :targets
        map "labels", to: :labels
        map "sections", to: :sections
        map "layoutOptions", to: :layout_options
        map "properties", to: :properties
      end

      yaml do
        map "id", to: :id
        map "sources", to: :sources
        map "targets", to: :targets
        map "labels", to: :labels
        map "sections", to: :sections
        map "layout_options", to: :layout_options
        map "properties", to: :properties
      end
    end
  end
end
