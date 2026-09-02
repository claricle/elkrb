# spec/support/invariants.rb
# frozen_string_literal: true

# Each matcher under invariants/ registers itself here at load time
# (`INVARIANTS << :name`), so this array is appended to after assignment
# and freezing it raises FrozenError on the first matcher loaded.
INVARIANTS = [] # rubocop:disable Style/MutableConstant

# The geometry every invariant reads, in one place. Two matchers had a
# byte-identical private copy of this, differing only in the parameter name.
#
# `|| 0.0` is a legitimate default here, not a papered-over nil: ELK leaves
# width and height optional, and an unsized node genuinely occupies a
# zero-sized box at its position.
module InvariantGeometry
  module_function

  def box(node)
    [node.x || 0.0, node.y || 0.0, node.width || 0.0, node.height || 0.0]
  end
end
