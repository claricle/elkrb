# frozen_string_literal: true

require_relative "crossing_minimizer"

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Connected components of one hierarchy level, and the row packing
        # that puts the laid-out components back side by side.
        module Components
          # One component after its own layout.
          Part = Struct.new(:graph, :layers, :index, :port_order, :slots)

          # The crossing minimizer of one component. ELK counts every node of
          # the level, not the component's own, against the greedy-switch
          # limit.
          class Minimizer < CrossingMinimizer
            def initialize(graph, layers, index, resolver, level_size)
              super(graph, layers, index, resolver)
              @node_count = level_size
            end
          end

          # Splits a level into one graph per connected component: nodes in
          # input order, components in order of their first node, each
          # graph-owned edge with the component its endpoints are in.
          class Splitter
            # @param graph [Graph::Graph] the level being laid out
            # @param index [NodeIndex] the level's index
            def initialize(graph, index)
              @graph = graph
              @index = index
            end

            # @return [Array<Graph::Graph>]
            def graphs
              groups.map do |nodes|
                Graph::Graph.new(
                  id: @graph.id, children: nodes, edges: edges_of(nodes),
                  layout_options: @graph.layout_options
                )
              end
            end

            private

            def groups
              seen = {}
              @graph.children.filter_map do |node|
                next if seen[node.id]

                members = reach(node.id, seen)
                @graph.children.select { |other| members.include?(other.id) }
              end
            end

            def reach(start, seen)
              found = []
              pending = [start]
              until pending.empty?
                id = pending.pop
                next if seen[id]

                seen[id] = true
                found << id
                pending.concat(neighbours[id])
              end
              found
            end

            def neighbours
              @neighbours ||= Hash.new { |map, id| map[id] = [] }.tap do |map|
                @index.edges.each do |edge|
                  ids = owner_ids(edge)
                  ids.each { |id| map[id].concat(ids) }
                end
              end
            end

            def owner_ids(edge)
              @index.endpoint_owners(edge.sources + edge.targets).map(&:id)
            end

            def edges_of(nodes)
              ids = nodes.map(&:id)
              @graph.edges.to_a.select do |edge|
                ids.include?(owner_ids(edge).first)
              end
            end
          end

          # Places boxes in rows the way ELK's simple row placer does: the
          # smallest box first, a new row once the next box would pass the
          # larger of the widest box and sqrt(total area) * aspect ratio.
          class RowPacker
            # The next free spot in the current row.
            Cursor = Struct.new(:x, :y, :tallest) do
              # This cursor, or the start of the next row when a box of
              # `width` would pass the limit.
              def fit(width, limit, spacing)
                return self unless x + width > limit

                Cursor.new(0.0, y + tallest + spacing, 0.0)
              end

              def corner
                [x, y]
              end

              def past(width, height, spacing)
                Cursor.new(x + width + spacing, y, [tallest, height].max)
              end
            end
            private_constant :Cursor

            # @param sizes [Array<Array(Float, Float)>] width and height of
            #   each box, without padding
            # @param spacing [Float] gap between boxes and between rows
            # @param aspect_ratio [Float]
            def initialize(sizes, spacing:, aspect_ratio:)
              @sizes = sizes
              @spacing = spacing
              @aspect_ratio = aspect_ratio
            end

            # @return [Array<Array(Float, Float)>] the top-left of each box,
            #   in the order the sizes were given
            def offsets
              placed = {}
              cursor = Cursor.new(0.0, 0.0, 0.0)
              order.each do |box|
                width, height = @sizes[box]
                cursor = cursor.fit(width, limit, @spacing)
                placed[box] = cursor.corner
                cursor = cursor.past(width, height, @spacing)
              end
              placed.sort.map(&:last)
            end

            # @param offsets [Array<Array(Float, Float)>] from #offsets
            # @return [Array(Float, Float)] the packed width and height
            def size(offsets)
              boxes = @sizes.zip(offsets)
              [[@spacing, *boxes.map { |(w, _), (x, _)| x + w }].max,
               boxes.map { |(_, h), (_, y)| y + h }.max]
            end

            private

            def order
              @sizes.each_index.sort_by { |box| [@sizes[box].inject(:*), box] }
            end

            # ELK takes the square root in single precision.
            def limit
              @limit ||= row_limit
            end

            def row_limit
              area = @sizes.sum { |width, height| width * height }
              root = [Math.sqrt(area)].pack("f").unpack1("f")
              [@sizes.map(&:first).max, root * @aspect_ratio].max
            end
          end
        end
      end
    end
  end
end
