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
      attribute :layout_options, :hash

      key_value do
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

      # Normalizes a Symbol key however the options arrive — a constructor,
      # a plain setter, or lutaml's own deserialization, which routes through
      # here too. This is the single normalization point: a :hash-typed
      # attribute otherwise stores a raw, unnormalized Hash.
      def layout_options=(value)
        value_set_for(:layout_options)
        attr = self.class.attributes(lutaml_register)[:layout_options]
        cast = attr.cast_value(DeepStringifyKeys.call(value), lutaml_register)
        instance_variable_set(:@layout_options, LayoutOptions.wrap(cast))
      end
    end
  end
end
