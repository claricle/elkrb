# 32 — Layered: long-edge dummies
Slice S25b · branch `fix/s25b-long-edge-dummies`

Can start after 31 (S25a) — a dummy slot is a position in a layer's cross-axis
order, and 31 is what establishes that order through the barycenter sweep;
inserting dummies into the assigner's raw insertion order would be reordered
away the moment 31 lands. The XD gate needs 02 (S0b's `corpus:dump` driver).
Blocks the START of 35 (S27b), which asserts the layered contract is complete,
and of 37 (S30), which is the final slice. Medium (~250 lines). Not BREAKING
in the D13 sense — this adds bend points to long edges; no node moves that 31
did not already move.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree.

Edges spanning more than one layer are drawn straight through the nodes
in between (layered-8). Layer assignment is longest-path
(`lib/elkrb/layout/algorithms/layered/layer_assigner.rb`, 109 lines), so
`a → c` next to `a → b → c` spans two layers, and nothing anywhere
handles it:

```sh
grep -rn 'dummy\|Dummy' lib/elkrb/
# (no matches)
```

The router then connects the two endpoints directly:

```sh
bundle exec ruby -relkrb -e 'n=->(i){{id:i,width:100,height:60}}; r=Elkrb.layout({id:"r",children:[n["a"],n["b"],n["c"]],edges:[{id:"1",sources:["a"],targets:["b"]},{id:"2",sources:["b"],targets:["c"]},{id:"3",sources:["a"],targets:["c"]}]},algorithm:"layered"); puts r.children.map{|x| "#{x.id}(#{x.x},#{x.y})"}.join(" "); s=r.edges[2].sections[0]; puts "e3: #{s.start_point.x},#{s.start_point.y} -> #{s.end_point.x},#{s.end_point.y} bends=#{(s.bend_points||[]).size}"'
# a(12.0,12.0) b(12.0,132.0) c(12.0,252.0)
# e3: 62.0,42.0 -> 62.0,282.0 bends=0
```

`b` occupies x 12…112, y 132…192. The `a → c` segment sits at x = 62 for
its whole length, so it runs straight through `b`'s rectangle. Zero bend
points.

Item 13 (S9) makes layered default to RIGHT with 20/20 spacing and item
31 sweeps the layer order, so both the coordinates and the layer contents
above will have moved by the time this item runs. The defect does not:
re-run the repro on the branch base and record the new numbers before
writing the spec.

`LayeredAlgorithm#layout_flat` (`lib/elkrb/layout/algorithms/layered.rb`,
49 lines) is cycle breaking → layer assignment → (item 31's crossing
minimisation) → node placement. `NodePlacer` is 77 lines and walks a
layer's nodes in order; it has no concept of an occupied slot that is
not a real node.

Golden `long_edge` (`a → b → c` plus `a → c`) was authored by item 03
(S0a) for exactly this case.

## Do

Everything below is settled — do not re-decide.

1. In `layer_assigner.rb`, after the layers are assigned, insert a **dummy
   slot** into every intermediate layer that a spanning edge crosses. A
   slot carries the edge id and its layer index; it is not a `Node` and
   it never appears in `graph.children` or in the output.
2. The slots take part in item 31's barycenter sweep and in
   `NodePlacer`'s cross-axis stacking exactly like real nodes, so a long
   edge gets its own lane instead of overlapping one.
3. Before routing, write a bend point at each dummy's position onto the
   spanning edge's section. Item 16 (S11) owns the section shape — reset
   to one `<edge>_s0`, endpoints clipped to borders — so these bends go
   into that section's `bend_points`, in layer order, and nothing else
   about the section changes.
4. Dummies never leak. After `layout_flat` returns, `graph.children` holds
   exactly the input nodes and `to_json` shows no synthetic id. Spec that
   directly.
5. Add the invariant **"no section passes through a non-endpoint node
   rectangle"** as its own file under `spec/support/invariants/`, ending
   with `INVARIANTS << :<name>`. Never edit `corpus_spec`'s matcher list
   — items 03, 16 and 17 all add files the same way. Segment-versus-
   axis-aligned-rectangle intersection over every consecutive point pair
   of every section, skipping the edge's own source and target.
6. Write the failing specs first:
   - the layered-8 repro: `e3` comes back with at least one bend point and
     its polyline misses `b`'s rectangle;
   - golden `long_edge` at `tier: :structural`;
   - a graph where a long edge spans three layers gets two bends;
   - `graph.children.map(&:id)` after layout equals the input ids.

Do not touch: layer assignment's longest-path rule and cycle breaking
(item 12), the sweep itself (item 31), section ids and endpoint clipping
(item 16), `CHANGELOG.md` (item 37 assembles it from the merged PR
bodies' `## Breaking` sections).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- The layered-8 repro prints a non-zero bend count and a polyline that
  clears `b`.
- `bundle exec rspec spec/elkrb/golden_spec.rb -e long_edge` passes at
  `tier: :structural`.
- The new invariant file self-registers, `corpus_spec`'s list was not
  edited by hand, and the invariant passes over the whole corpus.
- No output anywhere carries a synthetic node id.

Mandatory gates, in order: `thermo-nuclear-review` → `execution-diff` →
Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. No dependency-contract-check: nothing here crosses
a boundary we do not own — say so in the report rather than skipping
silently.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s25b` stack base — and again on the branch, then `diff -r` the two
dump dirs. `corpus:dump`'s exit status is informational; never chain on
it.

INTENDED execution-diff differences, and nothing else:

- Layered cases holding an edge that spans more than one layer gain bend
  points on that edge's section.
- Those same cases may move nodes on the cross axis, because a dummy slot
  occupies room in the intermediate layers. List every case that moves
  and say which spanning edge caused it.
- Layered cases with no spanning edge are byte-identical.
- Non-layered cases are byte-identical.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit):
edges spanning more than one layer now carry bend points and are routed
around the intervening nodes; graphs holding such edges may shift on the
cross axis to make room. Migration line: none — the old output drew lines
through node boxes.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
