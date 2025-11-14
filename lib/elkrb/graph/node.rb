# frozen_string_literal: true

require "lutaml/model"
require_relative "node_constraints"

module Elkrb
  module Graph
    class Node < Lutaml::Model::Serializable
      attribute :id, :string
      attribute :x, :float
      attribute :y, :float
      attribute :width, :float
      attribute :height, :float
      attribute :labels, Label, collection: true
      attribute :ports, Port, collection: true
      attribute :children, Node, collection: true
      attribute :edges, Edge, collection: true
      attribute :layout_options, LayoutOptions
      attribute :constraints, NodeConstraints
      attribute :properties, :hash

      json do
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
        map "constraints", to: :constraints
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
        map "constraints", to: :constraints
        map "properties", to: :properties
      end

      def hierarchical?
        @children && !@children.empty?
      end

      def find_node(node_id)
        return self if @id == node_id

        return nil unless @children

        @children.each do |child|
          found = child.find_node(node_id)
          return found if found
        end
        nil
      end

      def all_nodes
        nodes = [self]
        return nodes unless @children

        @children.each do |child|
          nodes.concat(child.all_nodes)
        end
        nodes
      end
    end
  end
end
