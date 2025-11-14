#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/elkrb"

# Example 1: Manual Port Sides
puts "=" * 60
puts "Example 1: Manual Port Sides"
puts "=" * 60

graph1 = Elkrb::Graph::Graph.new(id: "g1")

# Create a node with ports on specific sides
node1 = Elkrb::Graph::Node.new(
  id: "n1",
  width: 100,
  height: 60,
  x: 50,
  y: 50,
)

# Input ports on the left (WEST)
node1.ports = [
  Elkrb::Graph::Port.new(id: "in1", side: "WEST", index: 0),
  Elkrb::Graph::Port.new(id: "in2", side: "WEST", index: 1),
]

# Output port on the right (EAST)
node2 = Elkrb::Graph::Node.new(
  id: "n2",
  width: 100,
  height: 60,
  x: 200,
  y: 50,
)
node2.ports = [
  Elkrb::Graph::Port.new(id: "out1", side: "EAST", index: 0),
]

graph1.children = [node1, node2]

# Create edges connecting the ports
graph1.edges = [
  Elkrb::Graph::Edge.new(
    id: "e1",
    sources: ["in1"],
    targets: ["out1"],
  ),
]

# Apply layout
engine = Elkrb::Layout::LayoutEngine.new
result1 = engine.layout(graph1)

puts "\nNode 1 Ports (after layout):"
result1.children[0].ports.each do |port|
  puts "  #{port.id}: side=#{port.side}, x=#{port.x}, y=#{port.y}, " \
       "index=#{port.index}"
end

puts "\nNode 2 Ports (after layout):"
result1.children[1].ports.each do |port|
  puts "  #{port.id}: side=#{port.side}, x=#{port.x}, y=#{port.y}, " \
       "index=#{port.index}"
end

# Example 2: Automatic Side Detection
puts "\n"
puts "=" * 60
puts "Example 2: Automatic Side Detection from Positions"
puts "=" * 60

graph2 = Elkrb::Graph::Graph.new(id: "g2")

# Create node with ports at specific positions
# The layout engine will detect which side each port belongs to
node3 = Elkrb::Graph::Node.new(
  id: "n3",
  width: 120,
  height: 80,
  x: 50,
  y: 50,
)

node3.ports = [
  Elkrb::Graph::Port.new(id: "p1", x: 60, y: 0),    # Top - should detect NORTH
  Elkrb::Graph::Port.new(id: "p2", x: 60, y: 80),   # Bottom - should detect SOUTH
  Elkrb::Graph::Port.new(id: "p3", x: 0, y: 40),    # Left - should detect WEST
  Elkrb::Graph::Port.new(id: "p4", x: 120, y: 40), # Right - should detect EAST
]

graph2.children = [node3]

# Apply layout
result2 = engine.layout(graph2)

puts "\nPort Side Detection Results:"
result2.children[0].ports.each do |port|
  puts "  #{port.id}: detected side=#{port.side}, position=(#{port.x}, #{port.y})"
end

# Example 3: Port Ordering
puts "\n"
puts "=" * 60
puts "Example 3: Port Ordering within Sides"
puts "=" * 60

graph3 = Elkrb::Graph::Graph.new(id: "g3")

# Create node with multiple ports on the same side
node4 = Elkrb::Graph::Node.new(
  id: "n4",
  width: 150,
  height: 100,
  x: 50,
  y: 50,
)

# Multiple ports on NORTH side with explicit ordering
node4.ports = [
  Elkrb::Graph::Port.new(id: "north3", side: "NORTH", index: 2),
  Elkrb::Graph::Port.new(id: "north1", side: "NORTH", index: 0),
  Elkrb::Graph::Port.new(id: "north2", side: "NORTH", index: 1),
  Elkrb::Graph::Port.new(id: "south1", side: "SOUTH", index: 0),
  Elkrb::Graph::Port.new(id: "south2", side: "SOUTH", index: 1),
]

graph3.children = [node4]

# Apply layout
result3 = engine.layout(graph3)

puts "\nNORTH Side Ports (ordered):"
north_ports = result3.children[0].ports.select { |p| p.side == "NORTH" }
north_ports.sort_by(&:index).each do |port|
  puts "  #{port.id}: index=#{port.index}, x=#{port.x.round(2)}, " \
       "offset=#{port.offset.round(2)}"
end

puts "\nSOUTH Side Ports (ordered):"
south_ports = result3.children[0].ports.select { |p| p.side == "SOUTH" }
south_ports.sort_by(&:index).each do |port|
  puts "  #{port.id}: index=#{port.index}, x=#{port.x.round(2)}, " \
       "offset=#{port.offset.round(2)}"
end

# Example 4: Port Constraints in Layout Options
puts "\n"
puts "=" * 60
puts "Example 4: Port Constraints via Layout Options"
puts "=" * 60

graph4 = Elkrb::Graph::Graph.new(id: "g4")

# Set port constraint options
graph4.layout_options = Elkrb::Graph::LayoutOptions.new
graph4.layout_options["elk.portConstraints"] = "FIXED_SIDE"
graph4.layout_options["elk.portSideAssignment"] = "AUTOMATIC"
graph4.layout_options["elk.portOrdering"] = "INDEX"

puts "\nLayout Options:"
puts "  Port Constraints: #{graph4.layout_options.port_constraints}"
puts "  Port Side Assignment: #{graph4.layout_options.port_side_assignment}"
puts "  Port Ordering: #{graph4.layout_options.port_ordering}"

# Create node with ports
node5 = Elkrb::Graph::Node.new(
  id: "n5",
  width: 100,
  height: 60,
  x: 50,
  y: 50,
)

node5.ports = [
  Elkrb::Graph::Port.new(id: "p1", x: 25, y: 0),
  Elkrb::Graph::Port.new(id: "p2", x: 75, y: 0),
  Elkrb::Graph::Port.new(id: "p3", x: 0, y: 30),
]

graph4.children = [node5]

# Apply layout
result4 = engine.layout(graph4)

puts "\nPorts after layout with constraints:"
result4.children[0].ports.each do |port|
  puts "  #{port.id}: side=#{port.side}, index=#{port.index}, " \
       "pos=(#{port.x.round(2)}, #{port.y.round(2)})"
end

# Example 5: Complete Diagram with Port-Based Routing
puts "\n"
puts "=" * 60
puts "Example 5: Complete Diagram with Port-Based Routing"
puts "=" * 60

graph5 = Elkrb::Graph::Graph.new(id: "g5")
graph5.layout_options = Elkrb::Graph::LayoutOptions.new
graph5.layout_options["elk.algorithm"] = "layered"
graph5.layout_options["elk.edgeRouting"] = "ORTHOGONAL"

# Create multiple nodes with ports
nodeA = Elkrb::Graph::Node.new(
  id: "A",
  width: 80,
  height: 50,
  labels: [Elkrb::Graph::Label.new(text: "Node A")],
)
nodeA.ports = [
  Elkrb::Graph::Port.new(id: "a_out1", side: "EAST", index: 0),
  Elkrb::Graph::Port.new(id: "a_out2", side: "EAST", index: 1),
]

nodeB = Elkrb::Graph::Node.new(
  id: "B",
  width: 80,
  height: 50,
  labels: [Elkrb::Graph::Label.new(text: "Node B")],
)
nodeB.ports = [
  Elkrb::Graph::Port.new(id: "b_in", side: "WEST", index: 0),
  Elkrb::Graph::Port.new(id: "b_out", side: "EAST", index: 0),
]

nodeC = Elkrb::Graph::Node.new(
  id: "C",
  width: 80,
  height: 50,
  labels: [Elkrb::Graph::Label.new(text: "Node C")],
)
nodeC.ports = [
  Elkrb::Graph::Port.new(id: "c_in1", side: "WEST", index: 0),
  Elkrb::Graph::Port.new(id: "c_in2", side: "WEST", index: 1),
]

graph5.children = [nodeA, nodeB, nodeC]

# Connect nodes via ports
graph5.edges = [
  Elkrb::Graph::Edge.new(
    id: "e1",
    sources: ["a_out1"],
    targets: ["b_in"],
  ),
  Elkrb::Graph::Edge.new(
    id: "e2",
    sources: ["a_out2"],
    targets: ["c_in1"],
  ),
  Elkrb::Graph::Edge.new(
    id: "e3",
    sources: ["b_out"],
    targets: ["c_in2"],
  ),
]

# Apply layout
result5 = engine.layout(graph5)

puts "\nFinal Node Positions:"
result5.children.each do |node|
  puts "  #{node.id}: (#{node.x.round(2)}, #{node.y.round(2)})"
  node.ports.each do |port|
    abs_x = node.x + port.x
    abs_y = node.y + port.y
    puts "    #{port.id}: side=#{port.side}, " \
         "absolute_pos=(#{abs_x.round(2)}, #{abs_y.round(2)})"
  end
end

puts "\nEdge Routing:"
result5.edges.each do |edge|
  section = edge.sections&.first
  next unless section

  puts "  #{edge.id}:"
  puts "    Start: (#{section.start_point.x.round(2)}, " \
       "#{section.start_point.y.round(2)})"
  if section.bend_points&.any?
    section.bend_points.each_with_index do |bp, idx|
      puts "    Bend #{idx + 1}: (#{bp.x.round(2)}, #{bp.y.round(2)})"
    end
  end
  puts "    End: (#{section.end_point.x.round(2)}, " \
       "#{section.end_point.y.round(2)})"
end

puts "\n#{'=' * 60}"
puts "Port Constraints Demo Complete!"
puts "=" * 60
