#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "elkrb"

# Hierarchical graph layout example
# This demonstrates nested graphs with parent-child relationships

# Create a hierarchical graph with nested nodes
graph = {
  id: "root",
  layoutOptions: {
    "elk.algorithm" => "layered",
    "elk.direction" => "RIGHT",
  },
  children: [
    {
      id: "parent1",
      children: [
        { id: "p1_child1", width: 80, height: 40 },
        { id: "p1_child2", width: 80, height: 40 },
      ],
      edges: [
        { id: "p1_e1", sources: ["p1_child1"], targets: ["p1_child2"] },
      ],
    },
    {
      id: "parent2",
      children: [
        { id: "p2_child1", width: 80, height: 40 },
      ],
    },
  ],
  edges: [
    { id: "e1", sources: ["parent1"], targets: ["parent2"] },
  ],
}

result = Elkrb.layout(graph)

# Display results
puts "Hierarchical layout completed!"
puts "=" * 60
puts "Root dimensions: #{result.width}x#{result.height}"

# Child coordinates are relative to their parent
print_node = lambda do |node, depth|
  puts "#{'  ' * depth}#{node.id}: (#{node.x}, #{node.y}) " \
       "#{node.width}x#{node.height}"
  (node.children || []).each { |child| print_node.call(child, depth + 1) }
end
result.children.each { |node| print_node.call(node, 1) }
