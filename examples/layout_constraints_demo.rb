#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/elkrb"

puts "=" * 70
puts "ElkRb Layout Constraints Demonstration"
puts "=" * 70
puts

# Example 1: Fixed Position Constraint
puts "Example 1: Fixed Position - API Gateway stays at top center"
puts "-" * 70

graph1 = Elkrb::Graph::Graph.new(id: "fixed_example")

# API Gateway fixed at (500, 100)
gateway = Elkrb::Graph::Node.new(
  id: "gateway",
  width: 120,
  height: 60,
  x: 500,
  y: 100,
  constraints: Elkrb::Graph::NodeConstraints.new(fixed_position: true),
)

# Other services positioned automatically
auth = Elkrb::Graph::Node.new(id: "auth", width: 100, height: 60)
user = Elkrb::Graph::Node.new(id: "user", width: 100, height: 60)

graph1.children = [gateway, auth, user]
graph1.edges = [
  Elkrb::Graph::Edge.new(id: "e1", sources: ["gateway"], targets: ["auth"]),
  Elkrb::Graph::Edge.new(id: "e2", sources: ["gateway"], targets: ["user"]),
]

result1 = Elkrb.layout(graph1, algorithm: "layered")

puts "Gateway position: (#{result1.children[0].x}, #{result1.children[0].y})"
puts "  Expected: (500.0, 100.0)"
puts "  Status: #{result1.children[0].x == 500 && result1.children[0].y == 100 ? '✓' : '✗'}"
puts

# Example 2: Alignment Constraint
puts "Example 2: Alignment - All databases aligned horizontally"
puts "-" * 70

graph2 = Elkrb::Graph::Graph.new(id: "alignment_example")

# Three databases, all aligned horizontally
db1 = Elkrb::Graph::Node.new(
  id: "db1",
  width: 80,
  height: 50,
  constraints: Elkrb::Graph::NodeConstraints.new(
    align_group: "databases",
    align_direction: "horizontal",
  ),
)

db2 = Elkrb::Graph::Node.new(
  id: "db2",
  width: 80,
  height: 50,
  constraints: Elkrb::Graph::NodeConstraints.new(
    align_group: "databases",
    align_direction: "horizontal",
  ),
)

db3 = Elkrb::Graph::Node.new(
  id: "db3",
  width: 80,
  height: 50,
  constraints: Elkrb::Graph::NodeConstraints.new(
    align_group: "databases",
    align_direction: "horizontal",
  ),
)

graph2.children = [db1, db2, db3]

result2 = Elkrb.layout(graph2, algorithm: "box")

y1 = result2.children[0].y
y2 = result2.children[1].y
y3 = result2.children[2].y

puts "Database positions:"
puts "  db1 y: #{y1}"
puts "  db2 y: #{y2}"
puts "  db3 y: #{y3}"
puts "  Aligned: #{y1 == y2 && y2 == y3 ? '✓' : '✗'}"
puts

# Example 3: Layer Constraint
puts "Example 3: Layer - Three-tier architecture"
puts "-" * 70

graph3 = Elkrb::Graph::Graph.new(id: "layer_example")

# Tier 0: Frontend
frontend = Elkrb::Graph::Node.new(
  id: "frontend",
  width: 100,
  height: 60,
  constraints: Elkrb::Graph::NodeConstraints.new(layer: 0),
)

# Tier 1: Backend
backend = Elkrb::Graph::Node.new(
  id: "backend",
  width: 100,
  height: 60,
  constraints: Elkrb::Graph::NodeConstraints.new(layer: 1),
)

# Tier 2: Database
database = Elkrb::Graph::Node.new(
  id: "database",
  width: 100,
  height: 60,
  constraints: Elkrb::Graph::NodeConstraints.new(layer: 2),
)

graph3.children = [frontend, backend, database]
graph3.edges = [
  Elkrb::Graph::Edge.new(id: "e1", sources: ["frontend"], targets: ["backend"]),
  Elkrb::Graph::Edge.new(id: "e2", sources: ["backend"], targets: ["database"]),
]

result3 = Elkrb.layout(graph3, algorithm: "layered")

puts "Layer positions (y coordinates):"
puts "  Frontend (layer 0): y = #{result3.children[0].y.round(1)}"
puts "  Backend (layer 1):  y = #{result3.children[1].y.round(1)}"
puts "  Database (layer 2): y = #{result3.children[2].y.round(1)}"
puts "  Ordered correctly: #{result3.children[0].y < result3.children[1].y && result3.children[1].y < result3.children[2].y ? '✓' : '✗'}"
puts

# Example 4: Relative Position Constraint
puts "Example 4: Relative Position - API next to backend service"
puts "-" * 70

graph4 = Elkrb::Graph::Graph.new(id: "relative_example")

# Backend service (positioned by algorithm)
backend_svc = Elkrb::Graph::Node.new(
  id: "backend_svc",
  width: 100,
  height: 60,
)

# API positioned 150px to the right of backend
offset = Elkrb::Graph::RelativeOffset.new(x: 150, y: 0)
api = Elkrb::Graph::Node.new(
  id: "api",
  width: 100,
  height: 60,
  constraints: Elkrb::Graph::NodeConstraints.new(
    relative_to: "backend_svc",
    relative_offset: offset,
  ),
)

graph4.children = [backend_svc, api]

result4 = Elkrb.layout(graph4, algorithm: "box")

backend_x = result4.children[0].x
api_x = result4.children[1].x
expected_offset = 150

puts "Backend position: x = #{backend_x}"
puts "API position:     x = #{api_x}"
puts "Offset:           #{(api_x - backend_x).round(1)} (expected: #{expected_offset})"
puts "Correct offset:   #{(api_x - backend_x - expected_offset).abs < 0.1 ? '✓' : '✗'}"
puts

# Example 5: Combined Constraints
puts "Example 5: Combined - Microservices architecture with multiple constraints"
puts "-" * 70

graph5 = Elkrb::Graph::Graph.new(id: "microservices")

# API Gateway (fixed position, layer 0)
gateway5 = Elkrb::Graph::Node.new(
  id: "api_gateway",
  width: 120,
  height: 60,
  x: 500,
  y: 100,
  constraints: Elkrb::Graph::NodeConstraints.new(
    fixed_position: true,
    layer: 0,
  ),
)

# Backend services (aligned, layer 1)
auth5 = Elkrb::Graph::Node.new(
  id: "auth_svc",
  width: 100,
  height: 60,
  constraints: Elkrb::Graph::NodeConstraints.new(
    layer: 1,
    align_group: "backend",
    align_direction: "horizontal",
  ),
)

user5 = Elkrb::Graph::Node.new(
  id: "user_svc",
  width: 100,
  height: 60,
  constraints: Elkrb::Graph::NodeConstraints.new(
    layer: 1,
    align_group: "backend",
    align_direction: "horizontal",
  ),
)

# Databases (aligned, layer 2, relative to services)
auth_db = Elkrb::Graph::Node.new(
  id: "auth_db",
  width: 80,
  height: 50,
  constraints: Elkrb::Graph::NodeConstraints.new(
    layer: 2,
    align_group: "databases",
    align_direction: "horizontal",
  ),
)

user_db = Elkrb::Graph::Node.new(
  id: "user_db",
  width: 80,
  height: 50,
  constraints: Elkrb::Graph::NodeConstraints.new(
    layer: 2,
    align_group: "databases",
    align_direction: "horizontal",
  ),
)

graph5.children = [gateway5, auth5, user5, auth_db, user_db]
graph5.edges = [
  Elkrb::Graph::Edge.new(id: "e1", sources: ["api_gateway"],
                         targets: ["auth_svc"]),
  Elkrb::Graph::Edge.new(id: "e2", sources: ["api_gateway"],
                         targets: ["user_svc"]),
  Elkrb::Graph::Edge.new(id: "e3", sources: ["auth_svc"], targets: ["auth_db"]),
  Elkrb::Graph::Edge.new(id: "e4", sources: ["user_svc"], targets: ["user_db"]),
]

result5 = Elkrb.layout(graph5, algorithm: "layered", "elk.direction" => "DOWN")

puts "Results:"
puts "  Gateway (fixed):     (#{result5.children[0].x}, #{result5.children[0].y})"
puts "  Backend services:"
puts "    auth: y = #{result5.children[1].y.round(1)}"
puts "    user: y = #{result5.children[2].y.round(1)}"
puts "    Aligned: #{result5.children[1].y == result5.children[2].y ? '✓' : '✗'}"
puts "  Databases:"
puts "    auth_db: y = #{result5.children[3].y.round(1)}"
puts "    user_db: y = #{result5.children[4].y.round(1)}"
puts "    Aligned: #{result5.children[3].y == result5.children[4].y ? '✓' : '✗'}"
puts

puts "=" * 70
puts "All examples completed successfully!"
puts "See docs/LAYOUT_CONSTRAINTS_GUIDE.md for detailed documentation"
puts "=" * 70
