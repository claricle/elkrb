# frozen_string_literal: true

# This file is loadable on its own, so do not rely on another algorithm
# having loaded Ruby's Set first.
# rubocop:disable Lint/RedundantRequireStatement
require "set"
# rubocop:enable Lint/RedundantRequireStatement

require_relative "../../../options/resolver"
require_relative "layer_constraints"

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Assigns nodes to layers using an iterative longest-path pass, then
        # applies layer constraints: `elk.layered.layering.layerConstraint`
        # (FIRST, FIRST_SEPARATE, LAST, LAST_SEPARATE) and
        # `constraints.layer`. A constraint wins over the edges, so an edge
        # may end up pointing against the layer order.
        class LayerAssigner
          attr_reader :layers

          # `reversed_edges` holds the edge OBJECTS CycleBreaker decided to
          # orient backwards, compared by identity. See CycleBreaker for why
          # neither an id nor a plain Set can carry that decision.
          #
          # keep this `compare_by_identity` on the DEFAULT too, even though
          # nothing in this codebase can observe it today: the default is
          # only ever read via #include? and never added to, and an empty
          # Set answers #include? identically whichever comparison strategy
          # it uses -- so no spec can distinguish this from a plain
          # `Set.new` (confirmed by mutating it by hand). It becomes the
          # only thing standing between a dedup bug and a direct caller
          # that relies on the default AND later mutates it in place.
          def initialize(graph, index,
                         reversed_edges = Set.new.compare_by_identity,
                         resolver: Options::Resolver.new)
            @graph = graph
            @resolver = resolver
            @index = index
            @reversed_edges = reversed_edges
            @layers = []
            @node_layers = {}
          end

          def assign_layers
            return [] unless @graph.children

            nodes = @graph.children.to_h { |node| [node.id, node] }
            predecessors = build_predecessors(nodes)
            assign_predecessor_layers(nodes, predecessors)
            apply_layer_constraints(nodes)
            build_layers(nodes)
          end

          def get_layer(node_id)
            @node_layers[node_id]
          end

          private

          # Keep the predecessor order used by the former recursive pass.
          # That order is observable in NodePlacer's same-layer coordinates,
          # so an acyclic graph must not be reordered as a side effect of the
          # iterative implementation.
          def build_predecessors(nodes)
            predecessors = Hash.new { |hash, id| hash[id] = [] }

            @index.edges.each do |edge|
              source_id, target_id = oriented_endpoints(edge)
              next unless usable_edge?(source_id, target_id, nodes)

              predecessors[target_id] << source_id
            end

            predecessors
          end

          # Iterative post-order traversal of each node's predecessors. This
          # is the stack-safe equivalent of the original memoised recursive
          # longest-path calculation and preserves its insertion order.
          def assign_predecessor_layers(nodes, predecessors)
            @node_layers = {}
            colors = {}

            nodes.each_key do |node_id|
              next if @node_layers.key?(node_id)

              walk_predecessors(node_id, predecessors, colors)
            end
          end

          def walk_predecessors(root_id, predecessors, colors)
            colors[root_id] = :active
            stack = [[root_id, 0]]

            until stack.empty?
              step_predecessor_stack(stack, predecessors, colors)
            end
          end

          def step_predecessor_stack(stack, predecessors, colors)
            # `stack[-1]` and `stack.at(-1)` are the same Array call with a
            # single integer index -- no spec can tell them apart, and
            # mutant flags the swap as a surviving mutation every run.
            # Equivalent mutant, not a coverage gap.
            frame = stack[-1]
            current_id, predecessor_index = frame
            incoming = predecessors[current_id]

            if predecessor_index >= incoming.length
              finish_predecessor_frame(stack, current_id, incoming, colors)
              return
            end

            predecessor_id = incoming[predecessor_index]
            frame[1] = predecessor_index + 1
            return if predecessor_assigned?(predecessor_id, colors)

            colors[predecessor_id] = :active
            stack << [predecessor_id, 0]
          end

          def finish_predecessor_frame(stack, node_id, incoming, colors)
            assign_layer(node_id, incoming)
            # keep this write even though `colors` is only ever read with
            # `== :active` in predecessor_assigned?, which checks
            # @node_layers.key?(node_id) FIRST and returns true before it
            # would ever read :complete here -- assign_layer above always
            # runs first, so by the time anything could read this node's
            # color, the key-check has already short-circuited. Confirmed
            # by hand: removing this line changes nothing observable. It
            # becomes load-bearing only if that ordering, or the
            # :active-only read in predecessor_assigned?, ever changes.
            colors[node_id] = :complete
            stack.pop
          end

          # False here is the ordinary case: predecessor_id hasn't been
          # visited by an earlier root yet, so the caller descends into it
          # next. True from the :active check is the defensive case --
          # CycleBreaker orients every back edge away from the active DFS
          # path, so through the real pipeline this branch never fires; it
          # guards a direct caller of LayerAssigner that supplies an
          # incomplete reversal set. Warn there specifically (not on the
          # plain-revisit case above it): silently proceeding is what
          # dropped a diagnostic this class used to print for exactly that
          # misuse.
          def predecessor_assigned?(predecessor_id, colors)
            return true if @node_layers.key?(predecessor_id)
            return false unless colors[predecessor_id] == :active

            warn "LayerAssigner: cycle through #{predecessor_id} not " \
                 "fully broken; treating as a root for this branch"
            true
          end

          def assign_layer(node_id, incoming)
            max_predecessor_layer = incoming.filter_map do |predecessor_id|
              @node_layers[predecessor_id]
            end.max

            @node_layers[node_id] =
              if max_predecessor_layer
                max_predecessor_layer + 1
              else
                0
              end
          end

          def apply_layer_constraints(nodes)
            LayerConstraints.new(nodes, @node_layers, @resolver).apply
          end

          def build_layers(nodes)
            max_layer = @node_layers.values.max || 0
            @layers = Array.new(max_layer + 1) { [] }
            @node_layers.each do |node_id, layer|
              @layers[layer] << nodes[node_id]
            end

            @layers
          end

          def usable_edge?(source_id, target_id, nodes)
            source_id && target_id && source_id != target_id &&
              nodes.key?(source_id) && nodes.key?(target_id)
          end

          def oriented_endpoints(edge)
            source_id = endpoint_owner_id(edge.sources)
            target_id = endpoint_owner_id(edge.targets)
            return [nil, nil] unless source_id && target_id

            if @reversed_edges.include?(edge)
              [target_id, source_id]
            else
              [source_id, target_id]
            end
          end

          def endpoint_owner_id(endpoints)
            id = (endpoints || []).first
            owner = @index.owner(id) if id
            owner&.id
          end
        end
      end
    end
  end
end
