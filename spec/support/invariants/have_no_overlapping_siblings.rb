# spec/support/invariants/have_no_overlapping_siblings.rb
# frozen_string_literal: true

require_relative "../invariants"

RSpec::Matchers.define :have_no_overlapping_siblings do
  match do |graph|
    @overlaps = []
    check_level(graph)
    @overlaps.empty?
  end

  failure_message { @overlaps.join("\n") }

  # Checks `node`'s own children against each other, then recurses into
  # every child's children — covers every nesting depth, not just the root
  # and its immediate grandchildren.
  define_method(:check_level) do |node|
    siblings = node.children || []
    siblings.combination(2).each do |a, b|
      @overlaps << "#{a.id} overlaps #{b.id}" if strictly_overlap?(a, b)
    end
    siblings.each { |child| check_level(child) }
  end

  # `|| 0.0` on width/height is a legitimate geometric default (Decision 5:
  # an unsized leaf is a zero-size rectangle at its position). `|| 0.0` on
  # x/y is a convenience, not a correctness claim: a genuinely missing
  # position is `have_finite_coordinates`'s violation to report, run
  # alongside this matcher in the same spec — this one stays robust rather
  # than raising on it.

  define_method(:strictly_overlap?) do |a, b|
    ax, ay, aw, ah = InvariantGeometry.box(a)
    bx, by, bw, bh = InvariantGeometry.box(b)
    ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah
  end
end

INVARIANTS << :have_no_overlapping_siblings
