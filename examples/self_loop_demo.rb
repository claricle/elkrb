#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/elkrb"

# Example 1: Simple Self-loop
puts "=" * 70
puts "Example 1: Simple Self-loop with Default Settings"
puts "=" * 70

graph1 = Elkrb::Graph::Graph.new(
  id: "simple_self_loop",
  children: [
    Elkrb::Graph::Node.new(
      id: "state1",
      width: 100.0,
      height: 60.0,
    ),
  ],
  edges: [
    Elkrb::Graph::Edge.new(
      id: "loop1",
      sources: ["state1"],
      targets: ["state1"],
    ),
  ],
  layout_options: Elkrb::Graph::LayoutOptions.new(
    algorithm: "layered",
  ),
)

result1 = Elkrb.layout(graph1)
puts "\nNode position: (#{result1.children[0].x}, #{result1.children[0].y})"
puts "Self-loop section: #{result1.edges[0].sections.length} section(s)"
puts "Bend points: #{result1.edges[0].sections[0].bend_points.length}"
puts "Start: (#{result1.edges[0].sections[0].start_point.x.round(1)}, " \
     "#{result1.edges[0].sections[0].start_point.y.round(1)})"
puts "End: (#{result1.edges[0].sections[0].end_point.x.round(1)}, " \
     "#{result1.edges[0].sections[0].end_point.y.round(1)})"

# Example 2: Self-loop with Custom Side
puts "\n#{'=' * 70}"
puts "Example 2: Self-loop on Different Sides"
puts "=" * 70

%w[EAST WEST NORTH SOUTH].each do |side|
  graph = Elkrb::Graph::Graph.new(
    id: "self_loop_#{side.downcase}",
    children: [
      Elkrb::Graph::Node.new(
        id: "node",
        width: 80.0,
        height: 60.0,
      ),
    ],
    edges: [
      Elkrb::Graph::Edge.new(
        id: "loop",
        sources: ["node"],
        targets: ["node"],
        layout_options: Elkrb::Graph::LayoutOptions.new(
          "elk.selfLoopSide" => side,
        ),
      ),
    ],
    layout_options: Elkrb::Graph::LayoutOptions.new(
      algorithm: "layered",
    ),
  )

  result = Elkrb.layout(graph)
  section = result.edges[0].sections[0]
  puts "\n#{side} side:"
  puts "  Start: (#{section.start_point.x.round(1)}, " \
       "#{section.start_point.y.round(1)})"
  puts "  Bend points: #{section.bend_points.length}"
end

# Example 3: Multiple Self-loops on Same Node
puts "\n#{'=' * 70}"
puts "Example 3: Multiple Self-loops on Same Node"
puts "=" * 70

graph3 = Elkrb::Graph::Graph.new(
  id: "multiple_self_loops",
  children: [
    Elkrb::Graph::Node.new(
      id: "state",
      width: 100.0,
      height: 80.0,
    ),
  ],
  edges: [
    Elkrb::Graph::Edge.new(
      id: "loop1",
      sources: ["state"],
      targets: ["state"],
    ),
    Elkrb::Graph::Edge.new(
      id: "loop2",
      sources: ["state"],
      targets: ["state"],
    ),
    Elkrb::Graph::Edge.new(
      id: "loop3",
      sources: ["state"],
      targets: ["state"],
    ),
  ],
  layout_options: Elkrb::Graph::LayoutOptions.new(
    algorithm: "layered",
  ),
)

result3 = Elkrb.layout(graph3)
result3.edges.each_with_index do |edge, i|
  section = edge.sections[0]
  first_bend = section.bend_points[0]
  puts "\nLoop #{i + 1} (#{edge.id}):"
  puts "  First bend point x: #{first_bend.x.round(1)}"
  puts "  Offset from node edge: " \
       "#{(first_bend.x - result3.children[0].x -
           result3.children[0].width).round(1)}"
end

# Example 4: Self-loop with Spline Routing
puts "\n#{'=' * 70}"
puts "Example 4: Self-loop with Spline (Curved) Routing"
puts "=" * 70

graph4 = Elkrb::Graph::Graph.new(
  id: "spline_self_loop",
  children: [
    Elkrb::Graph::Node.new(
      id: "node",
      width: 100.0,
      height: 60.0,
    ),
  ],
  edges: [
    Elkrb::Graph::Edge.new(
      id: "curved_loop",
      sources: ["node"],
      targets: ["node"],
    ),
  ],
  layout_options: Elkrb::Graph::LayoutOptions.new(
    algorithm: "layered",
    edge_routing: "SPLINES",
  ),
)

result4 = Elkrb.layout(graph4)
section4 = result4.edges[0].sections[0]
puts "\nSpline self-loop:"
puts "  Control points: #{section4.bend_points.length}"
puts "  Control point 1: (#{section4.bend_points[0].x.round(1)}, " \
     "#{section4.bend_points[0].y.round(1)})"
puts "  Control point 2: (#{section4.bend_points[1].x.round(1)}, " \
     "#{section4.bend_points[1].y.round(1)})"

# Example 5: State Machine with Self-loops
puts "\n#{'=' * 70}"
puts "Example 5: State Machine with Self-loops and Transitions"
puts "=" * 70

graph5 = Elkrb::Graph::Graph.new(
  id: "state_machine",
  children: [
    Elkrb::Graph::Node.new(
      id: "idle",
      width: 80.0,
      height: 50.0,
    ),
    Elkrb::Graph::Node.new(
      id: "running",
      width: 80.0,
      height: 50.0,
    ),
    Elkrb::Graph::Node.new(
      id: "error",
      width: 80.0,
      height: 50.0,
    ),
  ],
  edges: [
    # Self-loops (states that can transition to themselves)
    Elkrb::Graph::Edge.new(
      id: "idle_wait",
      sources: ["idle"],
      targets: ["idle"],
    ),
    Elkrb::Graph::Edge.new(
      id: "running_continue",
      sources: ["running"],
      targets: ["running"],
    ),
    # Regular transitions
    Elkrb::Graph::Edge.new(
      id: "start",
      sources: ["idle"],
      targets: ["running"],
    ),
    Elkrb::Graph::Edge.new(
      id: "fail",
      sources: ["running"],
      targets: ["error"],
    ),
    Elkrb::Graph::Edge.new(
      id: "reset",
      sources: ["error"],
      targets: ["idle"],
    ),
  ],
  layout_options: Elkrb::Graph::LayoutOptions.new(
    algorithm: "layered",
    direction: "RIGHT",
  ),
)

result5 = Elkrb.layout(graph5)
puts "\nState machine layout:"
result5.children.each do |node|
  puts "  #{node.id}: (#{node.x.round(1)}, #{node.y.round(1)})"
end
puts "\nEdges:"
result5.edges.each do |edge|
  is_self_loop = edge.sources[0] == edge.targets[0]
  puts "  #{edge.id}: #{is_self_loop ? 'self-loop' : 'transition'}"
end

# Example 6: Self-loop with Ports
puts "\n#{'=' * 70}"
puts "Example 6: Self-loop Between Ports"
puts "=" * 70

graph6 = Elkrb::Graph::Graph.new(
  id: "port_self_loop",
  children: [
    Elkrb::Graph::Node.new(
      id: "component",
      width: 120.0,
      height: 80.0,
      ports: [
        Elkrb::Graph::Port.new(
          id: "out1",
          x: 120.0,
          y: 20.0,
          side: "EAST",
        ),
        Elkrb::Graph::Port.new(
          id: "in1",
          x: 120.0,
          y: 60.0,
          side: "EAST",
        ),
      ],
    ),
  ],
  edges: [
    Elkrb::Graph::Edge.new(
      id: "feedback",
      sources: ["out1"],
      targets: ["in1"],
    ),
  ],
  layout_options: Elkrb::Graph::LayoutOptions.new(
    algorithm: "layered",
  ),
)

result6 = Elkrb.layout(graph6)
section6 = result6.edges[0].sections[0]
puts "\nPort-based self-loop:"
puts "  Start (out1): (#{section6.start_point.x.round(1)}, " \
     "#{section6.start_point.y.round(1)})"
puts "  End (in1): (#{section6.end_point.x.round(1)}, " \
     "#{section6.end_point.y.round(1)})"
puts "  Bend points: #{section6.bend_points.length}"

# Example 7: Finite Automaton
puts "\n#{'=' * 70}"
puts "Example 7: Finite Automaton with Self-loops"
puts "=" * 70

graph7 = Elkrb::Graph::Graph.new(
  id: "finite_automaton",
  children: [
    Elkrb::Graph::Node.new(
      id: "q0",
      width: 60.0,
      height: 60.0,
    ),
    Elkrb::Graph::Node.new(
      id: "q1",
      width: 60.0,
      height: 60.0,
    ),
    Elkrb::Graph::Node.new(
      id: "q2",
      width: 60.0,
      height: 60.0,
    ),
  ],
  edges: [
    # Self-loops for states reading same symbol
    Elkrb::Graph::Edge.new(
      id: "q0_0",
      sources: ["q0"],
      targets: ["q0"],
      layout_options: Elkrb::Graph::LayoutOptions.new(
        "elk.selfLoopSide" => "NORTH",
      ),
    ),
    Elkrb::Graph::Edge.new(
      id: "q1_1",
      sources: ["q1"],
      targets: ["q1"],
      layout_options: Elkrb::Graph::LayoutOptions.new(
        "elk.selfLoopSide" => "NORTH",
      ),
    ),
    # State transitions
    Elkrb::Graph::Edge.new(
      id: "q0_to_q1",
      sources: ["q0"],
      targets: ["q1"],
    ),
    Elkrb::Graph::Edge.new(
      id: "q1_to_q2",
      sources: ["q1"],
      targets: ["q2"],
    ),
  ],
  layout_options: Elkrb::Graph::LayoutOptions.new(
    algorithm: "layered",
    direction: "RIGHT",
  ),
)

result7 = Elkrb.layout(graph7)
puts "\nFinite automaton states:"
result7.children.each do |node|
  puts "  #{node.id}: (#{node.x.round(1)}, #{node.y.round(1)})"
end

self_loops = result7.edges.select { |e| e.sources[0] == e.targets[0] }
puts "\nSelf-loops (same symbol transitions):"
self_loops.each do |edge|
  section = edge.sections[0]
  puts "  #{edge.id}: #{section.bend_points.length} bend points"
end

# Example 8: Mixed Routing Styles
puts "\n#{'=' * 70}"
puts "Example 8: Comparing Routing Styles"
puts "=" * 70

%w[ORTHOGONAL SPLINES POLYLINE].each do |style|
  graph = Elkrb::Graph::Graph.new(
    id: "style_#{style.downcase}",
    children: [
      Elkrb::Graph::Node.new(
        id: "node",
        width: 80.0,
        height: 60.0,
      ),
    ],
    edges: [
      Elkrb::Graph::Edge.new(
        id: "loop",
        sources: ["node"],
        targets: ["node"],
      ),
    ],
    layout_options: Elkrb::Graph::LayoutOptions.new(
      algorithm: "layered",
      edge_routing: style,
    ),
  )

  result = Elkrb.layout(graph)
  section = result.edges[0].sections[0]
  puts "\n#{style} routing:"
  puts "  Bend points: #{section.bend_points.length}"
  puts "  Path length: #{section.length.round(2)}"
end

puts "\n#{'=' * 70}"
puts "All examples completed successfully!"
puts "=" * 70
