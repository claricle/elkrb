# spec/support/invariants/contain_children_within_bounds.rb
# frozen_string_literal: true

require_relative "../invariants"

RSpec::Matchers.define :contain_children_within_bounds do |padding = 0|
  match do |graph|
    @violations = []
    check_level(graph, padding)
    @violations.empty?
  end

  failure_message { @violations.join("\n") }

  # Same `|| 0.0` convention as `have_no_overlapping_siblings`: correct
  # for width/height (Decision 5).
  define_method(:check_level) do |node, pad|
    width = node.width || 0.0
    height = node.height || 0.0
    (node.children || []).each do |child|
      out_of_bounds = escapes?(child, width, height, pad)
      @violations << "#{child.id} escapes #{node.id}'s bounds" if out_of_bounds

      check_level(child, pad)
    end
  end

  # The `|| 0.0` on x/y is a robustness convenience, not a correctness
  # claim — `have_finite_coordinates` owns flagging a genuinely missing
  # position. On width/height it is the Decision 5 convention, as above.
  define_method(:box) do |child|
    [child.x || 0.0, child.y || 0.0, child.width || 0.0, child.height || 0.0]
  end

  define_method(:escapes?) do |child, width, height, pad|
    cx, cy, cw, ch = box(child)
    cx < pad || cy < pad || (cx + cw) > (width - pad) ||
      (cy + ch) > (height - pad)
  end
end

INVARIANTS << :contain_children_within_bounds
