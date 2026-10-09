# spec/support/invariants/have_labels_inside_owner.rb
# frozen_string_literal: true

require_relative "../invariants"

# A node label whose placement names INSIDE is owner-relative and lies within
# the owner's own box: (0, 0) to (width, height). Labels with no placement
# option, and OUTSIDE labels, are not constrained.
RSpec::Matchers.define :have_labels_inside_owner do
  match do |graph|
    @offenders = []
    walk(graph, "root")
    @offenders.empty?
  end

  failure_message { "labels outside their owner: #{@offenders.join(', ')}" }

  define_method(:inside_placement?) do |node|
    options = node.layout_options || {}
    %w[elk.nodeLabels.placement node.label.placement label.placement]
      .filter_map { |key| options[key] || options[key.to_sym] }
      .any? { |value| value.to_s.upcase.include?("INSIDE") }
  end

  define_method(:escapes?) do |node, label|
    x, y, width, height = InvariantGeometry.box(label)
    _, _, node_width, node_height = InvariantGeometry.box(node)
    x.negative? || y.negative? ||
      (x + width) > node_width || (y + height) > node_height
  end

  define_method(:escaping_labels) do |node, node_path|
    (node.labels || []).each_with_index.filter_map do |label, i|
      "#{node_path}/labels[#{i}]" if escapes?(node, label)
    end
  end

  define_method(:walk) do |owner, path|
    (owner.children || []).each do |node|
      node_path = "#{path}/#{node.id}"
      if inside_placement?(node)
        @offenders.concat(escaping_labels(node,
                                          node_path))
      end
      walk(node, node_path)
    end
  end
end

INVARIANTS << :have_labels_inside_owner
