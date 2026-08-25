# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Assigns nodes to layers in the graph
        #
        # This is the second phase of the Sugiyama framework.
        # Uses longest path layering to create a balanced layout.
        class LayerAssigner
          attr_reader :layers

          def initialize(graph, index)
            @graph = graph
            @index = index
            @layers = []
            @node_layers = {}
            @in_progress = Set.new
          end

          def assign_layers
            return [] unless @graph.children

            # Calculate layer for each node
            @graph.children.each do |node|
              calculate_layer(node)
            end

            # Group nodes by layer
            max_layer = @node_layers.values.max || 0
            @layers = Array.new(max_layer + 1) { [] }

            @node_layers.each do |node_id, layer|
              node = @index.node(node_id)
              @layers[layer] << node if node
            end

            @layers
          end

          def get_layer(node_id)
            @node_layers[node_id]
          end

          private

          def calculate_layer(node)
            return @node_layers[node.id] if @node_layers.key?(node.id)

            # A cycle CycleBreaker did not resolve (only a genuine
            # hyperedge, > 1 target, can still reach this -- S8 will
            # reject those outright before phase 1 runs; this diff
            # does not). A node revisited while still being computed
            # has no further predecessor to contribute, so treat it as
            # one without them rather than recursing forever
            # (SystemStackError). CycleBreaker walks every target of
            # every edge, but reversing a hyperedge swaps its whole
            # source and target lists at once, which can leave a cycle
            # standing.
            if @in_progress.include?(node.id)
              warn "Layered: cycle through #{node.id} not fully broken " \
                   "(hyperedge); treating as a root for this branch"
              return 0
            end

            @in_progress << node.id

            # Find incoming edges
            incoming = get_incoming_edges(node)

            if incoming.empty?
              # Root node - assign to layer 0
              @node_layers[node.id] = 0
            else
              # Assign to one layer below the maximum of predecessors.
              # first_other_source cannot return nil here: every edge
              # in `incoming` already passed incoming_to?, which only
              # admits edges with at least one resolved source
              # different from `node` -- the same one this looks for.
              max_pred_layer = incoming.map do |edge|
                calculate_layer(first_other_source(edge, node))
              end.max || 0

              @node_layers[node.id] = max_pred_layer + 1
            end

            @in_progress.delete(node.id)
            @node_layers[node.id]
          end

          def get_incoming_edges(node)
            @index.edges.select { |edge| incoming_to?(edge, node) }
          end

          # True when `node` is a genuine target of `edge`: `node` is
          # one of its resolved targets AND at least one resolved
          # source is a DIFFERENT node. The second half excludes a
          # self-loop ("p1" -> "p2" on one node) and the
          # self-referencing leg of a mixed hyperedge
          # (a -> [a's port, b]) from counting as incoming, while still
          # counting a target's genuine incoming edges from elsewhere
          # (e.g. [a, c] -> b). Comparing raw ids, or only the first
          # source against the first target, both let a self-loop or a
          # self-referencing hyperedge leg look like real incoming
          # traffic, and calculate_layer recurses on the same node
          # forever before it is memoized (SystemStackError). S8 will
          # reject hyperedges before phase 1 runs; until then this
          # keeps the check correct.
          def incoming_to?(edge, node)
            targets = @index.endpoint_owners(edge.targets)
            return false unless targets.include?(node)

            sources = @index.endpoint_owners(edge.sources)
            sources.any? { |source| source != node }
          end

          # The first resolved source that is NOT `node` itself. Plain
          # `edge.sources.first` breaks for a hyperedge whose first
          # source happens to be the target itself (e.g. [a, b] -> a,
          # already known to have incoming traffic from b via
          # incoming_to? above): resolving straight back to `a` would
          # recurse calculate_layer on the same node forever before it
          # is memoized (SystemStackError, confirmed by direct
          # reproduction).
          def first_other_source(edge, node)
            @index.endpoint_owners(edge.sources).find do |source|
              source != node
            end
          end
        end
      end
    end
  end
end
