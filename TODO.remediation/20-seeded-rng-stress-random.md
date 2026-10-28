# 20 — Seeded RNG, stress edge length, random
Slice S14 · branch `fix/s14-seeded-rng-stress`

Can start after 10 (S6 moves `force.rb`/`stress.rb`/`random.rb` off
`@options` and onto the resolver — this item changes what those reads
return, not where they come from) and 11 (S7's `NodeIndex`, which the
new stress BFS resolves endpoints through). The goldens `random3` and
`stress_path4` and the `be_deterministic` matcher come from 03 (S0a);
the XD gate needs 02 (S0b's `corpus:dump` driver). Blocks the START of
21 (S15) — that item rewrites `force.rb` on top of the `rng` added
here — and blocks the CLOSE of 33 (S26), whose stress budget only
means anything once the BFS lands. Medium (~200 lines). Not on the
plan's `## Breaking` carrier list; see `## Done when`.

## Facts

Measured 2026-08-21 against `v2` (a008889).

force and random draw from `Kernel#rand`, so the same graph laid out
twice gives different coordinates (elk-compat-27; force-family-8):

```sh
bundle exec ruby -relkrb -e 'g=->{ {id:"r",children:(0...5).map{|i|{id:"n#{i}",width:30,height:30}}} }; p Elkrb.layout(g[],algorithm:"random").children.map{|c|[c.x,c.y]} == Elkrb.layout(g[],algorithm:"random").children.map{|c|[c.x,c.y]}'
# false   (same for algorithm:"force")
```

There are exactly four `rand` sites under `lib/elkrb/layout/algorithms`
— `force.rb:58-59` inside `initialize_positions`, and `random.rb:31-32`
(`git grep -n '\brand\b' a008889 -- lib/elkrb/layout/algorithms`).
Nothing in `lib/` calls `srand` or `Random.new`.

`Algorithms::Random` (`random.rb:12`) shadows `::Random` inside the
`Algorithms` namespace (force-family-9). A bare `Random.new` there
resolves to the algorithm class.

stress collapses every component. `stress.rb:85-86` sets the adjacent
ideal distance to `1.0`, and Floyd–Warshall turns hop count into pixels
(force-family-2). A 30-node chain of 30×30 nodes:

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({id:"r",children:(0...30).map{|i|{id:"n#{i}",width:30,height:30}},edges:(1...30).map{|i|{id:"e#{i}",sources:["n#{i-1}"],targets:["n#{i}"]}}},algorithm:"stress"); c=r.children; puts "#{r.width.round}x#{r.height.round} adjacent=#{Math.hypot(c[0].x-c[1].x,c[0].y-c[1].y).round(2)} overlaps=#{c.combination(2).count{|a,b| a.x<b.x+30&&b.x<a.x+30&&a.y<b.y+30&&b.y<a.y+30}}/435"'
# 61x82 adjacent=1.0 overlaps=435/435
```

stress is also slow by construction (force-family-14): shortest paths
are Floyd–Warshall at `stress.rb:89-100` (O(n³)), and the loop at
`stress.rb:37-44` calls `calculate_stress` twice per pass — `:38` and
`:40` — although the `:38` value always equals the previous pass's
`:40` value. A 100-node chain takes **12.77 s**
(`Benchmark.realtime { Elkrb.layout(chain100, algorithm: "stress") }`).

`base_algorithm.rb` at `v2`: `protected` at `:84`, `option` at `:91-94`,
`layout` at `:38`. 14 (S10) and 15 (S10b) both rewrite `layout`, so
`rng` goes below `option` and nowhere near it.

Corpus reach is narrow. Every `spec/fixtures/corpus/*.json` case S0b
authors declares `"layered"`, and the three `spec/fixtures/*.json` files
default to layered. The only dump files this item can move are the six
cross-validation cases that declare these algorithms:
`elkjs_layouters_force`, `elkjs_layouters_stress`,
`elkjs_layouters_random`, `java_elk_force`, `java_elk_stress`,
`java_elk_random`.

## Do

1. `base_algorithm.rb`: add `rng` **directly below `option`** in the
   protected section (after `:94`), not near `layout` —
   `@rng ||= ::Random.new(option("elk.randomSeed").to_i)`. The leading
   `::` is load-bearing: `Algorithms::Random` shadows the constant.
   The registry row for `elk.randomSeed` (default 1) exists from 08 (S4).
2. `random.rb:31-32` and `force.rb:58-59`: `rand` → `rng.rand`. Change
   nothing else in `force.rb` — 21 rewrites that file whole.
3. Add a guard spec that greps `lib/elkrb/layout/algorithms/**/*.rb` for
   `\brand\b` outside `rng.rand` and fails on a hit. It must be red
   before step 2 (four sites) and green after.
4. `stress.rb`: ideal distance per hop = `option("elk.stress.desiredEdgeLength")`,
   **multiplied** by the hop count. Set that row's default to `100.0` on
   its own line in `lib/elkrb/options/registry.rb` (rows are one per
   line, sorted by id — edit in place, never append). 08 registered the
   id; nothing reads it yet and the code carries no literal for it, so
   this item is where the value lands.
5. `stress.rb`: scale the initial placement radius in
   `initialize_positions` (`:54-64`) by the same desired edge length, so
   the start state is on the same scale as the targets.
6. Replace Floyd–Warshall (`stress.rb:89-100`) with one BFS per source
   over the unweighted adjacency, resolving endpoints through the
   `NodeIndex` 11 introduced. Hop counts are unchanged — only the cost is.
7. Compute stress once per pass: carry `new_stress` (`:40`) into the next
   pass as `old_stress` (`:38`). The convergence break at `:43` keeps its
   meaning and `elk.stress.epsilon` keeps its default.
8. Do not touch `collect_all_edges` (`force.rb:154-161`,
   `stress.rb:165-172`) — 14 (S10) restricts both to `graph.edges`. If 14
   is already in the base, keep its restriction intact.

**Specs first**, new files `spec/elkrb/layout/algorithms/random_spec.rb`
and `spec/elkrb/layout/algorithms/stress_spec.rb` (neither exists at
`v2`), all driven from JSON through `Elkrb.layout`:

- two `random` layouts of the same JSON are byte-identical; with
  `"elk.randomSeed":2` on the graph they differ.
- `be_deterministic` for random, stress and force.
- stress on a 30-node chain: every adjacent pair 100 ± 10 apart, and
  **0** overlapping pairs (435/435 today).
- stress on 200 nodes finishes in under 2 s.
- goldens `random3` and `stress_path4` at `tier: :structural`, un-pended
  in their own `it` blocks in `spec/elkrb/golden_spec.rb`.

## Done when

- `bundle exec rake` is green (04/S28 is in `v2` by then, so green means
  spec + rubocop).
- The determinism repro above prints `true` for both `random` and
  `force`, and prints `false` when the graph carries
  `"elk.randomSeed":2`.
- The stress repro above prints `adjacent=100.0 ± 10` and
  `overlaps=0/435`.
- `bundle exec ruby -relkrb -rbenchmark -e '...chain200...'` lays out
  stress in under 2 s (12.77 s at 100 nodes today).
- The `rand` guard spec passes and `git grep -n '\brand\b' -- lib/elkrb/layout/algorithms`
  shows only `rng.rand`.
- `bundle exec rspec spec/elkrb/golden_spec.rb` has no failures and
  `random3`/`stress_path4` are no longer `pending`.

Mandatory gates: thermo-nuclear → execution-diff → Codex → copilot-review.
**dependency-contract-check is not required and the plan must say so:**
nothing here crosses a boundary we do not own — `::Random` is stdlib and
its contract is exercised directly by the determinism specs.

**execution-diff intended differences** — driver
`bundle exec rake "corpus:dump[<dir>]"` (quoted) on the branch's base ref
— its merge-base with `v2`, or the `int/s14` stack base while 10 and 11
are unmerged — and again on the branch, then `diff -r`. Exactly six dump
files change:
`elkjs_layouters_force`, `elkjs_layouters_stress`,
`elkjs_layouters_random`, `java_elk_force`, `java_elk_stress`,
`java_elk_random`. Every other file is byte-identical. The rake exit
status is informational — never chain on it.

The plan's `## Breaking` carrier list (S3, S3b, S5, S7, S8, S9, S10,
S10b, S11, S12, S13, S13b, S16, S17, S19) does not include this slice,
and 37 (S30) assembles `CHANGELOG.md` from those sections alone. Yet
every force, stress and random coordinate changes here, and the output
becomes reproducible where it was not. Put a `## Breaking` section in
the report anyway so 37 can see it; the maintainer decides whether it
lands in the 2.0.0 block. Do not edit `CHANGELOG.md`.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`lib/elkrb/layout/algorithms/base_algorithm.rb`,
`lib/elkrb/layout/algorithms/random.rb`,
`lib/elkrb/layout/algorithms/force.rb` (two lines only),
`lib/elkrb/layout/algorithms/stress.rb`,
`lib/elkrb/options/registry.rb` (one row),
`spec/elkrb/layout/algorithms/{random,stress}_spec.rb` (new),
`spec/elkrb/golden_spec.rb` (two `it` blocks).
