# frozen_string_literal: true

require_relative "base_algorithm"

module Elkrb
  module Layout
    module Algorithms
      # Random layout algorithm
      #
      # Places nodes at random positions within a bounded area.
      # Useful for initial layouts or testing.
      class Random < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          # Get configuration
          aspect_ratio = option("aspect_ratio", 1.6).to_f
          spacing = node_spacing

          # Calculate total area needed
          total_area = graph.children.sum do |node|
            (node.width + spacing) * (node.height + spacing)
          end

          # Calculate bounds
          width = Math.sqrt(total_area * aspect_ratio)
          height = width / aspect_ratio

          # Position nodes randomly
          graph.children.each do |node|
            node.x = rand * (width - node.width)
            node.y = rand * (height - node.height)
          end

          # Apply padding and set graph dimensions
          apply_padding(graph)

          graph
        end
      end
    end
  end
end
