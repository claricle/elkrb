# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # Breaks cycles in the graph to make it acyclic
        #
        # This is the first phase of the Sugiyama framework.
        # Uses a greedy approach to reverse edges that create cycles.
        class CycleBreaker
          def initialize(graph, index)
            @graph = graph
            @index = index
            @visited = {}
            @in_stack = {}
            @edges_to_reverse = []
          end

          def break_cycles
            return unless @graph.children

            # Find all edges that create cycles using DFS
            @graph.children.each do |node|
              dfs(node) unless @visited[node.id]
            end

            # Reverse the problematic edges
            reverse_edges

            @edges_to_reverse
          end

          private

          def dfs(node)
            @visited[node.id] = true
            @in_stack[node.id] = true

            # Process outgoing edges
            get_outgoing_edges(node).each do |edge|
              other_targets(edge, node).each do |target|
                if @in_stack[target.id]
                  mark_for_reversal(edge)
                elsif !@visited[target.id]
                  dfs(target)
                end
              end
            end

            @in_stack[node.id] = false
          end

          # An edge can appear in get_outgoing_edges via both
          # node.edges and @graph.edges, and a hyperedge can be reached
          # from more than one in-stack frame or through more than one
          # of its own targets. Reversing it twice would swap it back
          # to its original direction and leave the cycle unbroken.
          def mark_for_reversal(edge)
            return if @edges_to_reverse.include?(edge)

            @edges_to_reverse << edge
          end

          # Every resolved target that is NOT `node` itself. A
          # hyperedge a -> [b, c] has to be walked through both b and
          # c: stopping at the first one hides a cycle that only c
          # closes. Dropping `node` matters when a target is one of the
          # source's own ports (a -> [a's port, b]) -- resolving that
          # back to `a` makes dfs read a's own in-progress frame as a
          # cycle and reverse an edge that has none, corrupting it
          # before LayerAssigner ever sees it (confirmed: recurses
          # forever there, SystemStackError).
          def other_targets(edge, node)
            targets = @index.endpoint_nodes(edge.targets)
            targets.reject { |target| target == node }
          end

          def get_outgoing_edges(node)
            edges = []
            edges.concat(@index.edges_on(node))

            # Get edges from the graph that have this node as source
            @graph.edges&.each do |edge|
              edges << edge if @index.endpoint_nodes(edge.sources).include?(node)
            end

            edges
          end

          def reverse_edges
            @edges_to_reverse.each do |edge|
              # Swap sources and targets
              edge.sources, edge.targets = edge.targets, edge.sources

              # Mark as reversed for later processing
              edge.properties ||= {}
              edge.properties["reversed"] = true
            end
          end
        end
      end
    end
  end
end
