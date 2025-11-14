# frozen_string_literal: true

require "lutaml/model"

module Elkrb
  module Graph
    class Port < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float
      attribute :labels, Label, collection: true
      attribute :layout_options, LayoutOptions
      attribute :properties, :hash
      attribute :side, :string, default: -> { "UNDEFINED" }
      attribute :index, :integer, default: -> { -1 }
      attribute :offset, :float, default: -> { 0.0 }

      # Port sides
      NORTH = "NORTH"
      SOUTH = "SOUTH"
      EAST = "EAST"
      WEST = "WEST"
      UNDEFINED = "UNDEFINED"

      SIDES = [NORTH, SOUTH, EAST, WEST, UNDEFINED].freeze

      # Node reference (not serialized)
      attr_accessor :node

      json do
        map "id", to: :id
        map "x", to: :x
        map "y", to: :y
        map "width", to: :width
        map "height", to: :height
        map "labels", to: :labels
        map "layoutOptions", to: :layout_options
        map "properties", to: :properties
        map "side", to: :side
        map "index", to: :index
        map "offset", to: :offset
      end

      yaml do
        map "id", to: :id
        map "x", to: :x
        map "y", to: :y
        map "width", to: :width
        map "height", to: :height
        map "labels", to: :labels
        map "layout_options", to: :layout_options
        map "properties", to: :properties
        map "side", to: :side
        map "index", to: :index
        map "offset", to: :offset
      end

      # Validate and set port side
      #
      # @param value [String] The port side (NORTH, SOUTH, EAST, WEST, UNDEFINED)
      # @raise [ArgumentError] If the side value is invalid
      def side=(value)
        return if value.nil?

        normalized = value.to_s.upcase
        unless SIDES.include?(normalized)
          raise ArgumentError,
                "Invalid port side: #{value}. Must be one of #{SIDES.join(', ')}"
        end
        @side = normalized
      end

      # Detect port side from position relative to node
      #
      # This method analyzes the port's position (x, y) relative to the node's
      # dimensions to determine which side of the node the port is closest to.
      #
      # @param node_width [Float] Width of the parent node
      # @param node_height [Float] Height of the parent node
      # @return [String] The detected side (NORTH, SOUTH, EAST, WEST, UNDEFINED)
      def detect_side(node_width, node_height)
        return UNDEFINED if x.nil? || y.nil? || node_width.nil? || node_height.nil?
        return UNDEFINED if node_width <= 0 || node_height <= 0

        # Calculate relative position (0.0 to 1.0)
        rel_x = x / node_width.to_f
        rel_y = y / node_height.to_f

        # Calculate distance to each side
        distances = {
          NORTH => rel_y,           # Distance from top
          SOUTH => 1.0 - rel_y,     # Distance from bottom
          WEST => rel_x,            # Distance from left
          EAST => 1.0 - rel_x, # Distance from right
        }

        # Return the side with minimum distance
        distances.min_by { |_, dist| dist }.first
      end
    end
  end
end
