# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../node_index"

module Elkrb
  module Layout
    module Algorithms
      # Radial layout algorithm
      #
      # Arranges nodes in a circular/radial pattern around a center point.
      class Radial < BaseAlgorithm
        def layout_flat(graph, _options = {})
          return graph if graph.children.nil? || graph.children.empty?

          if graph.children.size == 1
            centre(graph.children.first)
            apply_padding(graph)
            return graph
          end

          rings = rings(graph)
          centre(rings.fetch(0).first)
          place_rings(rings)

          apply_padding(graph)

          graph
        end

        private

        def rings(graph)
          index = NodeIndex.build(graph)
          adjacent, incoming = edge_tree(graph, index)
          root = radial_root(graph, incoming)
          depths = breadth_first_depths(root, adjacent)
          assign_unreached(graph.children, depths)

          graph.children.group_by { |node| depths.fetch(node.id) }
        end

        def edge_tree(graph, index)
          adjacent = Hash.new { |hash, key| hash[key] = [] }
          incoming = Hash.new(0)

          (graph.edges || []).each do |edge|
            edge_connections(edge, index).each do |source, target|
              adjacent[source.id] << target
              incoming[target.id] += 1
            end
          end
          adjacent.each_value { |nodes| nodes.uniq!(&:id) }
          [adjacent, incoming]
        end

        def edge_connections(edge, index)
          sources = index.endpoint_nodes(edge.sources)
          targets = index.endpoint_nodes(edge.targets)
          sources.product(targets).reject do |source, target|
            source.id == target.id
          end
        end

        def radial_root(graph, incoming)
          return graph.children.first if option(
            "elk.radial.centerOnRoot", default: false
          )

          graph.children.find { |node| incoming[node.id].zero? } ||
            graph.children.first
        end

        def breadth_first_depths(root, adjacent)
          depths = { root.id => 0 }
          queue = [root]

          until queue.empty?
            node = queue.shift
            adjacent[node.id].each do |child|
              next if depths.key?(child.id)

              depths[child.id] = depths.fetch(node.id) + 1
              queue << child
            end
          end
          depths
        end

        def assign_unreached(nodes, depths)
          outer = depths.values.max || 0
          nodes.each do |node|
            next if depths.key?(node.id)

            depths[node.id] = outer + 1
          end
        end

        def centre(node)
          node.x = -(node.width || 0.0) / 2.0
          node.y = -(node.height || 0.0) / 2.0
        end

        def place_rings(rings)
          placed = rings.fetch(0).dup
          base = option(
            "elk.radial.radius", default: automatic_radius(rings)
          ).to_f

          rings.keys.sort.drop(1).each do |depth|
            nodes = rings.fetch(depth)
            radius = base * depth
            radius = grow_until_separate(nodes, placed, radius)
            position_ring(nodes, radius)
            placed.concat(nodes)
          end
        end

        def automatic_radius(rings)
          extent = rings.values.flatten.map do |node|
            [node.width || 0.0, node.height || 0.0].max
          end.max || 0.0
          extent * Math.sqrt(2.0)
        end

        def grow_until_separate(nodes, placed, radius)
          loop do
            position_ring(nodes, radius)
            return radius unless overlaps?(nodes, placed)

            radius += [node_spacing, 1.0].max
          end
        end

        def position_ring(nodes, radius)
          step = (2 * Math::PI) / nodes.size
          offset = step / 2.0
          nodes.each_with_index do |node, index|
            angle = (index * step) + offset
            node.x = (radius * Math.cos(angle)) - ((node.width || 0.0) / 2.0)
            node.y = (radius * Math.sin(angle)) - ((node.height || 0.0) / 2.0)
          end
        end

        def overlaps?(ring, placed)
          candidates = ring.combination(2).to_a
          candidates.concat(ring.product(placed))
          candidates.any? { |left, right| overlap?(left, right) }
        end

        def overlap?(left, right)
          horizontal_overlap?(left, right) && vertical_overlap?(left, right)
        end

        def horizontal_overlap?(left, right)
          left.x < right.x + node_width(right) &&
            right.x < left.x + node_width(left)
        end

        def vertical_overlap?(left, right)
          left.y < right.y + node_height(right) &&
            right.y < left.y + node_height(left)
        end

        # The shared router starts node-to-node edges at node centres. Radial
        # edges are straight rays, so clip each end to its node rectangle.
        def apply_edge_routing(graph)
          super
          index = NodeIndex.build(graph)

          (graph.edges || []).each do |edge|
            source = index.endpoint_nodes(edge.sources).first
            target = index.endpoint_nodes(edge.targets).first
            next unless source && target && source.id != target.id

            section = reset_section(edge, graph)
            section.start_point = radial_endpoint_position(
              edge.sources.first, source, target, :outgoing
            )
            section.end_point = radial_endpoint_position(
              edge.targets.first, target, source, :incoming
            )
            section.bend_points = []
            edge.container = graph.id
          end
        end

        def radial_endpoint_position(endpoint_id, node, other, direction)
          return border_towards(node, other) unless
            find_port_by_id(endpoint_id, node)

          get_port_position(endpoint_id, node, direction)
        end

        def border_towards(node, other)
          center_x = node.x + (node_width(node) / 2.0)
          center_y = node.y + (node_height(node) / 2.0)
          other_x = other.x + (node_width(other) / 2.0)
          other_y = other.y + (node_height(other) / 2.0)
          delta_x = other_x - center_x
          delta_y = other_y - center_y
          scales = []
          scales << (node_width(node) / 2.0 / delta_x.abs) unless delta_x.zero?
          scales << (node_height(node) / 2.0 / delta_y.abs) unless delta_y.zero?
          scale = scales.min || 0.0

          Geometry::Point.new(
            x: center_x + (delta_x * scale),
            y: center_y + (delta_y * scale),
          )
        end

        def node_width(node)
          node.width || 0.0
        end

        def node_height(node)
          node.height || 0.0
        end
      end
    end
  end
end
