# 15 — Cross-level edge routing (bounded INCLUDE_CHILDREN)
Slice S10b · branch `fix/s10b-cross-level-edges`

Can start after 14 (S10 — this item needs per-level layout and children
sitting at padded local coordinates; the offset arithmetic below is only
correct because S10 put them there) and 16 (S11 — it reuses S11's
`clip_to_border` and S11's section shape). 16 carries a higher number and this
item still waits on it. The XD gate needs 02 (S0b). Blocks the START of 30
(S24, which documents the coordinates this item settles) and of 35 (S27b — the
C4 fixture asserts that every root relationship has a section). Small (~150
lines). Not BREAKING: `INCLUDE_CHILDREN` gains sections, nothing moves.

## Facts

Measured on 11's head (3d91c5e) in
`~/.claude/pipeline/worktrees/elkrb/s7-node-index`.

`elk.hierarchyHandling` is not read anywhere. `grep -rn hierarchyHandling lib/ spec/`
exits 1 on both `v2` and 3d91c5e — no matches in either tree.

A C4-shaped graph — two boundary compounds, one relationship between a member of
each — loses the relationship entirely:

```sh
bundle exec ruby -relkrb -rjson -e 'g=JSON.parse(%q({"id":"r","layoutOptions":{"elk.hierarchyHandling":"INCLUDE_CHILDREN"},"children":[{"id":"b1","children":[{"id":"m1","width":30,"height":30}]},{"id":"b2","children":[{"id":"m2","width":30,"height":30}]}],"edges":[{"id":"rel","sources":["m1"],"targets":["m2"]}]})); r=Elkrb.layout(g); puts "rel sections: #{r.edges[0].sections.inspect}"'
# rel sections: nil
```

That shape is the first consumer's, not a hypothetical. In claricle/sirena (a
separate repo, checked 2026-08-21) four transforms send
`elk.hierarchyHandling: INCLUDE_CHILDREN` on the root —
`lib/sirena/transform/c4.rb:271`, `class_diagram.rb:276`, `er_diagram.rb:199`,
`user_journey.rb:202`. C4 is the one that also nests: it builds boundary
compounds from their contents (`c4.rb:93-105`), puts per-node `layoutOptions` on
each boundary (`c4.rb:276-285`: `elk.algorithm: box`,
`elk.box.packingMode: GROUP_MIXED`, `elk.padding`,
`elk.spacing.nodeNode: "60"` as a String), and keeps every relationship at the
root while its endpoints live inside boundaries. So today sirena's C4 diagrams
come back with no relationship geometry at all.

08's registry already carries the row in `lib/elkrb/options/registry.rb`: type
`:enum`, values `INHERIT INCLUDE_CHILDREN SEPARATE_CHILDREN`, default
`INHERIT`, `status: :partial`, note "cross-level edges are routed; no
cross-level layering". 09 (S5) fires the once-per-layout warning for `:partial`
rows. Neither changes here.

`EdgeSection` already models the two keys this item writes:
`incoming_shape` / `outgoing_shape` at `lib/elkrb/graph/edge.rb:14-15`, mapped
to `incomingShape` / `outgoingShape` at `:22-23`. Nothing sets them today
(gap4-12); 16 starts doing so for same-level edges.

`spec/fixtures/` holds three files today — `elkjs_basic.json`,
`elkjs_bug7_complex.json`, `simple_graph.json`. There is no
`c4_include_children.json`; this item commits it.

02's `corpus_runner` enumerates every `spec/fixtures/*.json` as a bare graph on
the default algorithm (`corpus_runner.rb`, `top_level_fixture_cases`), so the
new fixture appears in the corpus automatically and its dump file is new on the
branch.

`NodeIndex` (`lib/elkrb/layout/node_index.rb`, from 11) indexes one level only
and has `build`, `node`, `endpoint_nodes`. There is no `build_deep`.

## Do

1. **Bounded form only** (D14 and decision 14, ruled). Full `INCLUDE_CHILDREN`
   means cross-level co-layering in one layered run; that is explicitly
   deferred. This item routes cross-level edges after the separate-children
   layout, so sirena's C4 relationships are visible. Nothing is co-layered and
   no node moves.

2. `BaseAlgorithm#layout` gains one call, after `apply_edge_routing(graph)`:
   `route_cross_level_edges(graph)`, guarded on
   `@resolver.get("elk.hierarchyHandling", graph)` being `INCLUDE_CHILDREN` on
   the root. `SEPARATE_CHILDREN` and the `INHERIT` default are unchanged —
   cross-level edges get no sections, which is what elkjs does.

3. `NodeIndex.build_deep(graph)` → `{ id => [[node, absolute_offset], …] }`.
   Every match per id, across every level, because 11 lets distinct levels reuse
   an id. Build it by reusing `NodeIndex.build` per level, so a duplicate id
   *within* one level still raises the same `ValidationError`. An endpoint id
   with more than one match raises
   `Elkrb::ValidationError, "ambiguous id across levels: #{id}"`. There is no
   qualified-path syntax — that was considered and is not in scope.

4. Compute absolute endpoint rectangles by summing ancestor `x`/`y` **only**.
   14 already places children at padded local coordinates, so padding must never
   be added again: with `p` at (12,12) and `c1` at local (12,12), `c1` is
   absolute (24,24), not (36,36). Adding padding pushes every endpoint off the
   border the spec below asserts.

5. Clip to the two borders with 16's `clip_to_border` and write **one** section
   in this level's frame: id `"#{edge.id}_s0"`, `incomingShape` / `outgoingShape`
   set to the endpoint ids as the user gave them. ORTHOGONAL / POLYLINE /
   SPLINES bends follow 16's definitions — do not invent a second bend rule
   here.

6. Files: `lib/elkrb/layout/algorithms/base_algorithm.rb` (one added call in
   `layout`), `lib/elkrb/layout/node_index.rb` (`build_deep`),
   `lib/elkrb/layout/edge_router.rb` (`route_cross_level_edges`, using the
   existing clip and bend helpers). No new shared ivars in the mixin — the
   method takes `graph` and reads `@resolver`.

7. Specs first:
   - `spec/elkrb/layout/node_index_spec.rb`: `build_deep` maps a nested leaf to
     `[[node, offset]]` with the summed ancestor offset and no padding term —
     with `p` at (12,12) and `c1` at local (12,12), `c1`'s offset is (12,12) and
     its absolute origin (24,24). The same id at two levels yields two entries
     under that id.
   - `spec/elkrb/layout/cross_level_edges_spec.rb` (new), reading
     `spec/fixtures/c4_include_children.json` (a plain ELK graph this item
     commits): root with two boundaries laid out by box via nested
     `"elk.algorithm":"box"`, and a root edge between one member of each. With
     `"elk.hierarchyHandling":"INCLUDE_CHILDREN"` on the root, that edge has
     exactly one section whose start and end lie within 1e-6 of the two members'
     absolute borders, expressed in the root frame. Node coordinates are
     identical to the run without the key. With the key absent or
     `SEPARATE_CHILDREN`, the edge has no sections. 09's warning for
     `elk.hierarchyHandling` fires exactly once. A root edge naming an id that
     exists in **both** boundaries (inline JSON, not the fixture) raises
     `Elkrb::ValidationError, /ambiguous id across levels: /`.

Do not touch: 20's `rng`, directly below `option` in `base_algorithm.rb`;
layering or node placement at any level; `INCLUDE_CHILDREN` semantics beyond the
section (no co-layering — deferred); the registry status and note (08) and the
warning (09).

## Done when

`bundle exec rake` green.

```sh
bundle exec exe/elkrb layout spec/fixtures/c4_include_children.json
```

prints the root edge with a single section whose endpoints sit inside the two
boundaries' absolute rectangles — the same fixture the spec reads. Put the two
endpoint coordinates in the report.

Report also confirms, by diffing the two runs, that node coordinates are
identical with and without `elk.hierarchyHandling`.

Mandatory gates: thermo-nuclear, execution-diff, Codex, copilot-review. No
dependency-contract-check — everything here is internal.

The execution-diff's intended differences: only corpus cases carrying
`elk.hierarchyHandling: INCLUDE_CHILDREN` with nested endpoints change. Expected
list is `spec/fixtures/c4_include_children.json` — new on the branch, so its
dump file is an addition, not a change — plus 34's (S27a) C4 capture if it is in
the corpus by then. List them in the report. Everything else byte-identical.
A diff on a `SEPARATE_CHILDREN` or flat case means the guard in step 2 leaks.

`## Breaking`: none expected. `INCLUDE_CHILDREN` gains sections on cross-level
edges; no node moves and no existing section changes.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
