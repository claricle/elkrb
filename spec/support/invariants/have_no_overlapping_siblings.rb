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

  # A zero-AREA node cannot strictly overlap anything, and the four
  # comparisons alone do not say that: a point at (5,5) with no size, sat
  # inside a 10x10 sibling, satisfied all four and was reported as an
  # overlap. That contradicts the convention directly above -- an unsized
  # leaf is a zero-size rectangle, and a rectangle with no interior
  # intersects nothing in a positive area. It also contradicted
  # `omit_size_for_unsized_input`, which exists to keep unsized nodes
  # unsized: the two invariants run over the same golden cases, so
  # `sizeless` satisfying one had to mean failing the other. The area
  # test comes first, so `strictly_` is what the predicate now means.
  define_method(:both_have_area?) do |a, b|
    InvariantGeometry.area?(a) && InvariantGeometry.area?(b)
  end

  define_method(:strictly_overlap?) do |a, b|
    return false unless both_have_area?(a, b)

    ax, ay, aw, ah = InvariantGeometry.box(a)
    bx, by, bw, bh = InvariantGeometry.box(b)
    ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah
  end
end

INVARIANTS << :have_no_overlapping_siblings
