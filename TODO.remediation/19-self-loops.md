# 19 — Self-loops
Slice S13b · branch `fix/s13b-self-loops`

Can start after 16 (S11 sets the section-reset shape, the `<edge>_s0` id and
`clip_to_border` — this item reuses all three), 18 (S13 resolves a port to its
owning node and fixes the port anchor, which is what lets `self_loop?`
recognise a port-to-port loop) and 07 (S3b rewrites the 12 `LayoutOptions.new`
sites in `self_loop_spec.rb`). The golden `self_loop` needs 03 (S0a); the XD
gate needs 02 (S0b) and its `self_loop` corpus case. Blocks the START of 30
(S24's README), which carries a paragraph on loop geometry; contributes a
`## Breaking` section to 37 (S30's CHANGELOG). Small (~150 lines).

## Facts

Verified against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`.

The orthogonal self-loop is a self-retracing zigzag, not the documented
rectangle (pipeline-12). `route_east_self_loop`
(`edge_router.rb:492-517`) emits four bends at `:510-515`:

```sh
bundle exec ruby -relkrb -e 'n=Elkrb::Graph::Node.new(id:"n",width:100,height:60); g=Elkrb::Graph::Graph.new(id:"r",children:[n],edges:[Elkrb::Graph::Edge.new(id:"l",sources:["n"],targets:["n"])]); Elkrb.layout(g,algorithm:"box"); s=g.edges[0].sections[0]; p s.id; p [[s.start_point.x,s.start_point.y],*s.bend_points.map{|b|[b.x,b.y]},[s.end_point.x,s.end_point.y]]'
# "l_section_0"
# [[112.0, 42.0], [172.0, 42.0], [172.0, -2.0], [172.0, 86.0], [112.0, 47.0], [112.0, 52.0]]
```

The x=172 leg runs up to y=-2, then back down through y=42 to y=86 —
one segment drawn twice — and the last leg is a diagonal back to the
node. y=-2 is also above the node's top (y=12) and outside the graph.
WEST, NORTH and SOUTH follow the same pattern at `:519-596`.

The section id is `<edge>_section_0`, not `<edge>_s0`. `route_self_loop`
creates it at `edge_router.rb:423-428` (id at `:427`) and only when
`edge.sections` is empty (`:424`) — a stale input section is reused
instead of replaced, the same defect item 16 fixes for ordinary edges.

A port-to-port edge on one node is not treated as a loop (gap4-6).
`self_loop?` (`edge_router.rb:401-408`) compares raw endpoint strings at
`:407` (`sources.first == targets.first`), so `p1 -> p2` on node `n`
goes through `route_edge` and is routed straight through the node body:

```sh
bundle exec ruby -relkrb -e 'n=Elkrb::Graph::Node.new(id:"n",width:100,height:60,ports:[Elkrb::Graph::Port.new(id:"p1",x:100,y:30,width:8,height:8,side:"EAST"),Elkrb::Graph::Port.new(id:"p2",x:50,y:60,width:8,height:8,side:"SOUTH")]); g=Elkrb::Graph::Graph.new(children:[n],edges:[Elkrb::Graph::Edge.new(id:"e",sources:["p1"],targets:["p2"])]); Elkrb.layout(g,algorithm:"fixed"); s=g.edges[0].sections[0]; p [[s.start_point.x,s.start_point.y],*s.bend_points.map{|q|[q.x,q.y]},[s.end_point.x,s.end_point.y]]'
# [[112.0, 42.0], [62.0, 42.0], [62.0, 72.0]]
```

The node spans x 12..112, y 12..72; the bend (62,42) is inside it.
Because `route_self_loop` is only entered when the raw source string
equals the raw target string, `route_self_loop_with_ports`
(`edge_router.rb:745`) always sees `source_port == target_port`, so the
"different sides" branches of `route_orthogonal_port_self_loop`
(`:872-877`) and `route_spline_port_self_loop` (`:923-928`) are dead.

A same-port loop degenerates to a zero-area out-and-back line, and every
port loop on a node shares offset 0 (gap4-7). `get_self_loop_index`
(`edge_router.rb:451-461`) compares `e.sources&.first == node.id`
(`:456`), which is never true for a port id:

```sh
bundle exec ruby -relkrb -e 'n=Elkrb::Graph::Node.new(id:"n",width:100,height:60,ports:[Elkrb::Graph::Port.new(id:"p1",x:100,y:20,width:8,height:8,side:"EAST")]); g=Elkrb::Graph::Graph.new(children:[n],edges:[1,2].map{|i|Elkrb::Graph::Edge.new(id:"l#{i}",sources:["p1"],targets:["p1"])}); Elkrb.layout(g,algorithm:"fixed"); g.edges.each{|e|s=e.sections[0]; p [e.id,[[s.start_point.x,s.start_point.y],*s.bend_points.map{|q|[q.x,q.y]},[s.end_point.x,s.end_point.y]]]}'
# ["l1", [[112.0, 42.0], [162.0, 42.0], [162.0, 42.0], [162.0, 42.0], [112.0, 42.0]]]
# ["l2", [[112.0, 42.0], [162.0, 42.0], [162.0, 42.0], [162.0, 42.0], [112.0, 42.0]]]
```

Three coincident bend points, no enclosed area, and the two loops are
identical. `calculate_loop_offset` (`edge_router.rb:703-706`) is a
hard-coded `20.0 * (index + 1)`; `elk.selfLoopOffset` and
`elk.selfLoopRouting` are documented but read nowhere in `lib/`. Only
`elk.selfLoopSide` is read, by `get_self_loop_side`
(`edge_router.rb:709-727`), which defaults to EAST (`:726`).

The elkjs 0.11.0 golden pins the target and it is NOT EAST.
`spec/fixtures/golden/expected/self_loop.json`: node `a` at (12,22)
30×30, self-loop `e2_s0` start (22,22) end (32,22) with bends (22,12)
and (32,12) — it leaves and re-enters the NORTH border, 10px out. Root
graph is **104×64** (two nodes plus the loop), not the 54×64 the slice
card guessed before the golden existed. The golden is `pending` in
`spec/elkrb/golden_spec.rb` today, on the node-placement reason ("RC7:
layered ignores elk.direction and uses a 60px layer gap…"), so item 13
(S9) clears the node half and this item clears the section half.

Corpus case: `spec/fixtures/corpus/self_loop.json` — one 30×30 node with
`e1: a -> a`, algorithm `layered`.

`spec/elkrb/layout/self_loop_spec.rb` carries tautologies that pass
whatever the geometry is; the example at `:406` ("routes self-loop
between two ports") never reaches `route_self_loop` at all — it asserts
start and end only, and `p1 -> p2` is routed by `route_edge` (gap4-16).
The offset-monotonicity example is real — `expect(bend_x_1).to be >
bend_x_0` at `self_loop_spec.rb:565` — keep it.

## Do

1. `self_loop?` (`edge_router.rb:401-408`): resolve each endpoint to its
   owning node through item 11's `NodeIndex` before comparing. An edge
   is a loop when the resolved source node is the resolved target node
   — same node id, same port, or two different ports on one node.
2. `route_self_loop` (`edge_router.rb:411-447`): replace the "create if
   empty" block at `:423-428` with an unconditional
   `edge.sections = [Graph::EdgeSection.new(id: "#{edge.id}_s0")]`, and
   set `incoming_shape` / `outgoing_shape` exactly as item 16 does. No
   output may mix `_s0` and `_section_0` ids after this lands.
3. `get_self_loop_index` (`edge_router.rb:451-461`): resolve the edge's
   source to its node before the `== node.id` comparison at `:456`, so
   two port loops on one node get distinct offsets instead of both
   getting 0.
4. The orthogonal loop becomes a real rectangle: leave the node at the
   border on the chosen side (`elk.selfLoopSide`, keeping today's EAST
   default from `get_self_loop_side`), go out by the offset, across,
   and back in at the border. At least four distinct points, and no
   segment traversed twice. Fix WEST, NORTH and SOUTH the same way.
5. Spline and polyline loops start and end on the border, not at a
   centre.
6. Replace the tautologies in `spec/elkrb/layout/self_loop_spec.rb` with
   value assertions. Keep the `:565` offset-monotonicity assertion. Every
   replaced example gets a concrete expected coordinate — the ground rule
   is replace, never delete.
7. Write the failing specs first: golden `self_loop` at
   `tier: :structural` (the loop leaves and re-enters a border; graph
   dimensions within 1px of the golden's 104×64 — assert structure, not
   NORTH, since elkjs defaults to NORTH and ours stays EAST); a loop on
   `a` via its ports `p1 -> p2` is routed as a loop, with at least one
   point outside the node rectangle; a same-port loop has ≥ 3 distinct
   points; a self-loop's single section id is `"#{edge.id}_s0"` with
   both shapes set.

Do not touch: node-to-node routing (item 16), port placement (item 18),
`CHANGELOG.md`.

## Done when

- `bundle exec rake` is green.
- The pipeline-12 repro above prints an id ending `_s0` and a path with
  no repeated segment and no point above the node's top border.
- The gap4-6 repro prints a path with at least one point outside the
  node rectangle (x 12..112, y 12..72).
- The gap4-7 repro prints two DIFFERENT paths for `l1` and `l2`, each
  with distinct bend points.
- `bundle exec rspec spec/elkrb/golden_spec.rb -e self_loop` passes at
  `tier: :structural`, with the section half no longer pending.
- `grep -rn '_section_0' lib spec` returns nothing.

Mandatory gates, in order: `thermo-nuclear-review` → `execution-diff` →
Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. No dependency-contract-check: nothing here crosses
a boundary we do not own — say so in the report.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref and on the branch, then `diff -r`.
The exit status is informational; never chain on it.

INTENDED execution-diff differences, and nothing else:

- Self-loop cases only: `self_loop`, `java_elk_self_loops`, and any
  corpus case whose graph carries a loop.
- The loop section id changes from `<edge>_section_0` to `<edge>_s0`.
- The loop path becomes a rectangle on the border: start and end move,
  the bend list changes, and the retraced segment disappears.
- Port-to-port edges on one node stop being routed through the node body
  and become loops.
- Multiple port loops on one node get distinct geometry.
- **Every case with no self-loop is byte-identical**, including node
  coordinates in the loop cases themselves.

Any other difference is a bug.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit):
self-loop section ids `_section_0` → `_s0`; loop geometry moves onto the
node border and becomes a rectangle; a port-to-port edge on one node is
now a loop. List the spec tautologies replaced and the value each one
now asserts.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
