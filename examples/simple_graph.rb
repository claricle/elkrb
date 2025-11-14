#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "elkrb"

# Simple graph layout example
# This demonstrates the basic usage of ElkRb with a simple node graph

# Create a graph with 4 nodes connected in sequence
graph = Elkrb::Graph.new(
  id: "root",
  children: [
    { id: "n1", width: 100, height: 50 },
    { id: "n2", width: 100, height: 50 },
    { id: "n3", width: 100, height: 50 },
    { id: "n4", width: 100, height: 50 },
  ],
  edges: [
    { id: "e1", sources: ["n1"], targets: ["n2"] },
    { id: "e2", sources: ["n2"], targets: ["n3"] },
    { id: "e3", sources: ["n3"], targets: ["n4"] },
  ],
)

# Configure layout options
graph.layout_options = {
  "algorithm" => "layered",
  "elk.direction" => "DOWN",
  "spacing.nodeNode" => 50,
}

# Perform layout
engine = Elkrb::Layout::LayoutEngine.new
result = engine.layout(graph)

# Display results
puts "Graph layout completed!"
puts "=" * 60
puts "Root dimensions: #{result.width}x#{result.height}"
puts "\nNode positions:"
result.children.each do |node|
  puts "  #{node.id}: (#{node.x}, #{node.y})"
end

puts "\nEdge routing:"
result.edges.each do |edge|
  puts "  #{edge.id}: #{edge.sections&.first&.start_point} -> " \
       "#{edge.sections&.first&.end_point}"
end
