# 16 — Edge sections: borders, ids, shapes, ORTHOGONAL
Slice S11 · branch `fix/s11-edge-sections`

Can start after 10 (S6 moves the `EdgeRouter` option reads onto the resolver
and gives the router spec a `@resolver` — this item extends those reads to the
graph), 11 (S7's `NodeIndex` resolves port-id endpoints, so the router knows
which node an endpoint belongs to), 13 (S9 fixes layered coordinates —
clipping to a border is only checkable once the borders sit where ELK puts
them), 14 (S10 lays out each compound in its own frame; the `compound_chain`
golden and the "node coordinates identical to S10" rule both need it) and 07
(S3b rewrites `edge_router_spec.rb:612` next to a hunk this item edits). The
XD gate needs 02 (S0b's `corpus:dump` driver and the `stale_sections`
fixture); the golden assertions need 03 (S0a). Blocks the START of 18 (S13
ports), 19 (S13b self-loops), 31 (S25a — a crossing is only countable once
sections are clipped to borders), and of 15 (S10b) which reuses this item's
`clip_to_border` — 15 carries a lower number but cannot start until this
lands. Medium (~300 lines). **BREAKING.**

## Facts

Verified against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`.

Sections start and end at node centres, not borders (pipeline-6;
elk-compat-16). Two 100×60 nodes through `box`:

```sh
bundle exec ruby -relkrb -e 'g={id:"r",children:[{id:"a",width:100,height:60},{id:"b",width:100,height:60}],edges:[{id:"e",sources:["a"],targets:["b"]}]}; r=Elkrb.layout(g,algorithm:"box"); s=r.edges[0].sections[0]; p [s.id,s.start_point.x,s.start_point.y,s.end_point.x,s.end_point.y,s.incoming_shape,s.outgoing_shape]'
# ["e_section_0", 62.0, 42.0, 182.0, 42.0, nil, nil]
```

Node `a` is at (12,12) 100×60, so (62,42) is its centre — the segment
starts inside the box. `route_node_to_node` (`edge_router.rb:131-141`)
takes both endpoints from `get_node_center` (`:168-172`).

Section ids are `<edge>_section_0`, not elkjs's `<edge>_s0`
(elk-compat-28). Written at `edge_router.rb:54` (`route_edge`), `:289`
(`route_spline_edge`) and `:427` (`route_self_loop`).

`incomingShape`/`outgoingShape` are never set (gap4-12; elk-compat-28).
`EdgeSection` declares both (`lib/elkrb/graph/edge.rb:14-15`, mapped at
`:22-23`) and `grep -rn 'incoming_shape *=' lib/` returns nothing.

Stale input sections survive and bend points accumulate (gap4-12;
pipeline-11). `route_edge` creates a section only when `edge.sections`
is empty and then touches `edge.sections.first` alone
(`edge_router.rb:51-58`), and it does `section.bend_points ||= []`
(`:114`, `:137`) rather than resetting. The corpus case
`spec/fixtures/corpus/stale_sections.json` already names its stale
section `e1_s0`, so its coordinates — (999,999)→(888,888) — are what
proves the reset, not its id:

```sh
# stale extra section passes through untouched
bundle exec ruby -relkrb -rjson -e 'j={id:"root",children:%w[a b c].map{|i|{id:i,width:30,height:30}},edges:[{id:"h",sources:["a"],targets:["c"],sections:[{id:"s0",startPoint:{x:999,y:999},endPoint:{x:998,y:998}},{id:"s1",startPoint:{x:777,y:777},endPoint:{x:776,y:776}}]}]}.to_json; r=Elkrb.layout(Elkrb::Graph::Graph.from_json(j),algorithm:"layered"); puts JSON.generate(JSON.parse(r.to_json)["edges"][0]["sections"])'
# [{"id":"s0",...recomputed...},{"id":"s1","startPoint":{"x":777.0,...}}]

# bend points grow on every re-layout
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.new(id:"r",children:[Elkrb::Graph::Node.new(id:"a",width:100,height:60,ports:[Elkrb::Graph::Port.new(id:"p",x:100,y:30)]),Elkrb::Graph::Node.new(id:"b",width:100,height:60,ports:[Elkrb::Graph::Port.new(id:"q",x:0,y:30)])],edges:[Elkrb::Graph::Edge.new(id:"e",sources:["p"],targets:["q"])]); 3.times{Elkrb.layout(g,algorithm:"box"); print g.edges[0].sections[0].bend_points.size," "}'
# 2 4 6
```

ORTHOGONAL and POLYLINE produce identical output (gap4-11).
`get_routing_style(graph)` (`edge_router.rb:242-250`) reads
`elk.edgeRouting` off the graph, but `route_edge_with_style` (`:253-262`)
sends both ORTHOGONAL and POLYLINE to `route_edge` — `route_polyline_edge`
(`:265-268`) is a bare delegation. The only orthogonal trigger left is
`should_use_orthogonal_routing?` (`:175-177`), which matches the private,
case-sensitive `edge.layout_options["edge.routing"] == "orthogonal"`. The
per-edge `"elk.edgeRouting" => "ORTHOGONAL"` the README documents is
never read.

elkjs 0.11.0 is the target and the goldens are committed (03/S0a).
`spec/fixtures/golden/expected/chain3.json`: `e1_s0` (42,27)→(62,27)
with `incomingShape "n1"` / `outgoingShape "n2"`; `e2_s0` (92,27)→(112,27).
`spec/fixtures/golden/expected/compound_chain.json`: inner `ie1_s0`
(42,27)→(62,27), root `e1_s0` (116,39)→(136,39). (The slice card calls
that root section `e2_s0`; the committed golden says the root edge is
`e1` and its section `e1_s0` — the golden wins.)

Consumer contract: `elk.edgeRouting` is defined but not yet emitted by
sirena; this item is what makes it honoured.

## Do

Everything below is settled (design decision D8) — do not re-decide.

1. In `route_edge`, `route_spline_edge` and `route_polyline_edge`,
   replace the "create if empty" block with an unconditional reset:
   `edge.sections = [Graph::EdgeSection.new(id: "#{edge.id}_s0")]`.
   Stale input sections are discarded, extra sections do not survive, and
   bend points cannot accumulate. Set `section.incoming_shape` to the
   source id as given and `section.outgoing_shape` to the target id as
   given (node id or port id, whichever the edge named).
2. Add `clip_to_border(rect, from, to)` — ray against an axis-aligned
   rectangle, ~25 lines, a pure function with its own unit examples. In
   `route_node_to_node`, take the centre-to-centre line, then
   `start = clip_to_border(source_rect, source_centre, target_centre)`
   and `end = clip_to_border(target_rect, target_centre, source_centre)`.
3. With ports, keep today's endpoint: the port origin from
   `get_port_position` (`edge_router.rb:151-165`). Moving the anchor is
   item 18's call, not this one.
4. Read the routing style through the resolver:
   `get("elk.edgeRouting", edge, @graph)` — edge first, then graph.
   ORTHOGONAL: no bends when start and end share an x or a y; otherwise
   two bends at the mid-coordinate of the dominant axis (`dx >= dy` →
   horizontal-first, `(mid_x, start.y)` and `(mid_x, end.y)`; else
   vertical-first). POLYLINE: no bends. SPLINES: the existing control
   points, computed from the clipped endpoints.
5. Hyperedges in non-layered algorithms keep first-source → first-target
   and one section. elkjs mrtree does the same, and layered raises
   (item 12 / S8 owns that).
6. Rewrite the stale expectations in
   `spec/elkrb/layout/edge_router_spec.rb`. Today `:98` expects the id
   `"e1_section_0"` — it becomes `"e1_s0"`. `:99-102` expects
   (25.0,25.0) → (125.0,25.0), commented "Center of n1" / "Center of n2"
   — those become the border values computed from the fixture geometry,
   and the comments go with them. `:297-300` is the same assertion for
   splines, under an example literally titled "uses node centers for
   routing" (`:293`) — rename it. Fix their siblings the same way.
   Replace every assertion; do not delete one without a replacement.
7. Add the invariant `have_edges_on_node_borders` as its own file
   `spec/support/invariants/have_edges_on_node_borders.rb`, ending with
   `INVARIANTS << :have_edges_on_node_borders`. Never edit
   `corpus_spec`'s list. Port-carrying edges are excluded inside the
   matcher until item 18 lands — encode the exclusion in the matcher.
8. Write the failing specs first: golden `chain3` with
   `fields: %i[sections]` at `tier: :exact` (`e1_s0` (42,27)→(62,27),
   shapes `n1`/`n2`); golden `compound_chain` sections exact (inner
   `ie1_s0` (42,27)→(62,27), root `e1_s0` (116,39)→(136,39)); golden
   `cycle3` sections structural; laying the same graph out twice gives
   identical sections and an unchanged `bend_points.size`; the
   `stale_sections` corpus case comes back with exactly one section whose
   points are recomputed — assert the coordinates, not the id, because
   the fixture's stale section is already called `e1_s0`; ORTHOGONAL on
   nodes at (0,0) and (100,60) sized 30×30 gives 2 right-angle bends,
   POLYLINE 0.

Do not touch: self-loops (item 19 owns `route_self_loop` and will reset
its section the same way), port side placement (item 18), labels
(item 17), `CHANGELOG.md` (item 37 assembles it from the merged PR
bodies' `## Breaking` sections).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- The elk-compat-16 repro prints a start point on `n1`'s right border,
  not its centre:
  `bundle exec exe/elkrb layout spec/fixtures/simple_graph.json | ruby -rjson -e 'j=JSON.parse(STDIN.read); p j["children"][0].values_at("x","y","width","height"), j["edges"][0]["sections"][0].values_at("startPoint","endPoint")'`
- `bundle exec rspec spec/elkrb/golden_spec.rb -e chain3 -e compound_chain`
  passes with `fields: %i[sections]` un-pended.
- `spec/support/invariants/have_edges_on_node_borders.rb` exists,
  self-registers, and `corpus_spec`'s matcher list was not edited by
  hand.

Mandatory gates, in order: `thermo-nuclear-review` → `execution-diff` →
Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. No dependency-contract-check: nothing here crosses
a boundary we do not own — say so in the report rather than skipping
silently.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s11` stack base — and again on the branch, then `diff -r` the two
dump dirs. `corpus:dump`'s exit status is informational; never chain on
it.

INTENDED execution-diff differences, and nothing else:

- Every `sections[].id` changes from `<edge>_section_0` to `<edge>_s0`.
- Every `startPoint`/`endPoint` moves from a node centre to a node
  border (port-anchored endpoints are unchanged — still the port origin).
- Every section gains `incomingShape` and `outgoingShape`.
- `stale_sections` comes back with one section instead of the input's,
  recomputed.
- Cases carrying ORTHOGONAL gain right-angle bends; POLYLINE cases lose
  the bends `route_edge` used to add.
- **Node coordinates are byte-identical to the item-14 (S10) baseline.**
  Prove it by diffing the dumps with `sections` stripped.

Any other difference is a bug.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit):
endpoints move from centres to borders; section ids `_section_0` →
`_s0`; sections gain `incomingShape`/`outgoingShape`. Migration line:
renderers that clipped centre-based lines themselves stop doing so.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
