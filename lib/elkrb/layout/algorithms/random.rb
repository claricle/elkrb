# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../java_random"
require_relative "../node_index"

module Elkrb
  module Layout
    module Algorithms
      # Random layout algorithm
      #
      # Places nodes at random positions within a bounded area, following
      # Java ELK's RandomLayoutProvider draw for draw: for one seed the node
      # positions and edge bend points are the ones Java ELK produces. That
      # includes its quirks, which are kept on purpose:
      # - an edge's start and end are both placed on its SOURCE node
      #   (right side, bottom side), never on the target;
      # - the graph size adds the padding twice.
      class Random < BaseAlgorithm
        # Java ELK's own defaults for this algorithm; the registry's are the
        # general ones.
        DEFAULT_SPACING = 15.0
        DEFAULT_PADDING = { left: 15.0, right: 15.0, top: 15.0,
                            bottom: 15.0 }.freeze
        # Bend points scatter by this share of the start-to-end distance.
        # The value is the float32 nearest 0.2, as in Java ELK.
        BEND_SCATTER = 0.20000000298023224

        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          @random = JavaRandom.new(option("elk.randomSeed").to_i)
          @pad = random_padding
          width, height = area_size(graph)

          graph.children.each do |node|
            node.x = @pad[:left] + spread(width - node_width(node))
            node.y = @pad[:top] + spread(height - node_height(node))
          end

          @bounds = [width + @pad[:left] + @pad[:right],
                     height + @pad[:top] + @pad[:bottom]]
          graph.width = @bounds[0] + @pad[:left] + @pad[:right]
          graph.height = @bounds[1] + @pad[:top] + @pad[:bottom]
          graph
        end

        private

        def spread(room)
          @random.next_double * room
        end

        def random_padding
          given = option("elk.padding", default: nil)
          given ? given.to_h : DEFAULT_PADDING
        end

        # Java ELK sizes the area from the node areas plus a spacing term per
        # node and edge, then stretches it to the aspect ratio.
        def area_size(graph)
          spacing = option("elk.spacing.nodeNode",
                           default: DEFAULT_SPACING).to_f
          aspect = option("elk.aspectRatio").to_f
          index = NodeIndex.build(graph)
          node_area = graph.children.sum { |n| node_width(n) * node_height(n) }
          edge_count = 1 + edges_by_source(graph, index).values.sum(&:size)
          side = Math.sqrt(node_area + (2 * spacing * spacing * edge_count *
                                        graph.children.size))
          [[side * aspect, graph.children.map { |n| node_width(n) }.max].max,
           [side / aspect, graph.children.map { |n| node_height(n) }.max].max]
        end

        def node_width(node)
          node.width || 0.0
        end

        def node_height(node)
          node.height || 0.0
        end

        # Edges whose source is a node of this level, keyed by that node.
        def edges_by_source(graph, index)
          (graph.edges || []).each_with_object({}) do |edge, grouped|
            source = index.endpoint_nodes(edge.sources).first
            (grouped[source.id] ||= []) << edge if source
          end
        end

        # Edges are scattered after the nodes, from the same random stream,
        # node by node.
        def apply_edge_routing(graph)
          return unless @random

          index = NodeIndex.build(graph)
          grouped = edges_by_source(graph, index)
          graph.children.each do |node|
            (grouped[node.id] || []).each do |edge|
              edge.container ||= graph.id
              next unless same_level?(edge, index)

              scatter_edge(edge, node)
            end
          end
        end

        def same_level?(edge, index)
          ids = Array(edge.sources) + Array(edge.targets)
          ids.all? { |id| index.node(id) }
        end

        def scatter_edge(edge, node)
          half_w = node_width(node) / 2.0
          half_h = node_height(node) / 2.0
          center_x = node.x + half_w
          center_y = node.y + half_h
          inside = half_w.positive? && half_h.positive?
          start = [inside ? center_x + half_w : center_x, center_y]
          finish = [center_x, inside ? center_y + half_h : center_y]

          section = Graph::EdgeSection.new(id: "#{edge.id}_s0")
          section.start_point = point(*start)
          section.end_point = point(*finish)
          section.bend_points = bend_points(start, finish)
          edge.sections = [section]
        end

        # Java ELK draws the bend count from the source and target node
        # being the same node, so there is always one more than nextInt(5).
        def bend_points(start, finish)
          count = @random.next_int(5) + 1
          dx = finish[0] - start[0]
          dy = finish[1] - start[1]
          scatter = Math.sqrt((dx * dx) + (dy * dy)) * BEND_SCATTER
          x, y = start
          Array.new(count) do
            x += dx / (count + 1)
            y += dy / (count + 1)
            point(scattered(x, scatter, @bounds[0]),
                  scattered(y, scatter, @bounds[1]))
          end
        end

        def scattered(coordinate, scatter, limit)
          value = coordinate + (@random.next_float * scatter) - (scatter / 2)
          return 1.0 if value.negative?

          value > limit ? limit - 1.0 : value
        end

        def point(horizontal, vertical)
          Geometry::Point.new(x: horizontal, y: vertical)
        end
      end
    end
  end
end
