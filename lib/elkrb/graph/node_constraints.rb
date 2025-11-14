# frozen_string_literal: true

require "lutaml/model"

module Elkrb
  module Graph
    # Relative offset for positioning
    #
    # Specifies x and y offset from a reference node.
    #
    # @example
    #   offset = RelativeOffset.new(x: 100, y: 50)
    #   # Position 100px right, 50px down from reference
    class RelativeOffset < Lutaml::Model::Serializable
      attribute :x, :float, default: -> { 0.0 }
      attribute :y, :float, default: -> { 0.0 }

      json do
        map "x", to: :x
        map "y", to: :y
      end

      yaml do
        map "x", to: :x
        map "y", to: :y
      end
    end

    # Node positioning constraints
    #
    # Allows precise control over node placement through various constraint types:
    # - Fixed position: Lock node at specific coordinates
    # - Alignment: Align nodes horizontally or vertically
    # - Layer: Force node into specific layer (for layered algorithm)
    # - Relative position: Position relative to another node
    #
    # @example Fixed position constraint
    #   constraints = NodeConstraints.new(fixed_position: true)
    #   node.constraints = constraints
    #   node.x = 100
    #   node.y = 200
    #   # Node won't move during layout
    #
    # @example Alignment constraint
    #   constraints = NodeConstraints.new(
    #     align_group: "databases",
    #     align_direction: "horizontal"
    #   )
    #   # All nodes in "databases" group will align horizontally
    #
    # @example Layer constraint
    #   constraints = NodeConstraints.new(layer: 2)
    #   # Node forced into layer 2 (for layered algorithm)
    #
    # @example Relative position constraint
    #   offset = RelativeOffset.new(x: 150, y: 0)
    #   constraints = NodeConstraints.new(
    #     relative_to: "backend_service",
    #     relative_offset: offset
    #   )
    #   # Node positioned 150px right of backend_service
    class NodeConstraints < Lutaml::Model::Serializable
      attribute :fixed_position, :boolean, default: -> { false }
      attribute :layer, :integer
      attribute :align_group, :string
      attribute :align_direction, :string
      attribute :relative_to, :string
      attribute :relative_offset, RelativeOffset
      attribute :position_priority, :integer, default: -> { 0 }

      json do
        map "fixedPosition", to: :fixed_position
        map "layer", to: :layer
        map "alignGroup", to: :align_group
        map "alignDirection", to: :align_direction
        map "relativeTo", to: :relative_to
        map "relativeOffset", to: :relative_offset
        map "positionPriority", to: :position_priority
      end

      yaml do
        map "fixedPosition", to: :fixed_position
        map "layer", to: :layer
        map "alignGroup", to: :align_group
        map "alignDirection", to: :align_direction
        map "relativeTo", to: :relative_to
        map "relativeOffset", to: :relative_offset
        map "positionPriority", to: :position_priority
      end

      # Valid alignment directions
      HORIZONTAL = "horizontal"
      VERTICAL = "vertical"
      ALIGN_DIRECTIONS = [HORIZONTAL, VERTICAL].freeze

      # Validate alignment direction
      def align_direction=(value)
        if value && !ALIGN_DIRECTIONS.include?(value.to_s.downcase)
          raise ArgumentError,
                "Invalid align_direction: #{value}. " \
                "Must be #{ALIGN_DIRECTIONS.join(' or ')}"
        end
        @align_direction = value&.to_s&.downcase
      end
    end
  end
end
