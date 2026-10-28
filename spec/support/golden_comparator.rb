# spec/support/golden_comparator.rb
# frozen_string_literal: true

# GoldenComparator had grown past 1000 lines once already and was split at
# its module boundary then (see `git log --follow -- spec/support/
# golden_comparator.rb`, "split the golden helper at its module boundary");
# further mutation-pinning work pushed the comparator itself past 1000
# lines the same way. This file is now only the loader; the three tiers
# (`:exact`, `:structural`, `:smoke`) each get their own file under
# golden_comparator/, plus a shared.rb for the id-matching and
# edge-endpoint primitives more than one tier depends on.
require_relative "golden_comparator/shared"
require_relative "golden_comparator/exact"
require_relative "golden_comparator/structural"
require_relative "golden_comparator/smoke"
