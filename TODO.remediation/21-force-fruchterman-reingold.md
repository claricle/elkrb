# 21 — Force rewrite (Fruchterman–Reingold)
Slice S15 · branch `fix/s15-force-fr`

Can start after 14 (S10 restricts `Force#collect_all_edges` to this level's
edges) and 20 (S14 adds `rng` and switches `force.rb:58-59` to it) — this item
rewrites the whole file, so both edits must already be in the base or they are
lost. The golden `force_tri` comes from 03 (S0a); the XD gate needs 02 (S0b).
Blocks the START of 30 (S24's README, which describes force layout) and the
CLOSE of 33 (S26) — 33 writes a budget against the force runtime this item
sets, so it must not pick that number until this is in `v2`. Medium–large
(~300 lines). Not on the plan's `## Breaking` carrier list; see
`## Done when`.

## Facts

Measured 2026-08-21 against `v2` (a008889).

Force is inert. `DEFAULT_TEMPERATURE = 0.001` at `force.rb:22` is used
as an absolute per-iteration displacement cap in pixels, so 300 decaying
iterations move nothing (force-family-1). The output is the random
scatter from `initialize_positions`:

```sh
bundle exec ruby -relkrb -e 'g=->{ {id:"r",children:(0...30).map{|i|{id:"n#{i}",width:30,height:30}},edges:(1...30).map{|i|{id:"e#{i}",sources:["n#{i-1}"],targets:["n#{i}"]}}} }; srand 1; a=Elkrb.layout(g[],algorithm:"force","iterations"=>0).children.map{|c|[c.x,c.y]}; srand 1; b=Elkrb.layout(g[],algorithm:"force").children.map{|c|[c.x,c.y]}; puts "max move: %.3f px" % a.zip(b).map{|(x1,y1),(x2,y2)| Math.hypot(x1-x2,y1-y2)}.max'
# max move: 0.345 px
```

The same 30-node chain comes out with **18 of 435 pairs overlapping**.

Raising the temperature does not help. Repulsion is `repulsion / d**2`
with `DEFAULT_REPULSION = 5.0` (`force.rb:21`, applied at
`apply_repulsive_force`, `:123`) and attraction is `d / 10`
(`apply_attractive_force`, `:139`), both measured between node origins
with no size term. The balance point is `d**3 == 10 * repulsion`, about
3.7 px — far inside any real node (force-family-6).

Coincident nodes never separate. `initialize_positions` (`:48-62`) only
randomises a node whose `x` or `y` is nil, and `apply_repulsive_force`
returns early below `distance_sq < 0.01` while attraction is zero at
distance 0. ELK/elkjs JSON almost always carries `x`/`y`, often 0, so
such a graph stays stacked on one point for the whole run
(force-family-5).

The per-iteration endpoint lookup is a linear rescan:
`force.rb:107-108` runs `graph.children.index { |n| n.id == ... }` twice
per edge on every iteration (force-family-15). 11 (S7) replaces it with
the `NodeIndex`. A 100-node chain takes **2.55 s** today.

Corpus reach: only two dump files declare `force` —
`elkjs_layouters_force` (10 nodes, 11 edges) and `java_elk_force`
(20 nodes, 22 edges). Neither carries `x`/`y` on any child. Everything
else in the corpus is layered.

## Do

Rewrite `lib/elkrb/layout/algorithms/force.rb` (~150 lines) to
Fruchterman–Reingold. The model is settled — implement it, do not
re-derive it:

1. Area = `Σ (w + s) * (h + s)` with `s = option("elk.spacing.nodeNode", default: 80.0)`.
   80 is **force's own default**, passed at the call site; the registry
   keeps ELK's core 20 (that split is the D10 rule for per-algorithm
   defaults — do not move 80 into the registry).
2. `k = sqrt(area / N)`.
3. Repulsion `k**2 / d`, attraction `d**2 / k`. `d` is measured between
   node **borders** — subtract half-extents — so node size enters the
   model. This is what kills the 3.7 px equilibrium.
4. Edges are resolved through the `NodeIndex` from 11, built once before
   the iteration loop, never rescanned per iteration.
5. Temperature starts at `side / 10` and cools linearly over
   `option("elk.force.iterations", default: 300)` (alias `iterations`).
   `elk.force.temperature` **scales** the initial temperature; it is not
   a pixel cap. `elk.force.repulsion` scales `k**2`.
6. Coincident nodes get a deterministic jitter drawn from `rng` (added
   by 20) — never `Kernel#rand`, which 20's guard spec forbids.
7. Initial scatter is seeded from `rng`, so `iterations: 0` returns
   exactly that scatter and is reproducible.
8. Keep `collect_all_edges` restricted to `graph.edges` as 14 left it.
   Contained edges belong to the child level.

**Specs first**, new `spec/elkrb/layout/algorithms/force_spec.rb` (no
force spec exists at `v2`), all from JSON through `Elkrb.layout`:

- 30-node chain: **0** overlapping pairs (18 today), adjacent distance
  in `[40, 200]`.
- 5 nodes all given `x: 0, y: 0` spread out — pairwise distance > 10.
- two runs of the same graph are byte-identical (`be_deterministic`).
- `"elk.force.iterations": 0` returns the seeded scatter and nothing
  else moves.
- golden `force_tri` at `tier: :structural`, un-pended in its own `it`
  block in `spec/elkrb/golden_spec.rb`.

## Done when

- `bundle exec rake` green.
- The max-move repro above prints a value far above 0.345 px, and the
  30-chain overlap count is 0/435.
- The all-at-(0,0) repro spreads the five nodes apart.
- Two consecutive `Elkrb.layout(g, algorithm: "force")` calls return
  identical coordinates.
- `spec/elkrb/golden_spec.rb` has `force_tri` passing at the structural
  tier with no `pending`.
- `git grep -n '\brand\b' -- lib/elkrb/layout/algorithms/force.rb` shows
  only `rng.rand`.

Mandatory gates: thermo-nuclear → execution-diff → Codex → copilot-review.
**dependency-contract-check is not required and the plan must say so:**
the rewrite touches no external boundary — `rng` is `::Random` from
stdlib and every other input is our own model.

**execution-diff intended differences** — driver
`bundle exec rake "corpus:dump[<dir>]"` (quoted) on the branch's base ref
— its merge-base with `v2`, or the `int/s15` stack base while 14 and 20
are unmerged — and again on the branch, then `diff -r`. Exactly two dump
files change:
`elkjs_layouters_force` and `java_elk_force`. Every other file is
byte-identical. Check both by hand against the FR formula — a 10-node
and a 20-node graph are small enough to verify `k` and the final
spacing. The rake exit status is informational.

The plan's `## Breaking` carrier list does not name this slice, and 37
(S30) builds `CHANGELOG.md` only from those sections. Every force
coordinate changes here and the algorithm goes from inert to real. Put a
`## Breaking` section in the report so 37 can see it; the maintainer
decides whether it lands in the 2.0.0 block. Do not edit `CHANGELOG.md`.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`lib/elkrb/layout/algorithms/force.rb` (whole file),
`spec/elkrb/layout/algorithms/force_spec.rb` (new),
`spec/elkrb/golden_spec.rb` (one `it` block). Registry rows only if 08
(S4) missed `elk.force.iterations`/`repulsion`/`temperature` — insert in
sorted position, never at the end.
