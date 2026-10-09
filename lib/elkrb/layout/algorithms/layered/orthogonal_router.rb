# frozen_string_literal: true

require_relative "port_order"
require_relative "port_spread"
require_relative "orthogonal/gap_solver"

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Orthogonal routes for the edges between adjacent layers. Each gap
        # between two layers holds the perpendicular runs of its edges, one
        # per routing slot; an edge leaves the side of its node that faces
        # the next layer, runs to its slot, along it, and on to its target.
        #
        # All geometry is read through callables, so the same router sizes
        # the gaps before nodes have a layer position and routes after.
        #
        # Not ported: junction points, and the segment splitting described
        # on Orthogonal::GapSolver.
        class OrthogonalRouter
          # Cross-axis geometry, each a callable.
          #
          # `start` is where an item starts, `extent` its cross size and
          # `port` the cross size of a port.
          Measure = Struct.new(:start, :extent, :port, keyword_init: true)

          # Distance between neighbouring routing slots.
          EDGE_SPACING = 10.0
          # Distance between a layer and its first routing slot.
          EDGE_NODE_SPACING = 10.0
          TOLERANCE = Orthogonal::HyperEdgeSegment::TOLERANCE
          # Node side that faces the next layer, and the side that faces the
          # previous one, per direction.
          FACING_SIDES = {
            "RIGHT" => %w[EAST WEST], "LEFT" => %w[WEST EAST],
            "DOWN" => %w[SOUTH NORTH], "UP" => %w[NORTH SOUTH]
          }.freeze

          # @param layers [Array<Array>] nodes and DummySlots per layer
          # @param port_order [PortOrder]
          # @param index [NodeIndex] resolves edge endpoints to nodes
          # @param direction [String] RIGHT, LEFT, DOWN or UP
          # @param measure [Measure] cross-axis geometry
          def initialize(layers, port_order, index, direction:, measure:)
            @layers = layers
            @port_order = port_order
            @index = index
            @facing = FACING_SIDES.fetch(direction)
            @vertical = %w[DOWN UP].include?(direction)
            @sign = %w[LEFT UP].include?(direction) ? -1 : 1
            @measure = measure
            @items = layers.flatten.to_h { |item| [item.id, item] }
            @offsets = spread_offsets
          end

          # Number of routing slots in each gap between two layers.
          def slot_counts
            gaps.map { |segments| Orthogonal::GapSolver.slot_count(segments) }
          end

          # @param along_range [#call] [low, high] of an item on the layer
          #   axis, in final coordinates
          # @return [Hash{Edge=>Array<Array(Float, Float)>}] the points of
          #   each edge that crosses a layer gap, source first; an edge
          #   whose declared port is not on the side facing its neighbour
          #   layer is left out
          def routes(along_range)
            @along_range = along_range
            bends = gap_bends
            grouped_segments.select { |_edge, links| facing?(links) }
              .to_h { |edge, links| [edge, edge_points(edge, links, bends)] }
          end

          private

          def spread_offsets
            sizes = @items.transform_values do |item|
              @measure.extent.call(item)
            end
            PortSpread.offsets(@layers, @port_order, sizes, @measure.port)
          end

          def gaps
            @layers.each_cons(2).map do |layer, _next_layer|
              ports = layer.flat_map do |item|
                @port_order.visual(item.id, :east)
              end
              Orthogonal::GapSolver.new(EDGE_SPACING)
                .solve(ports, method(:cross_of))
            end
          end

          def cross_of(port)
            item = @items.fetch(port.item_id)
            offset = item.respond_to?(:dummy?) ? 0.0 : @offsets.fetch(port)
            @measure.start.call(item) + offset
          end

          # Bend points per edge, per gap: [[along, cross], [along, cross]].
          def gap_bends
            bends = {}.compare_by_identity
            pairs = @layers.each_cons(2).zip(gaps)
            pairs.each_with_index do |(pair, segments), gap|
              start = layer_high(pair.first) + EDGE_NODE_SPACING
              segments.each { |segment| place(segment, start, gap, bends) }
            end
            bends
          end

          def place(segment, start, gap, bends)
            return if segment.straight?

            along = start + (segment.slot * EDGE_SPACING)
            source_links(segment).each do |link|
              add_bend(link, along, gap, bends)
            end
          end

          def source_links(segment)
            segment.ports.select { |port| port.side == :east }
              .flat_map(&:segments)
          end

          def add_bend(link, along, gap, bends)
            from = cross_of(link.from_port)
            to = cross_of(link.to_port)
            return if (from - to).abs <= TOLERANCE

            (bends[link.edge] ||= {})[gap] = [[along, from], [along, to]]
          end

          def grouped_segments
            groups = {}.compare_by_identity
            @port_order.segments.each do |link|
              (groups[link.edge] ||= []) << link
            end
            groups.transform_values do |links|
              links.sort_by { |link| layer_index(link.from_port.item_id) }
            end
          end

          def facing?(links)
            links.all? do |link|
              port_faces?(link.from_port, @facing.first) &&
                port_faces?(link.to_port, @facing.last)
            end
          end

          def port_faces?(port, side)
            port.declared.nil? || port.declared.side == side
          end

          def layer_index(item_id)
            @layer_index ||= index_layers
            @layer_index.fetch(item_id)
          end

          def index_layers
            map = {}
            @layers.each_with_index do |layer, i|
              layer.each { |item| map[item.id] = i }
            end
            map
          end

          def edge_points(edge, links, bends)
            first = links.first.from_port
            points = [anchor(first, :high), *gap_points(edge, links, bends),
                      anchor(links.last.to_port, :low)]
            points.map! { |along, cross| real_point(along, cross) }
            forward?(edge, first) ? points : points.reverse
          end

          def gap_points(edge, links, bends)
            links.flat_map do |link|
              bends.dig(edge, layer_index(link.from_port.item_id)) || []
            end
          end

          def forward?(edge, first_port)
            @index.node(edge.sources.first)&.id == first_port.item_id
          end

          # The point where an edge meets a port: on the item's border, or
          # beyond it for a declared port.
          def anchor(port, side)
            item = @items.fetch(port.item_id)
            low, high = abstract_range(item)
            reach = port.declared ? declared_extent(port.declared) : 0.0
            along = side == :high ? high + reach : low - reach
            [along, cross_of(port)]
          end

          def declared_extent(declared)
            (declared.public_send(@vertical ? :height : :width) || 0).to_f
          end

          def abstract_range(item)
            low, high = @along_range.call(item)
            @sign.positive? ? [low, high] : [-high, -low]
          end

          # The far edge of a layer, port overhang included.
          def layer_high(layer)
            return 0.0 if layer.empty?

            layer.map do |item|
              declared = @port_order.visual(item.id, :east)
                .filter_map(&:declared)
              reach = declared.map { |d| declared_extent(d) }.max || 0.0
              abstract_range(item).last + reach
            end.max
          end

          def real_point(along, cross)
            real = @sign * along
            @vertical ? [cross, real] : [real, cross]
          end
        end
      end
    end
  end
end
