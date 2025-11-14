#!/usr/bin/env ruby
# frozen_string_literal: true

# Spline Edge Routing Demo
#
# This example demonstrates the use of smooth Bezier curve routing for edges
# in ElkRb, comparing different routing styles.

require_relative "../lib/elkrb"

def create_sample_graph(routing_style, curvature = 0.5)
  Elkrb::Graph::Graph.new(
    id: "root",
    layout_options: Elkrb::Graph::LayoutOptions.new(
      algorithm: "layered",
      direction: "RIGHT",
      edge_routing: routing_style,
      spline_curvature: curvature,
      spacing_node_node: 80.0,
    ),
    children: [
      Elkrb::Graph::Node.new(
        id: "n1",
        width: 80,
        height: 40,
        labels: [
          Elkrb::Graph::Label.new(text: "Start", width: 40, height: 15),
        ],
      ),
      Elkrb::Graph::Node.new(
        id: "n2",
        width: 80,
        height: 40,
        labels: [
          Elkrb::Graph::Label.new(text: "Process", width: 50, height: 15),
        ],
      ),
      Elkrb::Graph::Node.new(
        id: "n3",
        width: 80,
        height: 40,
        labels: [
          Elkrb::Graph::Label.new(text: "Decision", width: 55, height: 15),
        ],
      ),
      Elkrb::Graph::Node.new(
        id: "n4",
        width: 80,
        height: 40,
        labels: [
          Elkrb::Graph::Label.new(text: "End", width: 30, height: 15),
        ],
      ),
    ],
    edges: [
      Elkrb::Graph::Edge.new(
        id: "e1",
        sources: ["n1"],
        targets: ["n2"],
      ),
      Elkrb::Graph::Edge.new(
        id: "e2",
        sources: ["n2"],
        targets: ["n3"],
      ),
      Elkrb::Graph::Edge.new(
        id: "e3",
        sources: ["n3"],
        targets: ["n4"],
      ),
      Elkrb::Graph::Edge.new(
        id: "e4",
        sources: ["n3"],
        targets: ["n2"],
        labels: [
          Elkrb::Graph::Label.new(text: "retry", width: 30, height: 15),
        ],
      ),
    ],
  )
end

def print_edge_info(edge, style_name)
  section = edge.sections&.first
  return unless section

  puts "\n  Edge #{edge.id} (#{style_name}):"
  puts "    Start: (#{section.start_point.x.round(1)}, " \
       "#{section.start_point.y.round(1)})"

  if section.bend_points&.any?
    section.bend_points.each_with_index do |point, i|
      puts "    Control #{i + 1}: (#{point.x.round(1)}, #{point.y.round(1)})"
    end
  end

  puts "    End: (#{section.end_point.x.round(1)}, " \
       "#{section.end_point.y.round(1)})"
  puts "    Length: #{section.length.round(2)}"
end

puts "=" * 70
puts "ElkRb Spline Edge Routing Demo"
puts "=" * 70

# Demo 1: Orthogonal Routing (Default)
puts "\n1. ORTHOGONAL ROUTING (90-degree bends)"
puts "-" * 70

graph1 = create_sample_graph("ORTHOGONAL")
result1 = Elkrb::Layout::LayoutEngine.layout(graph1)

puts "\nGraph dimensions: #{result1.width.round(1)} x #{result1.height.round(1)}"
result1.edges.each { |edge| print_edge_info(edge, "ORTHOGONAL") }

# Demo 2: Polyline Routing
puts "\n\n2. POLYLINE ROUTING (Straight lines)"
puts "-" * 70

graph2 = create_sample_graph("POLYLINE")
result2 = Elkrb::Layout::LayoutEngine.layout(graph2)

puts "\nGraph dimensions: #{result2.width.round(1)} x #{result2.height.round(1)}"
result2.edges.each { |edge| print_edge_info(edge, "POLYLINE") }

# Demo 3: Spline Routing (Smooth curves - Default curvature)
puts "\n\n3. SPLINE ROUTING (Smooth curves - curvature: 0.5)"
puts "-" * 70

graph3 = create_sample_graph("SPLINES", 0.5)
result3 = Elkrb::Layout::LayoutEngine.layout(graph3)

puts "\nGraph dimensions: #{result3.width.round(1)} x #{result3.height.round(1)}"
result3.edges.each { |edge| print_edge_info(edge, "SPLINES") }

# Demo 4: Spline Routing with Low Curvature
puts "\n\n4. SPLINE ROUTING (Gentle curves - curvature: 0.2)"
puts "-" * 70

graph4 = create_sample_graph("SPLINES", 0.2)
result4 = Elkrb::Layout::LayoutEngine.layout(graph4)

puts "\nGraph dimensions: #{result4.width.round(1)} x #{result4.height.round(1)}"
result4.edges.each { |edge| print_edge_info(edge, "SPLINES 0.2") }

# Demo 5: Spline Routing with High Curvature
puts "\n\n5. SPLINE ROUTING (Strong curves - curvature: 0.9)"
puts "-" * 70

graph5 = create_sample_graph("SPLINES", 0.9)
result5 = Elkrb::Layout::LayoutEngine.layout(graph5)

puts "\nGraph dimensions: #{result5.width.round(1)} x #{result5.height.round(1)}"
result5.edges.each { |edge| print_edge_info(edge, "SPLINES 0.9") }

# Demo 6: Port-based Spline Routing
puts "\n\n6. PORT-BASED SPLINE ROUTING"
puts "-" * 70

port_graph = Elkrb::Graph::Graph.new(
  id: "port_demo",
  layout_options: Elkrb::Graph::LayoutOptions.new(
    algorithm: "layered",
    direction: "RIGHT",
    edge_routing: "SPLINES",
    spline_curvature: 0.6,
  ),
  children: [
    Elkrb::Graph::Node.new(
      id: "source",
      width: 100,
      height: 60,
      ports: [
        Elkrb::Graph::Port.new(id: "out1", x: 100, y: 15),
        Elkrb::Graph::Port.new(id: "out2", x: 100, y: 45),
      ],
      labels: [
        Elkrb::Graph::Label.new(text: "Source", width: 45, height: 15),
      ],
    ),
    Elkrb::Graph::Node.new(
      id: "target",
      width: 100,
      height: 60,
      ports: [
        Elkrb::Graph::Port.new(id: "in1", x: 0, y: 15),
        Elkrb::Graph::Port.new(id: "in2", x: 0, y: 45),
      ],
      labels: [
        Elkrb::Graph::Label.new(text: "Target", width: 45, height: 15),
      ],
    ),
  ],
  edges: [
    Elkrb::Graph::Edge.new(
      id: "pe1",
      sources: ["out1"],
      targets: ["in1"],
    ),
    Elkrb::Graph::Edge.new(
      id: "pe2",
      sources: ["out2"],
      targets: ["in2"],
    ),
  ],
)

port_result = Elkrb::Layout::LayoutEngine.layout(port_graph)
puts "\nGraph dimensions: #{port_result.width.round(1)} x " \
     "#{port_result.height.round(1)}"
port_result.edges.each { |edge| print_edge_info(edge, "PORT SPLINES") }

# Comparison Summary
puts "\n\n#{'=' * 70}"
puts "COMPARISON SUMMARY"
puts "=" * 70

puts "\nRouting Style Characteristics:"
puts "  • ORTHOGONAL: Right-angle bends, clear paths, traditional look"
puts "  • POLYLINE:   Direct straight lines, minimal space, technical look"
puts "  • SPLINES:    Smooth curves, aesthetic appeal, natural flow"

puts "\nSpline Curvature Guide:"
puts "  • 0.0-0.3: Gentle curves, closer to straight lines"
puts "  • 0.4-0.6: Moderate curves, balanced appearance (recommended)"
puts "  • 0.7-1.0: Strong curves, very pronounced arcs"

puts "\nWhen to Use Each Style:"
puts "  • ORTHOGONAL: Technical diagrams, flowcharts, circuit diagrams"
puts "  • POLYLINE:   Simple connections, space-constrained layouts"
puts "  • SPLINES:    Presentation diagrams, organic layouts, visual appeal"

puts "\n#{'=' * 70}"
puts "Demo complete! See SPLINE_ROUTING_GUIDE.md for more information."
puts "=" * 70
