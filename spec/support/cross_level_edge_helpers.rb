# frozen_string_literal: true

module CrossLevelEdgeHelpers
  def layout_cross_level_graph(graph)
    Elkrb.layout(graph, algorithm: "layered")
  end

  def capture_elkrb_warnings
    output = StringIO.new
    previous = Elkrb.logger
    Elkrb.logger = Logger.new(output, level: Logger::WARN)
    yield
    output.string
  ensure
    Elkrb.logger = previous
  end

  def nested_coordinates(owner, path = "root", result = {})
    (owner.children || []).each do |node|
      node_path = "#{path}/#{node.id}"
      result[node_path] = [node.x, node.y]
      nested_coordinates(node, node_path, result)
    end
    result
  end

  def hash_node_positions(owner, path = "root", result = {})
    (owner["children"] || []).each do |node|
      node_path = "#{path}/#{node['id']}"
      result[node_path] = node.values_at("x", "y")
      hash_node_positions(node, node_path, result)
    end
    result
  end

  def absolute_rectangle(graph, boundary_id, member_id)
    boundary = child_by_id(graph, boundary_id)
    member = child_by_id(boundary, member_id)
    x, y = absolute_origin(boundary, member)
    Elkrb::Geometry::Rectangle.new(x, y, member.width, member.height)
  end

  def child_by_id(owner, id)
    owner.children.find { |node| node.id == id }
  end

  def absolute_origin(boundary, member)
    [boundary.x + member.x, boundary.y + member.y]
  end

  def point_on_border?(point, rectangle)
    epsilon = 1e-6
    on_horizontal_border?(point, rectangle, epsilon) ||
      on_vertical_border?(point, rectangle, epsilon)
  end

  def on_horizontal_border?(point, rectangle, epsilon)
    boundary?(point.y, rectangle.y, rectangle.height, epsilon) &&
      within?(point.x, rectangle.x, rectangle.width, epsilon)
  end

  def on_vertical_border?(point, rectangle, epsilon)
    boundary?(point.x, rectangle.x, rectangle.width, epsilon) &&
      within?(point.y, rectangle.y, rectangle.height, epsilon)
  end

  def boundary?(coordinate, origin, length, epsilon)
    near?(coordinate, origin, epsilon) ||
      near?(coordinate, origin + length, epsilon)
  end

  def within?(coordinate, origin, length, epsilon)
    coordinate.between?(origin - epsilon, origin + length + epsilon)
  end

  def near?(left, right, epsilon)
    (left - right).abs <= epsilon
  end
end
