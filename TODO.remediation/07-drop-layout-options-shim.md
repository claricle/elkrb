# 07 — Drop the LayoutOptions shim
Slice S3b · branch `fix/s3b-drop-options-shim`

Can start after 06 (S3 — the shim only exists once `attribute
:layout_options, :hash` has replaced the typed class, and this item deletes
what 06 introduced) and 11 (S7 — it edits
`spec/elkrb/layout/edge_router_spec.rb:614-615`, the two lines directly under
the `:612` `LayoutOptions.new` site this item rewrites, so landing them out of
order guarantees a conflict). The XD gate needs 02 (S0b's `corpus:dump`).
**Blocks the START of 14 (S10), 16 (S11), 17 (S12), 19 (S13b), 23 (S17), 24
(S18), 28 (S22) and 30 (S24)** — it must merge before any of them begins,
because the shim call sites live in the very spec and example files those
items rewrite, and a rewrite on top of a rewrite is a merge conflict for no
gain. Parallel with 08 (S4), 09 (S5), 10 (S6), 12 (S8) and 13 (S9) only.
Medium (~200 lines, mechanical). **BREAKING.**

## Facts

Measured against `v2` (a008889).

`Elkrb::Graph::LayoutOptions` is referenced 98 times across 15 files under
`spec/` and `examples/` — 97 `LayoutOptions.new` calls in 14 files, plus one
class reference at `spec/elkrb/graph/layout_options_spec.rb:5`:

```sh
git grep -o "LayoutOptions" a008889 -- spec examples | wc -l   # 98
git grep -c "LayoutOptions.new" a008889 -- spec examples       # 14 files
```

Per file at `v2`: `self_loop_spec.rb` 12, `vertiflex_spec.rb` 12,
`libavoid_spec.rb` 12, `examples/self_loop_demo.rb` 11,
`label_placer_spec.rb` 10, `edge_router_spec.rb` 9,
`topdown_packing_spec.rb` 8, `rectpacking_spec.rb` 5, `mrtree_spec.rb` 5,
`hierarchical_processor_spec.rb` 4, `radial_spec.rb` 4,
`examples/spline_routing_demo.rb` 2, `examples/port_constraints_demo.rb` 2,
`dot_serializer_spec.rb` 1.

The audit and the original card say 89 sites. That was 6ac367c; slice 1
(a008889, the `v2` seed) added 8 more. **Re-count on the branch base before
starting** — do not carry a stale number into the report.

After 06 lands, exactly four references remain in `lib/`:

```sh
git grep -n "LayoutOptions" a008889 -- lib/elkrb/graph/graph.rb \
  lib/elkrb/layout/algorithms/topdown_packing.rb \
  lib/elkrb/layout/algorithms/vertiflex.rb
# graph.rb:15   attribute :layout_options, LayoutOptions      <- 06 changes to :hash
# graph.rb:52   @layout_options ||= LayoutOptions.new         <- 06 changes to {}
# topdown_packing.rb:133  # @param layout_opts [Hash, LayoutOptions] The layout options
# vertiflex.rb:85         # @param layout_opts [Hash, LayoutOptions] The layout options
```

06 clears the two `graph.rb` lines. The two YARD `@param` comments survive it
— they are what stops this item's `grep -rn LayoutOptions lib` acceptance
coming back empty.

The shim 06 ships is larger than a bare `::Hash` subclass (99 lines, not 20):
`[]`/`[]=` stringify keys, `merge` mutates self and returns self, and a
private `LEGACY_KWARG_ELK_KEYS` table translates old typed keyword names to
ELK ids with a once-per-key deprecation warning. All of that goes with the
class. The rewrite target is a plain string-keyed `::Hash` literal, so any
call site that relied on the legacy-kwarg translation must be written with
the ELK id directly.

Nothing in `lib/` calls the shim after 06, so this item changes no runtime
behaviour. The corpus dump must come out byte-identical.

## Do

Design decision D1/D3, ruled: the constructor shim is a migration aid and
does not ship in 2.0. Do not re-decide it.

1. Delete `lib/elkrb/graph/layout_options.rb` and its require at
   `lib/elkrb.rb:13` (`require_relative "elkrb/graph/layout_options"`).
2. Edit the two YARD comments that still name the class —
   `lib/elkrb/layout/algorithms/topdown_packing.rb:133` and
   `lib/elkrb/layout/algorithms/vertiflex.rb:85` —
   `@param layout_opts [Hash, LayoutOptions]` → `@param layout_opts [Hash]`.
   Comment-only; no code line changes.
3. That is the entire `lib/` diff: two deletions and two comment edits.
   `Graph#initialize` already reads `@layout_options ||= {}` from 06.
4. Rewrite every `LayoutOptions.new(...)` site in `spec/` and `examples/` to
   a plain string-keyed Hash. Mechanical:
   `LayoutOptions.new("elk.x" => 1)` → `{ "elk.x" => 1 }`;
   `LayoutOptions.new(algorithm: "x")` → `{ "elk.algorithm" => "x" }` — use
   the ELK id the shim's legacy table would have translated to, since the
   table goes away with the class; `LayoutOptions.new` → `{}`. Include
   spec/example comments that name the class.
5. The 06 `layout_options_spec` examples that exercised the shim constructor
   (`LayoutOptions.new("elk.x" => 1)`, `.new({…})`, `.new(algorithm:)`,
   `Graph.new(layout_options: LayoutOptions.new(…))`) become plain-Hash
   examples with the same assertions. Delete the shim's docstring pin only if
   it covered the shim alone — the "`text` and `elements` are reserved"
   sentence belongs to the models and must survive somewhere item 30 (S24)
   can carry into the README.
6. Specs first: rewrite the `layout_options_spec` examples (plain Hash in,
   same results out), then the mechanical sweep, running `bundle exec rspec`
   per directory as you go.

Do not touch: any `lib/` file beyond the two deletions and the two
comment-only YARD edits; the *values* in spec expectations — only the
constructor form changes; README (item 30); `CHANGELOG.md` (item 37).

## Done when

- `grep -rn LayoutOptions lib spec examples` → **no output**.
- `bundle exec ruby -relkrb -e 'p defined?(Elkrb::Graph::LayoutOptions)'`
  → `nil`.
- `bundle exec rake` green (spec + rubocop; 04/S28 made that the bar). The
  example count matches the branch base — this item adds and removes none.
- The `lib/` diff is exactly two file deletions plus two changed comment
  lines. Check it by reading `git diff --stat` against the base, not by
  assuming.

Gates, in this order: `thermo-nuclear-review` → `execution-diff`
(**mandatory**) → Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. **No dependency-contract-check** — nothing here
crosses a boundary we do not own. Say that in the report rather than skipping
it silently.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s3b` stack base when 06 and 11 are still unmerged — and again on the
branch, then `diff -r` the two dump dirs. The rake exit status is
informational; never chain on it.

INTENDED execution-diff differences: **none.** The dumps must be
byte-identical across all 47 cases. Any difference means a spec-only rewrite
reached runtime, which is a bug.

The report carries: the site count rewritten per file (re-counted on the
branch base, not copied from here); confirmation that the two lib deletions
and the two comment-only YARD edits are the whole `lib/` diff; and a
`## Breaking` section — `Elkrb::Graph::LayoutOptions` no longer exists; pass a
plain string-keyed Hash.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then Gate B
(Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`lib/elkrb/graph/layout_options.rb` (deleted), `lib/elkrb.rb` (one require
removed), `lib/elkrb/layout/algorithms/topdown_packing.rb:133`,
`lib/elkrb/layout/algorithms/vertiflex.rb:85`, and the 15 spec/example files
listed in Facts.
