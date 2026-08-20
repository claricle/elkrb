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
              target = first_other_target(edge, node)
              next unless target

              if @in_stack[target.id]
                # Found a cycle - mark this edge for reversal
                @edges_to_reverse << edge
              elsif !@visited[target.id]
                dfs(target)
              end
            end

            @in_stack[node.id] = false
          end

          # The first resolved target that is NOT `node` itself. Plain
          # `edge.targets.first` breaks for a hyperedge whose first
          # target happens to be one of the source's own ports (e.g.
          # a -> [a's port, b]): resolving straight to `a` makes dfs
          # see a's own in-progress frame as a cycle and reverse the
          # edge, corrupting it before LayerAssigner ever sees it
          # (confirmed: recurses forever there, SystemStackError). This
          # keeps the existing "first target" simplification (D8) but
          # skips a self-reference to find the genuinely different one.
          def first_other_target(edge, node)
            @index.endpoint_nodes(edge.targets).find { |target| target != node }
          end

          def get_outgoing_edges(node)
            edges = []

            # Get edges from the node itself
            edges.concat(node.edges) if node.edges

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
