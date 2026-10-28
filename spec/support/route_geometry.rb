# frozen_string_literal: true

# Geometry assertions for routed sections: whether a route ever enters a
# node's own interior. A route may touch the border (where an endpoint sits)
# but never pass through the interior.
module RouteGeometry
  # start_point, bend_points..., end_point as one ordered list.
  def route_path_points(section)
    [section.start_point] + (section.bend_points || []) + [section.end_point]
  end

  # Samples each leg of the routed section at `samples` points (inclusive
  # of both ends) and returns any sample that falls strictly inside `node`,
  # as [x, y] pairs -- empty means the whole path clears the node.
  def route_interior_crossings(section, node, samples: 25)
    route_path_points(section).each_cons(2).flat_map do |from_pt, to_pt|
      route_leg_samples(from_pt, to_pt, samples)
        .select { |x_pos, y_pos| route_inside_node?(x_pos, y_pos, node) }
    end
  end

  def route_leg_samples(from_pt, to_pt, samples)
    (0..samples).map do |step|
      fraction = step.to_f / samples
      [from_pt.x, from_pt.y].zip([to_pt.x, to_pt.y]).map do |from, to|
        from + ((to - from) * fraction)
      end
    end
  end

  def route_inside_node?(x_pos, y_pos, node, tolerance = 1e-6)
    x_pos > node.x + tolerance && x_pos < node.x + node.width - tolerance &&
      y_pos > node.y + tolerance && y_pos < node.y + node.height - tolerance
  end
end

RSpec.configure { |c| c.include RouteGeometry }
