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
      attribute :children, Node, collection: true
      attribute :edges, Edge, collection: true
      attribute :layout_options, LayoutOptions
      attribute :properties, :hash

      json do
        map "id", to: :id
        map "x", to: :x
        map "y", to: :y
        map "width", to: :width
        map "height", to: :height
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
        @children ||= []
        @edges ||= []
        @properties ||= {}
        @layout_options ||= LayoutOptions.new
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
        edges = @edges.dup
        @children.each do |child|
          edges.concat(child.edges) if child.respond_to?(:edges)
          next unless child.respond_to?(:children)

          child.children.each do |grandchild|
            edges.concat(grandchild.all_edges) if
              grandchild.respond_to?(:all_edges)
          end
        end
        edges
      end

      def hierarchical?
        @children.any?(&:hierarchical?)
      end
    end
  end
end
