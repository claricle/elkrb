# frozen_string_literal: true

require "lutaml/model"

module Elkrb
  module Graph
    class Label < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :text, :string
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float
      attribute :layout_options, LayoutOptions

      json do
        map "id", to: :id
        map "text", to: :text
        map "x", to: :x
        map "y", to: :y
        map "width", to: :width
        map "height", to: :height
        map "layoutOptions", to: :layout_options
      end

      yaml do
        map "id", to: :id
        map "text", to: :text
        map "x", to: :x
        map "y", to: :y
        map "width", to: :width
        map "height", to: :height
        map "layout_options", to: :layout_options
      end

      def initialize(**attributes)
        super
        @x ||= 0.0
        @y ||= 0.0
        @width ||= 0.0
        @height ||= 0.0
      end
    end
  end
end
