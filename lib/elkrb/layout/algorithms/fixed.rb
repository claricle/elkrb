# frozen_string_literal: true

require_relative "base_algorithm"

module Elkrb
  module Layout
    module Algorithms
      # Fixed layout algorithm
      #
      # Keeps nodes at their current positions. Only applies padding
      # and calculates graph dimensions based on existing node positions.
      # Useful when node positions are pre-determined or manually set.
      class Fixed < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          # Ensure all nodes have positions
          graph.children.each do |node|
            node.x ||= 0.0
            node.y ||= 0.0
          end

          # Simply apply padding and calculate dimensions
          # Nodes keep their existing x, y positions
          apply_padding(graph)

          graph
        end
      end
    end
  end
end
