# frozen_string_literal: true

module Elkrb
  module Layout
    module Algorithms
      module Layered
        # The order ELK lists a connected graph's nodes in: a depth-first walk
        # from the first node, following each node's edges in the order the
        # importer created them. Every layer starts out in that order, and it
        # decides which of two equally good orders the sweep keeps.
        class DiscoveryOrder
          # @param graph [Graph::Node] the graph whose children are layered
          # @param index [NodeIndex, nil] resolves edge endpoints to nodes
          def initialize(graph, index)
            @children = graph.children || []
            @neighbours = neighbours(index)
          end

          # Reorders each layer in place; dummy slots keep their place at the
          # end.
          def sort(layers)
            ranks = discover
            layers.each do |layer|
              layer.replace(layer.each_with_index.sort_by do |item, position|
                [ranks.fetch(item.id, ranks.length), position]
              end.map(&:first))
            end
          end

          private

          def discover
            ranks = {}
            @children.each { |child| walk(child.id, ranks) }
            ranks
          end

          def walk(root, ranks)
            return if ranks.key?(root)

            pending = [[root]]
            until pending.empty?
              found = pending.last.shift
              next pending.pop unless found
              next if ranks.key?(found)

              ranks[found] = ranks.length
              pending.push(@neighbours.fetch(found).dup)
            end
          end

          def neighbours(index)
            table = @children.to_h { |child| [child.id, []] }
            index&.edges&.each do |edge|
              link(table, owner_id(index, edge.sources),
                   owner_id(index, edge.targets))
            end
            table
          end

          def owner_id(index, endpoints)
            index.owner(endpoints&.first)&.id
          end

          def link(table, source, target)
            return unless table.key?(source) && table.key?(target)

            table[source] << target
            table[target] << source
          end
        end
      end
    end
  end
end
