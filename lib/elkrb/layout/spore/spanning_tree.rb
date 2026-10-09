# frozen_string_literal: true

module Elkrb
  module Layout
    module Spore
      # Minimum spanning tree grown outward from a root by repeatedly adding
      # the cheapest edge that joins a tree body to a body not yet in it.
      # Edges of equal cost are taken in the order given.
      module SpanningTree
        # A body and the bodies reached through it.
        Branch = Struct.new(:body, :children)

        module_function

        # @param edges [Array<Array(Body, Body)>]
        # @param root [Body]
        # @yieldparam first [Body]
        # @yieldparam second [Body]
        # @yieldreturn [Float] the edge's cost
        # @return [Branch]
        def build(edges, root, &)
          pending = by_cost(edges, &)
          tree = Branch.new(root, [])
          branches = {}.compare_by_identity
          branches[root] = tree
          while (index = cheapest_crossing(pending, branches))
            attach(branches, *pending.delete_at(index))
          end
          tree
        end

        def by_cost(edges, &)
          edges.each_with_index
            .sort_by { |(first, second), i| [yield(first, second), i] }
            .map(&:first)
        end

        def cheapest_crossing(pending, branches)
          pending.index do |first, second|
            branches.key?(first) != branches.key?(second)
          end
        end

        def attach(branches, first, second)
          from, added = branches.key?(first) ? [first, second] : [second, first]
          branch = Branch.new(added, [])
          branches[from].children << branch
          branches[added] = branch
        end
      end
    end
  end
end
