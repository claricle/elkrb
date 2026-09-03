# frozen_string_literal: true

require "lutaml/model"
require_relative "../geometry/point"
require_relative "read_only_mapping"

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
      attribute :incoming_sections, :string, collection: true
      attribute :outgoing_sections, :string, collection: true

      key_value do
        map "id", to: :id
        map "startPoint", to: :start_point
        map "endPoint", to: :end_point
        map "bendPoints", to: :bend_points
        map "incomingShape", to: :incoming_shape
        map "outgoingShape", to: :outgoing_shape
        map "incomingSections", to: :incoming_sections
        map "outgoingSections", to: :outgoing_sections
      end

      yaml do
        map "id", to: :id
        map "start_point", to: :start_point
        map "end_point", to: :end_point
        map "bend_points", to: :bend_points
        map "incoming_shape", to: :incoming_shape
        map "outgoing_shape", to: :outgoing_shape
        map "incoming_sections", to: :incoming_sections
        map "outgoing_sections", to: :outgoing_sections
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
      include ReadOnlyMapping

      attribute :id, :string
      attribute :sources, :string, collection: true
      attribute :targets, :string, collection: true
      attribute :labels, Label, collection: true
      attribute :sections, EdgeSection, collection: true
      attribute :layout_options, :hash
      attribute :properties, :hash
      attribute :junction_points, Geometry::Point, collection: true
      attribute :container, :string

      # The legacy elkjs endpoint keys mapped at the end of the block below are
      # read-only, and they reach every key-value format -- JSON, Hash, TOML,
      # JSONL, YAMLS -- but NOT YAML, which declares its own block after it.
      # Precedence: a non-empty sources/targets wins, an explicit [] counts as
      # absent, and a NONBLANK sourcePort precedes source (in ELK JSON the port
      # id IS the endpoint) by declaration order rather than key order.
      # Blank endpoint values are ignored by the hooks below, so a real source
      # or target wins there; targetPort and target behave the same way.
      #
      # Do NOT "simplify" the pairs into a second `map "source", to: :sources`:
      # a plain rule fires even when its key is absent, clobbering sources with
      # nil, and emits both spellings on write.
      key_value do
        map "id", to: :id
        map "sources", to: :sources
        map "targets", to: :targets
        map "labels", to: :labels
        map "sections", to: :sections
        map "layoutOptions", to: :layout_options
        map "properties", to: :properties
        map "junctionPoints", to: :junction_points
        map "container", to: :container

        # Read-only legacy keys; see the note above the block. Order matters.
        map "sourcePort", with: { from: :merge_legacy_source,
                                  to: :omit_from_output }
        map "source", with: { from: :merge_legacy_source,
                              to: :omit_from_output }
        map "targetPort", with: { from: :merge_legacy_target,
                                  to: :omit_from_output }
        map "target", with: { from: :merge_legacy_target,
                              to: :omit_from_output }
      end

      yaml do
        map "id", to: :id
        map "sources", to: :sources
        map "targets", to: :targets
        map "labels", to: :labels
        map "sections", to: :sections
        map "layout_options", to: :layout_options
        map "properties", to: :properties
        map "junction_points", to: :junction_points
        map "container", to: :container
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

      # Serialization hooks for the legacy endpoint keys above. Public because
      # lutaml invokes them with `public_send`; not part of the supported API.
      #
      # @api private
      def merge_legacy_source(model, value)
        return unless Array(model.sources).empty?

        model.sources = reject_blank_endpoints(value)
      end

      # @api private
      def merge_legacy_target(model, value)
        return unless Array(model.targets).empty?

        model.targets = reject_blank_endpoints(value)
      end

      private

      def reject_blank_endpoints(value)
        Array(value).reject { |endpoint| endpoint.to_s.empty? }
      end
    end
  end
end
