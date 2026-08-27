# 31 — Layered: barycenter crossing minimisation
Slice S25a · branch `fix/s25a-layered-barycenter`

Can start after 13 (S9 replaces `NodePlacer`'s placement with the (layer axis,
cross axis) frame this item reorders within — sweeping the old
left-aligned-at-zero placer would be work thrown away) and 16 (S11 clips
sections to borders, which is what makes a crossing countable from the
output). The goldens need 03 (S0a); the XD gate needs 02 (S0b's `corpus:dump`
driver). Blocks the START of 32 (S25b), which inserts long-edge dummies into
the layer order this item establishes, and of 35 (S27b), which asserts the two
strategy keys are honoured. Medium (~250 lines). Not BREAKING in the D13 sense
— layered coordinates already moved in 13 — but every multi-layer layered
graph changes again.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree.

There is no crossing minimisation and no parent centring (layered-7).
`NodePlacer#place_layer` (`lib/elkrb/layout/algorithms/layered/node_placer.rb:61-72`)
starts each layer at `x = 0` (`:65`) directly under the comment
`# Center the layer horizontally` (`:64`), and walks the nodes in the
order `LayerAssigner` inserted them. No sweep, no barycenter, no
centroid:

```sh
bundle exec ruby -relkrb -e 'n=->(i){{id:i,width:100,height:60}}; r=Elkrb.layout({id:"r",children:[n["a"],n["b"],n["c"],n["d"]],edges:[{id:"1",sources:["a"],targets:["d"]},{id:"2",sources:["b"],targets:["c"]}]},algorithm:"layered"); puts r.children.map{|x| "#{x.id}(#{x.x},#{x.y})"}.join(" ")'
# a(12.0,12.0) b(132.0,12.0) c(12.0,132.0) d(132.0,132.0)
```

`a → d` runs right-and-down while `b → c` runs left-and-down: they cross.
One swap in layer 1 removes it. The comment at `:64` is false.

`LayeredAlgorithm#layout_flat` (`lib/elkrb/layout/algorithms/layered.rb:26-40`)
runs three phases — cycle breaking (`:29-31`), layer assignment
(`:33-35`), node placement (`:37-39`). There is no fourth phase to hook
into; this item adds one.

The two option keys exist as registry rows and nothing reads them. Item
08 (S4) pre-seeded `elk.layered.crossingMinimization.strategy` and
`elk.layered.considerModelOrder.strategy` as `:accepted` precisely so
this item flips a status on one line instead of appending a row.

Consumer contract: sirena emits
`elk.layered.considerModelOrder.strategy: "NODES_AND_EDGES"` from
`lib/sirena/transform/base.rb:163` (the shared default) and again in
`class_diagram.rb:275`, `er_diagram.rb:198`, `sequence.rb:138` and
`user_journey.rb:201`. It defines
`elk.layered.crossingMinimization.strategy` (`base.rb:75-76`) but does
not emit it yet. Both keys are `:accepted` in 2.0 until this item lands.

Decision 7 (maintainer-ruled): Brandes-Köpf and network simplex are
deferred, so the `fan_out`, `fan_in` and `diamond` goldens stay at
`tier: :structural`. Do not try to match elkjs's exact fan-out y.

## Do

Everything below is settled — do not re-decide.

1. New `lib/elkrb/layout/algorithms/layered/crossing_minimizer.rb`.
   Barycenter sweeps, **four** of them (down, up, down, up), each
   reordering one layer by the mean cross-axis index of its neighbours in
   the adjacent layer. Endpoints resolve through item 11's `NodeIndex`,
   so a port-id endpoint counts for its owning node.
2. Ties break by INPUT order when
   `get("elk.layered.considerModelOrder.strategy", @graph)` is
   `NODES_AND_EDGES`, and by node id otherwise. Read it through the
   resolver — never off the hash directly.
3. `get("elk.layered.crossingMinimization.strategy", @graph)` selects the
   phase: `LAYER_SWEEP` (the default) runs the sweep; `NONE` keeps the
   assigner's order untouched; **any other value falls back to
   LAYER_SWEEP** and that value stays reported as `accepted`. Three
   states, no fourth.
4. Insert the phase in `layered.rb` between layer assignment (`:33-35`)
   and node placement (`:37-39`). Reuse the index item 11 built and item
   12 passed to both phases — do not build a second one.
5. `NodePlacer`: place a fan-out parent over the centroid of its children
   on the cross axis when the layer has room for it. Where it does not,
   keep item 13's centring rule. This is the "parents over children"
   half of layered-7 and it is what makes the `diamond` crossing count
   reach zero.
6. Flip the two registry rows to `:honoured` **on their own lines** in
   `lib/elkrb/options/registry.rb`. Rows are one per line, sorted by id;
   never append, never reflow the table.
7. Write the failing specs first:
   - the layered-7 repro above: after this item, `b` and `a` (or `c` and
     `d`) have swapped so the two edges no longer cross — assert the
     crossing count is 0, not a coordinate;
   - the same graph with
     `"elk.layered.crossingMinimization.strategy":"NONE"` keeps the
     crossing;
   - a tie broken by input order under `NODES_AND_EDGES` and by id
     without it;
   - golden `diamond` at `tier: :structural` plus an explicit
     crossing count of 0;
   - goldens `fan_out` and `fan_in` stay `structural` — un-pend them only
     if they pass.

Write the crossing counter as a spec helper: for every pair of edges
between two adjacent layers, count an inversion in the cross-axis order
of their endpoints. Counting crossings is the assertion; coordinates are
not.

Do not touch: layer assignment itself (item 12 owns cycle breaking and
longest-path layering), long-edge dummies (item 32), direction and
spacing (item 13), `CHANGELOG.md` (item 37 assembles it from the merged
PR bodies' `## Breaking` sections).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- The layered-7 repro produces a crossing-free layout, and the same graph
  with `"elk.layered.crossingMinimization.strategy":"NONE"` reproduces
  the crossing.
- `Elkrb::Options::Registry.status("elk.layered.crossingMinimization.strategy")`
  and `…("elk.layered.considerModelOrder.strategy")` both return
  `:honoured`, and item 09's once-per-layout warning stops firing for
  them.
- `bundle exec rspec spec/elkrb/golden_spec.rb -e diamond -e fan_out -e fan_in`
  passes at `tier: :structural` with the diamond crossing count at 0.
- `git diff lib/elkrb/options/registry.rb` shows two changed lines and no
  reordering.

Mandatory gates, in order: `thermo-nuclear-review` → `execution-diff` →
Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. No dependency-contract-check: nothing here crosses
a boundary we do not own — say so in the report rather than skipping
silently.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s25a` stack base — and again on the branch, then `diff -r` the two
dump dirs. `corpus:dump`'s exit status is informational; never chain on
it.

INTENDED execution-diff differences, and nothing else:

- Every layered corpus case with more than one node in any layer changes
  its within-layer order, and therefore its cross-axis coordinates and
  its sections.
- Single-chain layered cases are byte-identical: one node per layer means
  nothing to sweep. `spec/fixtures/simple_graph.json` is one — use it as
  the control.
- Non-layered cases are byte-identical.

Verify two changed cases by hand against the sweep, and record the
crossing count before and after for each.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit):
layered node order within a layer now follows a barycenter sweep, so
cross-axis coordinates move for any layer holding more than one node;
`elk.layered.crossingMinimization.strategy` and
`elk.layered.considerModelOrder.strategy` move from accepted to
honoured. Migration line: `"elk.layered.crossingMinimization.strategy":"NONE"`
restores the old insertion order.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
