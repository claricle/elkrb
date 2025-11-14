#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/elkrb"

# Example 1: Simple graph with layout and DOT export
puts "Example 1: Simple Graph"
puts "=" * 50

# Build graph using model objects
simple_graph = Elkrb::Graph::Graph.new(id: "root")

node1 = Elkrb::Graph::Node.new(id: "n1", width: 100, height: 60)
node1.labels = [Elkrb::Graph::Label.new(text: "Node 1")]

node2 = Elkrb::Graph::Node.new(id: "n2", width: 100, height: 60)
node2.labels = [Elkrb::Graph::Label.new(text: "Node 2")]

node3 = Elkrb::Graph::Node.new(id: "n3", width: 100, height: 60)
node3.labels = [Elkrb::Graph::Label.new(text: "Node 3")]

simple_graph.children = [node1, node2, node3]
simple_graph.edges = [
  Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"], targets: ["n2"]),
  Elkrb::Graph::Edge.new(id: "e2", sources: ["n2"], targets: ["n3"]),
  Elkrb::Graph::Edge.new(id: "e3", sources: ["n1"], targets: ["n3"]),
]

# Layout the graph
result = Elkrb.layout(simple_graph, algorithm: "layered")

# Export to DOT format
dot_output = Elkrb.export_dot(result, rankdir: "TB")
puts dot_output
puts "\n"

# Example 2: Hierarchical graph
puts "Example 2: Hierarchical Graph"
puts "=" * 50

# Build hierarchical graph using model objects
hierarchical_graph = Elkrb::Graph::Graph.new(id: "root")

# Cluster 1
cluster1 = Elkrb::Graph::Node.new(id: "cluster1")
cluster1.labels = [Elkrb::Graph::Label.new(text: "Group 1")]
n1 = Elkrb::Graph::Node.new(id: "n1", width: 50, height: 30)
n1.labels = [Elkrb::Graph::Label.new(text: "A")]
n2 = Elkrb::Graph::Node.new(id: "n2", width: 50, height: 30)
n2.labels = [Elkrb::Graph::Label.new(text: "B")]
cluster1.children = [n1, n2]
cluster1.edges = [Elkrb::Graph::Edge.new(id: "e1", sources: ["n1"],
                                         targets: ["n2"])]

# Cluster 2
cluster2 = Elkrb::Graph::Node.new(id: "cluster2")
cluster2.labels = [Elkrb::Graph::Label.new(text: "Group 2")]
n3 = Elkrb::Graph::Node.new(id: "n3", width: 50, height: 30)
n3.labels = [Elkrb::Graph::Label.new(text: "C")]
n4 = Elkrb::Graph::Node.new(id: "n4", width: 50, height: 30)
n4.labels = [Elkrb::Graph::Label.new(text: "D")]
cluster2.children = [n3, n4]
cluster2.edges = [Elkrb::Graph::Edge.new(id: "e2", sources: ["n3"],
                                         targets: ["n4"])]

hierarchical_graph.children = [cluster1, cluster2]
hierarchical_graph.edges = [Elkrb::Graph::Edge.new(id: "e3", sources: ["n2"],
                                                   targets: ["n3"])]

# Layout and export
hierarchical_result = Elkrb.layout(hierarchical_graph, algorithm: "layered")
dot_hierarchical = Elkrb.export_dot(hierarchical_result)
puts dot_hierarchical
puts "\n"

# Example 3: Force-directed layout with custom DOT attributes
puts "Example 3: Force-Directed Layout with Custom Attributes"
puts "=" * 50

# Build force-directed graph
force_graph = Elkrb::Graph::Graph.new(id: "root")

center = Elkrb::Graph::Node.new(id: "center", width: 80, height: 80)
center.labels = [Elkrb::Graph::Label.new(text: "Center")]

na = Elkrb::Graph::Node.new(id: "a", width: 60, height: 60)
na.labels = [Elkrb::Graph::Label.new(text: "A")]

nb = Elkrb::Graph::Node.new(id: "b", width: 60, height: 60)
nb.labels = [Elkrb::Graph::Label.new(text: "B")]

nc = Elkrb::Graph::Node.new(id: "c", width: 60, height: 60)
nc.labels = [Elkrb::Graph::Label.new(text: "C")]

nd = Elkrb::Graph::Node.new(id: "d", width: 60, height: 60)
nd.labels = [Elkrb::Graph::Label.new(text: "D")]

force_graph.children = [center, na, nb, nc, nd]
force_graph.edges = [
  Elkrb::Graph::Edge.new(id: "e1", sources: ["center"], targets: ["a"]),
  Elkrb::Graph::Edge.new(id: "e2", sources: ["center"], targets: ["b"]),
  Elkrb::Graph::Edge.new(id: "e3", sources: ["center"], targets: ["c"]),
  Elkrb::Graph::Edge.new(id: "e4", sources: ["center"], targets: ["d"]),
  Elkrb::Graph::Edge.new(id: "e5", sources: ["a"], targets: ["b"]),
  Elkrb::Graph::Edge.new(id: "e6", sources: ["c"], targets: ["d"]),
]

force_result = Elkrb.layout(force_graph, algorithm: "force")
dot_force = Elkrb.export_dot(
  force_result,
  graph_name: "ForceDirected",
  graph_attrs: { bgcolor: "white", splines: "true" },
  node_attrs: { shape: "ellipse", style: "filled", fillcolor: "lightblue" },
  edge_attrs: { color: "gray", arrowsize: 0.8 },
)
puts dot_force
puts "\n"

# Example 4: Write to file
puts "Example 4: Saving to File"
puts "=" * 50

output_file = "output_graph.dot"
File.write(output_file, dot_output)
puts "DOT file saved to: #{output_file}"
puts "You can render it with Graphviz:"
puts "  dot -Tpng #{output_file} -o output_graph.png"
puts "  dot -Tsvg #{output_file} -o output_graph.svg"
puts "\n"

puts "Demo complete!"
puts "All graphs have been laid out and exported to DOT format."
puts "Note: This is a pure Ruby implementation with no runtime Graphviz dependency."
