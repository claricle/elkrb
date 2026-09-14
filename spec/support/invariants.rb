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

  # Whether the node's box has any interior. An unsized leaf, and a node
  # with one dimension at zero, occupy no area -- nothing is strictly
  # inside them and they are strictly inside nothing.
  def area?(node)
    (node.width || 0.0).positive? && (node.height || 0.0).positive?
  end
end

# The key-normalization every invariant matcher's INPUT walk needs, in one
# place. `preserve_ids_and_endpoints` and `omit_size_for_unsized_input` both
# read their `input_hash` argument with String-keyed lookups
# (`input_level["children"]`, `input_owner["width"]`, ...), but
# `Elkrb.layout` itself documents and accepts a Symbol-keyed Hash too (see
# `Elkrb.layout`'s own `@example` in lib/elkrb.rb) -- a caller who passes
# one to a matcher got every String-keyed lookup below silently returning
# nil, which is indistinguishable from "not declared" and made both
# matchers report false violations or find none at all.
module InvariantInputNormalizer
  module_function

  # Re-keys Symbol keys to String, recursively, WITHOUT touching values,
  # nils, or key presence/absence -- only the key type changes. That
  # preserves the declared-vs-absent distinction
  # `omit_size_for_unsized_input#check_dimensions` depends on
  # (`input_owner.key?("width")`, and a declared-but-empty
  # `"children": []` counting as a compound per Decision 5) exactly as the
  # caller wrote it; round-tripping through the real `Graph`/`Node` model
  # instead (as `GoldenComparator.to_comparable` does for a laid-out
  # result) was tried and rejected here because lutaml-model omits an
  # unset or empty collection attribute from `to_json` entirely, which
  # would make `key?` true fewer times than the caller's own Hash did, not
  # the same.
  def stringify_keys(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys(v) }
    when Array
      obj.map { |v| stringify_keys(v) }
    else
      obj
    end
  end
end
