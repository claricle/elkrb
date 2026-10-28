# frozen_string_literal: true

require "lutaml/model"

module Elkrb
  module Graph
    class Graph < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float
      attribute :labels, Label, collection: true
      attribute :ports, Port, collection: true
      attribute :children, Node, collection: true
      attribute :edges, Edge, collection: true
      attribute :layout_options, :hash
      attribute :properties, :hash

      key_value do
        map "id", to: :id
        map "x", to: :x
        map "y", to: :y
        map "width", to: :width
        map "height", to: :height
        map "labels", to: :labels
        map "ports", to: :ports
        map "children", to: :children
        map "edges", to: :edges
        map "layoutOptions", to: :layout_options
        map "properties", to: :properties
      end

      yaml do
        map "id", to: :id
        map "x", to: :x
        map "y", to: :y
        map "width", to: :width
        map "height", to: :height
        map "labels", to: :labels
        map "ports", to: :ports
        map "children", to: :children
        map "edges", to: :edges
        map "layout_options", to: :layout_options
        map "properties", to: :properties
      end

      def initialize(**attributes)
        super
        @id ||= "root"
        @x ||= 0.0
        @y ||= 0.0
        @width ||= 0.0
        @height ||= 0.0
        set_collection_defaults
        @properties ||= {}
        @layout_options ||= {}
      end

      def set_collection_defaults
        @labels = [] if @labels.nil?
        @ports = [] if @ports.nil?
        @children = [] if @children.nil?
        @edges = [] if @edges.nil?
      end
      private :set_collection_defaults

      # Normalizes a Symbol key however the options arrive — a constructor,
      # a plain setter, or lutaml's own deserialization, which routes through
      # here too. This is the single normalization point: a :hash-typed
      # attribute otherwise stores a raw, unnormalized Hash.
      def layout_options=(value)
        value_set_for(:layout_options)
        attr = self.class.attributes(lutaml_register)[:layout_options]
        cast = attr.cast_value(DeepStringifyKeys.call(value), lutaml_register)
        instance_variable_set(:@layout_options, NormalizeOptionKeys.call(cast))
      end

      def find_node(node_id)
        @children.each do |child|
          found = child.find_node(node_id)
          return found if found
        end
        nil
      end

      def all_nodes
        nodes = []
        @children.each do |child|
          nodes.concat(child.all_nodes)
        end
        nodes
      end

      def all_edges
        edges = (@edges || []).dup
        (@children || []).each do |child|
          edges.concat(descendant_edges(child))
        end
        edges
      end

      def hierarchical?
        (@children || []).any?(&:hierarchical?)
      end

      private

      def descendant_edges(node)
        edges = (node.edges || []).dup
        (node.children || []).each do |child|
          edges.concat(descendant_edges(child))
        end
        edges
      end
    end
  end
end
