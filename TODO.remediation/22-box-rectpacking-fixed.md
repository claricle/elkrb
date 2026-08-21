# 22 — Box, rectpacking, fixed
Slice S16 · branch `fix/s16-box-rect-fixed`

Can start after 10 (S6 puts `box.rb`'s and `rectpacking.rb`'s option reads on
the resolver, which is where `elk.aspectRatio` and `elk.spacing.nodeNode` have
to arrive from before either can honour them). The goldens `box3`,
`box_mixed`, `box_aspect`, `fixed2`, `rect6` come from 03 (S0a); the XD gate
needs 02 (S0b). Runs in parallel with 13–21. Blocks the START of 30 (S24,
which documents these three algorithms) and of 35 (S27b), which asserts the
`elk.box.packingMode` contract row. Medium–large (~300 lines). **BREAKING** —
`fixed` stops translating.

## Facts

Measured 2026-08-21 against `v2` (a008889).

Box is a uniform grid, not ELK's packer (force-family-11).
`box.rb:18` reads `option("aspect_ratio", 1.6)`, `:23` computes
`cols = Math.sqrt(num_nodes * aspect_ratio).ceil`, and `:35-36` place
every node in a `max_width × max_height` cell. There is no sorting and
no per-row fill:

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({id:"r",children:[{id:"big",width:200,height:200}]+(0...9).map{|i|{id:"s#{i}",width:10,height:10}}},algorithm:"box"); puts "#{r.width}x#{r.height}"'
# 694.0x474.0    (ten small boxes 220 px apart)
```

RectPacking never opens a second shelf (tree-family-4). `rectpacking.rb:39`
sorts by `-n.height`, so the shelf height is always the max seen so far
and `can_fit_on_shelf?` (`:71-78`, `shelf[:height] >= node.height * 0.8`)
is always true. `rectpacking.rb` contains no `option(` call at all, so
`elk.aspectRatio` is never read, and `_spacing` at `:71` is unused:

```sh
bundle exec ruby -relkrb -e 'srand 1; g=Elkrb.layout({id:"r",children:(1..30).map{|i|{id:"n#{i}",width:rand(30..150),height:rand(20..120)}},edges:[]},algorithm:"rectpacking"); puts "#{g.width.round}x#{g.height.round} rows=#{g.children.map(&:y).uniq.size}"'
# 3277x138 rows=1
```

Fixed moves everything (force-family-4). `fixed.rb:14-25` does nothing
but call `apply_padding`, which rebases the bounding box on the padding
origin, contradicting the class doc at `fixed.rb:10` ("Keeps nodes at
their current positions"):

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({id:"r",children:[{id:"a",x:100,y:100,width:30,height:30}]},algorithm:"fixed"); p r.children.map{|c|[c.x,c.y]}'
# [[12.0, 12.0]]
```

`Elkrb.known_layout_options` advertises `position` (KVector) and
`bendPoints` (KVectorChain) "for the fixed algorithm", and neither
`Options::KVector` nor `Options::KVectorChain` has a caller anywhere in
`lib/`.

The translation is spec-encoded. `spec/elkrb/layout_engine_spec.rb:53-79`
is `context "with fixed algorithm" / it "keeps nodes at their current
positions"`; it asserts only the relative offsets at `:76-77`
(`n2.x - n1.x == 40`) and carries the comment "Nodes should be shifted
by padding but relative positions maintained" at `:70`. The example
passes today precisely because it never checks an absolute coordinate.

Corpus reach: five dump files declare these algorithms —
`elkjs_layouters_box`, `elkjs_layouters_fixed`, `java_elk_box`,
`java_elk_fixed`, `java_elk_rectpacking` (elkjs has no rectpacking
case). **No child in any of those fixtures carries `x`/`y`**, so today
`elkjs_layouters_fixed` and `java_elk_fixed` both come out `124x84` with
every node stacked at the padding origin, and `java_elk_rectpacking`
comes out `2404x84` in a single row. Every other corpus case is layered.

## Do

**`box.rb` — port ELK's `BoxLayoutProvider`, SIMPLE packing only.**

1. Sort nodes **ascending by area** — the `box_mixed` golden pins the
   order (20×20, then 30×30, then 60×30).
2. Fill rows left to right using each box's real width, wrapping at a
   row-width budget derived from `elk.aspectRatio`; row height is the
   tallest box in the row.
3. Box passes **15.0** as its own default for both
   `elk.spacing.nodeNode` and `elk.padding` — at the call site as
   `option(key, default: 15.0)`, never in the registry (the registry
   keeps ELK's core 20 and 12; that split is the settled D10 rule).
4. Only SIMPLE is implemented. `GROUP_*` values of
   `elk.box.packingMode` fall back to SIMPLE.

   Arithmetic check before you write the loop: sorting ascending by area
   and wrapping at `sqrt(Σ (w+s)(h+s) * elk.aspectRatio)` with `s = 15`
   and `aspectRatio = 1.6` reproduces both committed goldens — `box3`
   (a(15,15) b(60,15) c(15,60), 105×105) and `box_mixed` (c(15,15)
   b(50,15) a(15,60), 95×105). The committed goldens are the authority;
   confirm against them, do not trust this line alone.

**`rectpacking.rb`** — open a new row when the row width would exceed
`sqrt(total_area * elk.aspectRatio)`. Delete the dead `_spacing`
parameter at `:71` and the never-false `can_fit_on_shelf?` height test.

**`fixed.rb`** — do not translate. Keep every declared `x`/`y` exactly
as given; apply `elk.position` (KVector) per node and `elk.bendPoints`
(KVectorChain) per edge where present; set `graph.width` /
`graph.height` to max extent + padding. Nodes with no `x`/`y` are the
common case in the corpus — treat them as 0, do not re-grid the graph.

**Registry** — `elk.box.packingMode` was pre-seeded by 08 (S4) as
`:accepted`. Edit **that row only, in place, in sorted position**, so it
records that box implements SIMPLE and `GROUP_*` fall back. Keep the
status `:accepted`: 35 (S27b) copies the consumer-contract table as
data and asserts `Registry.status("elk.box.packingMode") == :accepted`,
and sirena emits `GROUP_MIXED`, whose value genuinely has no effect. If
the maintainer prefers `:partial` with a note, the contract table row has
to change in the same breath — flag it, do not change one side alone.

**Specs first.**

- Goldens exact, each in its own `it` block in
  `spec/elkrb/golden_spec.rb`: `box3`, `box_mixed`, `box_aspect`,
  `fixed2` (positions unchanged). `rect6` at `tier: :structural`.
- `rectpacking` on 20 equal nodes produces more than one row.
- `fixed` on a node at (100,100) leaves it at (100,100).
- `fixed` with `"elk.position": "(40,50)"` on a node places it there.
- `fixed` with `elk.bendPoints` on an edge keeps those bends.
- Rewrite `spec/elkrb/layout_engine_spec.rb:53-79` to assert **absolute**
  coordinates — (10,20), (50,60), (90,100) unchanged — and delete the
  "shifted by padding" comment at `:70`. This is the force-family-4 fix
  and the example must state it, not imply it.

## Done when

- `bundle exec rake` green.
- The fixed repro above prints `[[100.0, 100.0]]`.
- The rectpacking repro above prints `rows=` a number greater than 1.
- The box repro above prints a graph materially smaller than
  `694.0x474.0`, with the nine 10×10 boxes packed rather than spread on
  a 220 px pitch.
- `bundle exec rspec spec/elkrb/golden_spec.rb` green with `box3`,
  `box_mixed`, `box_aspect`, `fixed2` at the exact tier and `rect6`
  structural — none of them `pending`.
- `Registry.status("elk.box.packingMode") == :accepted` still holds, and
  the row's own line records the SIMPLE/`GROUP_*` behaviour.

Mandatory gates: thermo-nuclear → execution-diff → Codex → copilot-review.
**dependency-contract-check is not required and the plan must say so:**
no external boundary is crossed. `Options::KVector` and
`Options::KVectorChain` are ours and get their first callers here — pin
their parse results with specs rather than a DCC pass.

**execution-diff intended differences** — driver
`bundle exec rake "corpus:dump[<dir>]"` (quoted) on the branch's base ref
— its merge-base with `v2`, or the `int/s16` stack base while 10 is
unmerged — and again on the branch, then `diff -r`. Exactly five dump
files change:
`elkjs_layouters_box`, `elkjs_layouters_fixed`, `java_elk_box`,
`java_elk_fixed`, `java_elk_rectpacking`. Everything else is
byte-identical. Verify `java_elk_rectpacking` by hand — 20 nodes of
100×60 must no longer land in one 2404 px row.

`## Breaking` section in the report (this slice is on the plan's carrier
list): `fixed` no longer translates nodes to the padding origin and now
honours `elk.position`/`elk.bendPoints`; box coordinates move to ELK's
packing. Do not edit `CHANGELOG.md` — 37 (S30) assembles it from the
merged PR bodies.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`lib/elkrb/layout/algorithms/box.rb`,
`lib/elkrb/layout/algorithms/rectpacking.rb`,
`lib/elkrb/layout/algorithms/fixed.rb`,
`lib/elkrb/options/registry.rb` (one row, in place),
`spec/elkrb/layout_engine_spec.rb:53-79`,
`spec/elkrb/layout/algorithms/rectpacking_spec.rb`,
`spec/elkrb/golden_spec.rb` (five `it` blocks).
