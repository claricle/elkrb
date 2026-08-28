# 33 — Performance leftovers
Slice S26 · branch `fix/s26-perf`

Can start after 24 (S18) — the libavoid expansion cap and bounding box this
item verifies are added there, and there is nothing to verify before. The XD
gate needs 02 (S0b). It cannot CLOSE until 12 (S8), 20 (S14) and 21 (S15) are
in `v2`: step 4 measures the three budgets on a base that already contains the
iterative layered phases, the stress BFS and the force rewrite. Blocks the
START of 35 (S27b, which lists this item among the slices that must be
complete before the consumer contract is asserted) and of 37 (S30, the final
slice). Small (~150 lines). Not breaking — this item changes no layout
behaviour at all.

## Facts

RC16 names five performance defects. **Four are fixed elsewhere and
this item only asserts them; none is re-fixed here:**

- Recursive DFS in `layered/cycle_breaker.rb:51` and
  `layered/layer_assigner.rb:46` overflows the stack (layered-11).
  Fixed by 12 (S8), which makes both iterative. Verified still broken at
  `v2` (a008889) on 2026-08-21: a 4000-node chain raises
  `SystemStackError`.
- `force.rb:107-108` rescans `graph.children.index { |n| n.id == ... }`
  twice per edge on every one of 300 iterations (force-family-15). Fixed
  by 11 (S7)'s `NodeIndex`. A 100-node chain takes **2.55 s** at `v2`.
- `stress.rb` calls `calculate_stress` twice per pass — `:38` and `:40`,
  where the `:38` value always equals the previous pass's `:40` — and
  computes shortest paths by Floyd–Warshall at `:89-100`
  (force-family-14). Fixed by 20 (S14), which computes stress once per
  pass and switches to BFS per source. A 100-node chain takes
  **12.77 s** at `v2`.
- `validate_command.rb:105` is O(E·N) (gap3-12). Fixed by 26 (S20).

The fifth is libavoid's unbounded A\*: `find_path`'s
`while open_set.any?` (`libavoid.rb:166`) has no bounding box and no
expansion cap (spore-libavoid-vertiflex-2). 24 (S18) adds both. This
item is where the bound is proven to bite.

`benchmarks/elkrb_benchmark.rb` is 145 lines and takes no arguments —
there is no `ARGV` or `OptionParser` reference in the file. It hardcodes
a 5 s warm-up timeout (`run_with_timeout(5)` at `:52`, method at
`:99-104`), 10 timed iterations per algorithm (`:64-70`), and writes
`benchmarks/results/elkrb_results.json` and `elkrb_summary.json`
(`:115-140`). `Rakefile:16-18` shells `benchmark:elkrb` to it. Nothing in
it can fail a build.

`.rspec` at `v2` is three lines — `--require spec_helper`, `--color`,
`--format documentation`. There is no tag exclusion. `.github/workflows/rake.yml`
delegates to `metanorma/ci`'s `generic-rake`, and 04 (S28) makes
`bundle exec rake` mean spec + rubocop. So an unexcluded perf spec runs
on every CI job of every later PR.

`benchmarks/results/elkrb_results.json` and `elkrb_summary.json` are
**tracked in git** at `v2`, while the plan's test strategy says benchmark
results are generated and never checked in. Noted, not acted on — see
step 4.

## Do

1. `benchmarks/elkrb_benchmark.rb`: add `--assert-max-ms`. Given the
   flag, the run exits non-zero when any measured average exceeds the
   budget, naming the graph and the algorithm. Without it the script
   behaves exactly as today — the flag is opt-in, so `rake benchmark:elkrb`
   is unchanged.
2. New `:perf`-tagged spec (one file, e.g.
   `spec/elkrb/performance_spec.rb`) with three rows, each built in the
   spec from JSON: **layered 4000-node chain**, **stress 200 nodes**,
   **force 100 nodes**. Each asserts a wall-clock budget.
3. `.rspec`: add the tag exclusion so the perf rows are out of the
   default run and out of CI. Prove it: `bundle exec rspec` must not
   execute them, and `bundle exec rspec --tag perf` must.
4. Choose the three budgets by **measuring on the branch's base**, not
   from this file. The base must already contain 12 (S8, layered
   iterative), 20 (S14, stress BFS) and 21 (S15, the force rewrite) —
   21 is not in this item's formal depends-on, so check
   `git log origin/v2` for it before picking the force number and record
   what you found. Budgets sit above the measured value with headroom;
   a budget that a warm laptop only just clears is a flaky CI job
   waiting to happen.
5. Prove libavoid's bound bites. Drive the repro that used to spin — a
   source and target whose offset is not a multiple of the grid step —
   through `find_path` under a timeout and assert it returns. This is
   the executable half of the item; without it "libavoid bounds
   verified" is a claim, not a check.
6. `benchmarks/results/*.json` being tracked contradicts the plan's test
   strategy. Do **not** delete them unilaterally. Say so in the report
   and let the maintainer rule; if they agree, gitignore the directory
   and `git rm --cached` the two files in this PR.

## Done when

- `bundle exec rake` green, and its runtime is unchanged — the perf rows
  do not execute (check the example count before and after).
- `bundle exec rspec --tag perf` runs exactly the three rows and passes.
- Each of the three budgets was measured on the branch's base and the
  measurement is in the report next to the budget.
- `bundle exec ruby benchmarks/elkrb_benchmark.rb --assert-max-ms <n>`
  exits non-zero for a deliberately tiny `<n>` and zero for a generous
  one. Prove both directions — a gate that never fails is not a gate.
- The libavoid bound spec returns instead of timing out.
- The 4000-node layered chain lays out without `SystemStackError`
  (it raises one at `v2`).

Mandatory gates: thermo-nuclear → execution-diff → Codex → copilot-review.
**dependency-contract-check is not required and the plan must say so:**
the benchmark script is ours and runs in-process; no external boundary
is crossed.

**execution-diff intended differences: none.** Driver
`bundle exec rake "corpus:dump[<dir>]"` (quoted) on the branch's base ref
— its merge-base with `v2`, or the `int/s26` stack base while 24 is
unmerged — and again on the branch, then `diff -r`. Every dump file must
be byte-identical. This item adds a flag and a tagged spec; it touches no
algorithm. Any diff at all is a bug. The rake exit status is
informational, never chain on it.

No `## Breaking` section — nothing observable changes.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`benchmarks/elkrb_benchmark.rb`, `.rspec`,
`spec/elkrb/performance_spec.rb` (new), and — only on the maintainer's
ruling — `.gitignore` plus the two tracked files under
`benchmarks/results/`.
