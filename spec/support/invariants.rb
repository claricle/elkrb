# spec/support/invariants.rb
# frozen_string_literal: true

# Each matcher under invariants/ registers itself here at load time
# (`INVARIANTS << :name`), so this array is appended to after assignment
# and freezing it raises FrozenError on the first matcher loaded.
INVARIANTS = [] # rubocop:disable Style/MutableConstant
