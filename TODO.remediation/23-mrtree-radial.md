# 23 — mrtree and radial
Slice S17 · branch `fix/s17-mrtree-radial`

Can start after 10 (S6 routes `node_spacing` and the padding read through the
resolver, which is how `elk.spacing.nodeNode` reaches these two algorithms at
all), 11 (S7's `NodeIndex` — radial builds its tree from edges and mrtree
resolves port-id endpoints through it) and 07 (S3b rewrites the 5
`LayoutOptions.new` sites in `mrtree_spec.rb` and the 4 in `radial_spec.rb`
that this item edits). Goldens `mrtree3`, `mrtree7`, `radial_star5` come from
03 (S0a); the XD gate needs 02 (S0b). Blocks the START of 30 (S24, docs cover
S3–S17) and of 35 (S27b), which asserts the `elk.direction` contract row for
mrtree. Medium (~250 lines). **BREAKING if output changes** — it does;
see `## Done when`.

## Facts

Measured 2026-08-21 against `v2` (a008889).

mrtree uses a hard-coded 80 px level pitch. `mrtree.rb:110` sets
`level_height = 80.0` and `:115`/`:132` place `node.y = y_offset +
(tree[:level] * level_height)`, so anything taller than 80 overlaps the
next level (tree-family-7):

```sh
bundle exec ruby -relkrb -e 'g=Elkrb.layout({id:"r",children:[{id:"r1",width:100,height:100},{id:"c",width:100,height:100}],edges:[{id:"e",sources:["r1"],targets:["c"]}]},algorithm:"mrtree"); a,b=g.children; p [a.y+a.height, b.y]'
# [112.0, 92.0]   root bottom below child top — 20 px overlap
```

Neighbouring trees overlap too (tree-family-6). `mrtree.rb:29` throws
away `layout_tree`'s return value and advances `x_offset` by
`calculate_tree_width` (`:138-142`) instead, which sums leaf widths only
and ignores the spacing `layout_tree` inserted between siblings:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb.layout({id:"r",children:%w[r1 c1 c2 c3 r2 d1].map{|i|{id:i,width:100,height:50}},edges:[["r1","c1"],["r1","c2"],["r1","c3"],["r2","d1"]].each_with_index.map{|(s,t),i|{id:"e#{i}",sources:[s],targets:[t]}}},algorithm:"mrtree"); c3=g.children.find{|n|n.id=="c3"}; d1=g.children.find{|n|n.id=="d1"}; p [c3.x+c3.width, d1.x]'
# [352.0, 332.0]   the next tree starts 20 px inside this one
```

`mrtree.rb` contains no `option(` call and no occurrence of the string
`direction` (`git grep -n 'direction\|option(' a008889 --
lib/elkrb/layout/algorithms/mrtree.rb` returns nothing). The
`"elk.direction" => "DOWN"` that README.adoc tells mrtree users to set
is read nowhere (tree-family-12).

radial ignores edges entirely. `git grep -n edges a008889 --
lib/elkrb/layout/algorithms/radial.rb` returns nothing: `layout_flat`
(`:12-46`) puts every node, root included, on one circle in `children`
order, and `calculate_radius` (`:49-60`) is
`max(nodes.size * avg_size / (2π) * 1.2, 100.0)` — which does not
guarantee separation (tree-family-5):

```sh
bundle exec ruby -relkrb -e 'g=Elkrb.layout({id:"r",children:(1..8).map{|i|{id:"n#{i}",width:100,height:50}},edges:[]},algorithm:"radial"); puts g.children.combination(2).count{|a,b| a.x<b.x+b.width && b.x<a.x+a.width && a.y<b.y+b.height && b.y<a.y+a.height}'
# 4
bundle exec ruby -relkrb -e 'g=Elkrb.layout({id:"r",children:%w[a b c].map{|i|{id:i,width:60,height:40}},edges:[{id:"e1",sources:["a"],targets:["b"]},{id:"e2",sources:["a"],targets:["c"]}]},algorithm:"radial"); p g.children.map{|n|[n.id,n.x.round,n.y.round]}'
# [["a", 162, 99], ["b", 12, 185], ["c", 12, 12]]   root a is not centred
```

`radial.rb` reads no option at all — `elk.radial.radius` and
`elk.radial.centerOnRoot` are registered by 08 (S4) with no consumer.

Corpus reach: four dump files declare these algorithms.
`elkjs_layouters_mrtree` is 304×564 today, `java_elk_mrtree` 424×964,
`elkjs_layouters_radial` 430×375, `java_elk_radial` 735×695. Everything
else in the corpus is layered.

## Do

**`mrtree.rb:107-142`** — the geometry is settled:

1. Level pitch = max node height **in that level** + `elk.spacing.nodeNode`
   (20). No constant.
2. Subtree width = Σ child subtree widths + `(n - 1) * spacing`, floored
   at the node's own width. Advance `x_offset` by the real extent, not
   `calculate_tree_width`'s leaf sum.
3. Parent centred over its children's span.
4. mrtree passes **20** as its own `elk.padding` default at the call
   site — `option("elk.padding", default: 20)` — never in the registry
   (the registry keeps ELK's core 12; that split is the settled D10
   rule).
5. `elk.direction` is honoured. Compute every node in a `(level, breadth)`
   frame, then map the whole graph to x/y once, at the end. 13 (S9) settles
   the same shape for layered; the contract is restated here in full so this
   item needs nothing from that file:
   - **DOWN** (mrtree's default, as ELK) → level→y, breadth→x.
   - **RIGHT** → level→x, breadth→y.
   - **UP** → map as DOWN, then mirror y in the graph bbox:
     `y' = graph.height - y - node.height`.
   - **LEFT** → map as RIGHT, then mirror x in the graph bbox:
     `x' = graph.width - x - node.width`.
   Mirror after the bbox is known, so padding lands once and the graph size
   is the same in all four directions.

   Arithmetic check: with padding 20, spacing 20 and 30×30 nodes, the
   rules above give the committed `mrtree3` golden exactly — b(20,70),
   c(70,70), a centred over the 20..100 span at (45,20), graph 120×120.
   The golden is the authority; confirm against it.

**`radial.rb`** — build the tree from `graph.edges` through the
`NodeIndex` from 11. Root is the node with in-degree 0, or the node
named by `elk.radial.centerOnRoot`. Rings by BFS depth. Ring radius from
`elk.radial.radius`, defaulting to max node extent + spacing, grown
until adjacent nodes on a ring do not overlap. Root at the centre.
Flip 08's pre-seeded `elk.radial.centerOnRoot` row to `:honoured` — on
its own line, in sorted position, never appended.

**Specs first.**

- Golden `mrtree3` **exact** — a(45,20) b(20,70) c(70,70), 120×120 —
  in its own `it` block in `spec/elkrb/golden_spec.rb`.
- Goldens `mrtree7` and `radial_star5` at `tier: :structural`, each in
  its own `it` block.
- One spec per direction: DOWN, UP, LEFT, RIGHT — every node inside the
  graph bounds with the root on the expected side.
- One spec using the bare `direction` alias (registered by 08, ruled
  first-class in decision 9) — same result as `elk.direction`.
- tree-family-6 repro as a spec: two 3-child subtrees do not overlap
  (352.0 vs 332.0 today).
- tree-family-7 repro as a spec: a 100-high root and a 100-high child do
  not overlap.
- radial: the 3-node star above puts the root at the centre; the 8-node
  100×50 case has 0 overlapping pairs.

## Done when

- `bundle exec rake` green.
- Both mrtree repros above print non-overlapping values.
- Both radial repros print 0 overlaps and a centred root.
- `bundle exec rspec spec/elkrb/golden_spec.rb` green with `mrtree3`
  passing at the exact tier and `mrtree7`/`radial_star5` at structural —
  none of them `pending`.
- `Registry.status("elk.radial.centerOnRoot") == :honoured`.
- A graph carrying `"elk.direction":"RIGHT"` and the same graph carrying
  bare `"direction":"RIGHT"` produce identical mrtree output.

Mandatory gates: thermo-nuclear → execution-diff → Codex → copilot-review.
**dependency-contract-check is not required and the plan must say so:**
no external boundary — both algorithms read only our model and the
resolver.

**execution-diff intended differences** — driver
`bundle exec rake "corpus:dump[<dir>]"` (quoted) on the branch's base ref
— its merge-base with `v2`, or the `int/s17` stack base while 07, 10 and
11 are unmerged — and again on the branch, then `diff -r`. Exactly four
dump files change:
`elkjs_layouters_mrtree`, `elkjs_layouters_radial`, `java_elk_mrtree`,
`java_elk_radial`. Everything else byte-identical. Check one mrtree case
by hand against the pitch rule — the 20-node `java_elk_mrtree` graph is
all 100×60 nodes, so every level pitch must be 80 exactly (60 + 20) and
the old 964 height must move.

`## Breaking` section in the report (this slice is on the plan's carrier
list, conditioned on output changing — it does): mrtree and radial
coordinates move to the ELK shape; mrtree now honours `elk.direction`;
radial now reads edges and centres the root. Do not edit
`CHANGELOG.md` — 37 (S30) assembles it from the merged PR bodies.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`lib/elkrb/layout/algorithms/mrtree.rb`,
`lib/elkrb/layout/algorithms/radial.rb`,
`lib/elkrb/options/registry.rb` (one row, in place),
`spec/elkrb/layout/algorithms/mrtree_spec.rb`,
`spec/elkrb/layout/algorithms/radial_spec.rb`,
`spec/elkrb/golden_spec.rb` (three `it` blocks).
