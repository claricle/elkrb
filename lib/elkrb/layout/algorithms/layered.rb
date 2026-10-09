# frozen_string_literal: true

require_relative "base_algorithm"
require_relative "../node_index"
require_relative "layered/cycle_breaker"
require_relative "layered/components"
require_relative "layered/crossing_minimizer"
require_relative "layered/layer_assigner"
require_relative "layered/node_placer"
require_relative "layered/orthogonal_router"

module Elkrb
  module Layout
    module Algorithms
      # Layered (Sugiyama) layout algorithm
      #
      # The flagship algorithm for hierarchical graph layout.
      # Implements the Sugiyama framework in phases:
      # 1. Cycle breaking - find the back edges, WITHOUT making the graph
      #    acyclic. The caller's edges are handed back exactly as written;
      #    the reversal is a private orientation the next phase borrows.
      # 2. Layer assignment - assign nodes to horizontal layers, reading
      #    each back edge in its reversed direction
      # 3. Crossing minimization - reorder nodes within assigned layers
      # 4. Node placement - position nodes within layers
      #
      # Ideal for:
      # - UML class diagrams
      # - Call graphs
      # - Data flow diagrams
      # - Organization charts
      # - Any directed acyclic graph
      #
      # The three bang validators below (raise_hyperedge!,
      # raise_missing_endpoint!, validate_simple_edge!) are argument
      # validators, not the dangerous/safe pair MissingSafeMethod expects --
      # same reasoning as GraphvizWrapper's own exemption, see that file's
      # comment. No nested class here to inherit this and need its own reset.
      # rubocop:disable Layout/LineLength
      # :reek:MissingSafeMethod { exclude: [ raise_hyperedge!, raise_missing_endpoint!, validate_simple_edge! ] }
      # rubocop:enable Layout/LineLength
      class LayeredAlgorithm < BaseAlgorithm
        # BaseAlgorithm intentionally skips layout_flat when a deserialized
        # graph omits `children`. Validate that public entry point here so an
        # unsupported edge cannot silently pass through untouched.
        def layout(graph)
          validate_edges(NodeIndex.build(graph)) unless graph.children
          super
        end

        def layout_flat(graph, _options = {})
          @routed_layers = nil
          @parts = []
          @level_size = graph.children.to_a.length
          index = NodeIndex.build(graph)
          validate_edges(index)
          return graph if graph.children.nil? || graph.children.empty?

          @parts = lay_out_components(graph, index)
          @dummy_slots = @parts.flat_map(&:slots)
          @routed_layers = [@parts.flat_map(&:layers), index]
          graph
        end

        private

        # A graph with several connected components is laid out one component
        # at a time and packed afterwards, as ELK does.
        def lay_out_components(graph, index)
          parts = []
          if option("elk.separateConnectedComponents")
            parts = Layered::Components::Splitter.new(graph, index).graphs
          end
          return [lay_out_part(graph, index)] if parts.length < 2

          laid = parts.map { |part| lay_out_part(part, NodeIndex.build(part)) }
          pack_components(graph, laid)
          laid
        end

        def lay_out_part(graph, index)
          layers = assign_layers(graph, index)

          # Phase 3: Minimize crossings within the assigned layers
          layers = minimize_crossings(graph, layers, index)
          @dummy_slots = dummy_slots(layers)

          # Phase 4: Place nodes
          place_nodes(graph, layers, index)

          # Apply padding and set graph dimensions
          apply_padding_with_dummies(graph)
          Layered::Components::Part.new(
            graph, layers, index, @port_order, @dummy_slots
          )
        end

        def pack_components(graph, parts)
          packer = row_packer(parts)
          offsets = packer.offsets
          parts.zip(offsets) { |part, (left, top)| move_part(part, left, top) }
          size_packed(graph, *packer.size(offsets))
        end

        def size_packed(graph, width, height)
          graph.width = width + padding[:left] + padding[:right]
          graph.height = height + padding[:top] + padding[:bottom]
        end

        def row_packer(parts)
          Layered::Components::RowPacker.new(
            parts.map { |part| content_size(part.graph) },
            spacing: option("elk.spacing.componentComponent").to_f,
            aspect_ratio: option("elk.aspectRatio").to_f,
          )
        end

        def content_size(part_graph)
          [part_graph.width - padding[:left] - padding[:right],
           part_graph.height - padding[:top] - padding[:bottom]]
        end

        def move_part(part, shift_x, shift_y)
          [*part.graph.children, *part.slots].each do |item|
            item.x += shift_x
            item.y += shift_y
          end
        end

        def assign_layers(graph, index)
          # Phase 1: Find the back edges
          reversed_edges = Layered::CycleBreaker.new(graph, index).break_cycles

          # Phase 2: Assign layers and insert long-edge dummy slots
          Layered::LayerAssigner.new(
            graph, index, reversed_edges, resolver: @resolver
          ).assign_layers
        end

        def apply_edge_routing(graph)
          super
          routed = route_orthogonal_edges(graph)
          add_long_edge_bends(graph, routed)
        end

        # Replaces the generic route of every edge that crosses a layer gap
        # with the layer-gap route, when its style is ORTHOGONAL.
        #
        # @return [Array<Graph::Edge>] the edges it routed
        def route_orthogonal_edges(graph)
          return [] unless @routed_layers

          routes = orthogonal_routes
          graph.edges.to_a.select do |edge|
            points = routes[edge]
            next false unless points && level_edge?(edge)
            next false unless orthogonal_edge?(graph, edge)

            apply_route(edge, points, graph)
            true
          end
        end

        def orthogonal_routes
          @parts.map { |part| orthogonal_router(part) }
            .map { |router| router.routes(method(:along_range)) }
            .reduce({}, :merge)
        end

        # A cross-hierarchy edge names a nested node; its route is not this
        # level's to draw.
        def level_edge?(edge)
          index = @routed_layers.last
          [edge.sources.first, edge.targets.first].all? { |id| index.node(id) }
        end

        def orthogonal_edge?(graph, edge)
          get_edge_routing_style(graph, edge) == "ORTHOGONAL"
        end

        def apply_route(edge, points, graph)
          section = reset_section(edge, graph)
          start, *bends, finish = points
          section.start_point = point_at(start)
          section.end_point = point_at(finish)
          section.bend_points = []
          bends.each { |x, y| section.add_bend_point(x, y) }
        end

        def point_at(coordinates)
          Geometry::Point.new(x: coordinates[0], y: coordinates[1])
        end

        def orthogonal_router(part)
          Layered::OrthogonalRouter.new(
            part.layers, part.port_order, part.index,
            direction: layer_direction, measure: router_measure
          )
        end

        def router_measure
          Layered::OrthogonalRouter::Measure.new(
            start: method(:cross_start), extent: method(:cross_extent),
            port: method(:port_cross_extent)
          )
        end

        def layer_direction
          direction = option("elk.direction")
          direction == "UNDEFINED" ? "RIGHT" : direction
        end

        def vertical_layers?
          %w[DOWN UP].include?(layer_direction)
        end

        def along_range(item)
          start, size = along_of(item)
          start ||= 0.0
          [start, start + (size || 0.0)]
        end

        def along_of(item)
          vertical_layers? ? [item.y, item.height] : [item.x, item.width]
        end

        def cross_extent(item)
          thickness = Layered::NodePlacer::EDGE_THICKNESS
          return thickness if item.respond_to?(:dummy?)

          (vertical_layers? ? item.width : item.height) || 0
        end

        def cross_start(item)
          start = (vertical_layers? ? item.x : item.y) || 0.0
          return start unless item.respond_to?(:dummy?)

          spare = cross_slot_size(item) - Layered::NodePlacer::EDGE_THICKNESS
          start + (spare / 2.0)
        end

        def cross_slot_size(slot)
          vertical_layers? ? slot.width : slot.height
        end

        def port_cross_extent(port)
          return 0 unless port.declared

          (vertical_layers? ? port.declared.width : port.declared.height) || 0
        end

        def apply_padding_with_dummies(graph)
          shift_x, shift_y = padding_shift(graph)
          shift_dummy_slots(shift_x, shift_y)
          include_long_edges(graph)
        end

        # A long edge's lane can run beyond the nodes; the padding is
        # measured from the lane, not from the nearest node.
        def include_long_edges(graph)
          return if @dummy_slots.empty?

          vertical = %w[DOWN UP].include?(option("elk.direction"))
          before, after = lane_overhang(graph, vertical)
            .map { |amount| [amount, 0].max }
          shift_cross(graph, vertical, before)
          grow_cross(graph, vertical, before + after)
        end

        # How far the lanes reach past the padded content on each end of
        # the cross axis; negative when they stay inside.
        def lane_overhang(graph, vertical)
          low, high = @dummy_slots.map { |slot| lane_centre(slot, vertical) }
            .minmax
          reach = Layered::NodePlacer::EDGE_THICKNESS / 2.0
          start, stop = content_range(graph, vertical)
          [start - (low - reach), high + reach - stop]
        end

        def content_range(graph, vertical)
          lead, trail = padding.values_at(*cross_sides(vertical))
          [lead, (vertical ? graph.width : graph.height) - trail]
        end

        def cross_sides(vertical)
          vertical ? %i[left right] : %i[top bottom]
        end

        def lane_centre(slot, vertical)
          vertical ? slot.x + (slot.width / 2.0) : slot.y + (slot.height / 2.0)
        end

        def shift_cross(graph, vertical, amount)
          items = [*graph.children, *@dummy_slots]
          items.each do |item|
            if vertical
              item.x += amount
            else
              item.y += amount
            end
          end
        end

        def grow_cross(graph, vertical, amount)
          return unless amount.positive?

          if vertical
            graph.width += amount
          else
            graph.height += amount
          end
        end

        def padding_shift(graph)
          first = graph.children.first
          before = first && [first.x, first.y]
          apply_padding(graph)
          return [0.0, 0.0] unless before

          [first.x - before[0], first.y - before[1]]
        end

        def shift_dummy_slots(shift_x, shift_y)
          @dummy_slots.each do |slot|
            slot.x += shift_x
            slot.y += shift_y
          end
        end

        def dummy_slots(layers)
          layers.flatten.select { |item| item.respond_to?(:dummy?) }
        end

        def add_long_edge_bends(graph, routed)
          slots_by_edge = {}.compare_by_identity
          @dummy_slots.to_a.each do |slot|
            (slots_by_edge[slot.edge] ||= []) << slot
          end
          graph.edges.to_a.each do |edge|
            next if routed.any? { |done| done.equal?(edge) }

            add_edge_dummy_bends(edge, slots_by_edge[edge], graph)
          end
        end

        def add_edge_dummy_bends(edge, slots, graph)
          return if slots.nil? || slots.empty? || edge.sections.to_a.empty?

          section = edge.sections.first
          section.bend_points = ordered_dummy_anchors(
            section.start_point, slots, graph
          )
        end

        # A lone dummy is entered and left at its layer's edges; a single
        # bend at its centre would cut across the nodes beside it.
        def ordered_dummy_anchors(start_point, slots, graph)
          return lone_dummy_anchors(start_point, slots.first, graph) if
            slots.length == 1

          ordered = slots.sort_by { |slot| squared_distance(start_point, slot) }
          ordered.each_with_index.map do |slot, index|
            dummy_anchor(slot, graph, anchor_for(index, ordered.length))
          end
        end

        # A reversed edge runs against the layer order, so the anchor nearer
        # its start comes first.
        def lone_dummy_anchors(start_point, slot, graph)
          points = %i[leading trailing].map do |anchor|
            dummy_anchor(slot, graph, anchor)
          end
          points.sort_by do |point|
            ((point.x - start_point.x)**2) + ((point.y - start_point.y)**2)
          end
        end

        def anchor_for(index, length)
          return :leading if index.zero?
          return :trailing if index == length - 1

          :center
        end

        def squared_distance(point, slot)
          ((slot.x + (slot.width / 2.0) - point.x)**2) +
            ((slot.y + (slot.height / 2.0) - point.y)**2)
        end

        def dummy_anchor(slot, graph, anchor)
          direction = resolver.get("elk.direction", graph)
          return dummy_center(slot) if anchor == :center
          return vertical_dummy_anchor(slot, direction, anchor) if
            %w[DOWN UP].include?(direction)

          Geometry::Point.new(
            x: horizontal_anchor(slot, direction, anchor),
            y: slot.y + (slot.height / 2.0),
          )
        end

        def vertical_dummy_anchor(slot, direction, anchor)
          Geometry::Point.new(
            x: slot.x + (slot.width / 2.0),
            y: vertical_anchor(slot, direction, anchor),
          )
        end

        def dummy_center(slot)
          Geometry::Point.new(
            x: slot.x + (slot.width / 2.0),
            y: slot.y + (slot.height / 2.0),
          )
        end

        def horizontal_anchor(slot, direction, anchor)
          leading, trailing = if direction == "LEFT"
                                [slot.x + slot.width, slot.x]
                              else
                                [slot.x, slot.x + slot.width]
                              end
          anchor == :leading ? leading : trailing
        end

        def vertical_anchor(slot, direction, anchor)
          leading, trailing = if direction == "UP"
                                [slot.y + slot.height, slot.y]
                              else
                                [slot.y, slot.y + slot.height]
                              end
          anchor == :leading ? leading : trailing
        end

        def minimize_crossings(graph, layers, index)
          minimizer = Layered::Components::Minimizer.new(
            graph, layers, index, resolver, @level_size
          )
          minimizer.minimize.tap { @port_order = minimizer.port_order }
        end

        def place_nodes(graph, layers, index)
          direction = option("elk.direction")
          direction = "RIGHT" if direction == "UNDEFINED"

          placer = Layered::NodePlacer.new(
            graph, layers,
            direction: direction,
            layer_spacing: option("elk.layered.spacing.nodeNodeBetweenLayers"),
            node_spacing: node_spacing
          )
          placer.index = index
          placer.port_order = @port_order
          placer.orthogonal = get_edge_routing_style(graph) == "ORTHOGONAL"
          placer.place_nodes
        end

        def validate_edges(index)
          index.edges.each do |edge|
            validate_simple_edge!(edge)
          end
        end

        # An id is optional on an edge. An edge without one is ANONYMOUS: it
        # carries no handle, so `edge_label` falls back to its endpoints.
        # `""` counts as no id, and this is the ONE place that decides it.
        def anonymous?(edge)
          edge.id.to_s.empty?
        end

        def validate_simple_edge!(edge)
          sources = edge.sources || []
          targets = edge.targets || []

          raise_missing_endpoint!(edge) if missing_endpoint?(sources, targets)

          return if sources.length == 1 && targets.length == 1

          raise_hyperedge!(edge)
        end

        def missing_endpoint?(sources, targets)
          [sources, targets].any? do |endpoints|
            endpoints.empty? || !endpoint_present?(endpoints.first)
          end
        end

        def endpoint_present?(endpoint)
          !endpoint.nil?
        end

        # An edge id is optional in ELK, so every message below could read
        # "(edge )" with nothing after it. The endpoints are the fallback
        # handle -- not because an edge always has them (the very next
        # method is raised when it does not, and `endpoint_list` answers
        # "(no endpoints)" for that case), but because they are the only
        # other thing a reader can use to find the edge in their input.
        # Keep the three messages using one helper: fixing only some of
        # them makes the rest look deliberate.
        def edge_label(edge)
          # `""` is truthy in Ruby, so a plain `if edge.id` here puts the
          # empty message straight back. `anonymous?` is the single
          # definition of "no id".
          return edge.id unless anonymous?(edge)

          "(none), #{endpoint_list(edge.sources)} -> " \
            "#{endpoint_list(edge.targets)}"
        end

        def endpoint_list(endpoints)
          named = (endpoints || []).compact
          return "(no endpoints)" if named.empty?

          named.map(&:inspect).join(", ")
        end

        def raise_missing_endpoint!(edge)
          raise Elkrb::UnsupportedConfigurationException.new(
            "layered requires non-empty edge endpoints " \
            "(edge #{edge_label(edge)})",
            option: "edge",
            value: edge.id,
          )
        end

        def raise_hyperedge!(edge)
          raise Elkrb::UnsupportedConfigurationException.new(
            "layered does not support hyperedges " \
            "(edge #{edge_label(edge)})",
            option: "edge",
            value: edge.id,
          )
        end
      end
    end
  end
end
