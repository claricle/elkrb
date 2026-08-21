# 24 — Truthfulness: disco, libavoid, vertiflex, spore, topdown
Slice S18 · branch `fix/s18-truthful-algorithms`

Can start after 10 (S6 moves the `spore.*`, `libavoid.*`, `vertiflex.*`,
`topdownpacking.*` and `disco.*` reads onto the resolver — every one of
them is a raw `graph.layout_options&.[]` today), 11 (S7's `NodeIndex`,
which already fixed disco's component detection and which libavoid's
node map reuses) and 07 (S3b rewrites the 12 `LayoutOptions.new` sites
in `libavoid_spec.rb`, 12 in `vertiflex_spec.rb` and 8 in
`topdown_packing_spec.rb` that this item edits). The XD gate needs 02
(S0b). 03 (S0a) does not gate the START: elkjs 0.11.0 has no disco,
topdownpacking, libavoid or vertiflex algorithm, so there are no goldens
for them and D12 rules invariants instead. It does gate the CLOSE — 03
authors the `spore_overlap4` golden and this item is where its fate is
settled (see `## Do`), so 03 must be in the base before this PR closes.
Blocks the START of 33 (S26), whose libavoid bound is the one added here.
Medium–large (~300 lines). Not on the plan's `## Breaking` carrier list; see
`## Done when`.

## Facts

Measured 2026-08-21 against `v2` (a008889).

**libavoid's A\* never runs** (spore-libavoid-vertiflex-1).
`route_single_edge` (`libavoid.rb:119`) starts from
`get_node_center(source_node)` at `:131`; `build_obstacle_map`
(`:94-106`) makes an obstacle of every node including the source; and
`line_intersects_rectangle?` (`:244-267`) is true when either endpoint
is inside a rectangle. So the start node has zero neighbours, the open
set empties on the first pass, and `find_path` returns the fallback
`[start, goal]`:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.new; g.children=[Elkrb::Graph::Node.new(id:"a",x:0,y:0,width:50,height:50),Elkrb::Graph::Node.new(id:"b",x:200,y:0,width:50,height:50),Elkrb::Graph::Node.new(id:"c",x:100,y:-20,width:50,height:90)]; g.edges=[Elkrb::Graph::Edge.new(id:"e",sources:["a"],targets:["b"])]; Elkrb::Layout::Algorithms::Libavoid.new.layout(g); s=g.edges[0].sections[0]; p [[s.start_point.x,s.start_point.y],s.bend_points.map{|q|[q.x,q.y]},[s.end_point.x,s.end_point.y]]'
# [[37.0, 57.0], [], [237.0, 57.0]]
```

That straight line runs at y=57 from x=37 to x=237, through obstacle `c`
(x 112..162, y 12..102 after padding). No bends, no avoidance.

**libavoid's search is unbounded** (spore-libavoid-vertiflex-2).
`find_path`'s loop is `while open_set.any?` (`libavoid.rb:166`) with no
bounding box and no expansion cap, and `get_orthogonal_neighbors` takes
`step_size = option("libavoid.routingPadding", 10)` (`:215`), so a
padding of 0 gives a zero step. Today this is masked by the defect
above; fixing the start point unmasks it.

**libavoid wipes positions** (spore-libavoid-vertiflex-9).
`position_nodes_if_needed` (`:74-91`) returns early only when **every**
node has `x` and `y`; otherwise it re-grids all children. One
unpositioned node discards the caller's whole layout — from a connector
router that is supposed to move nothing.

**spore_overlap and spore_compaction crash on standard ELK input**
(spore-libavoid-vertiflex-3). Both do arithmetic on `node.x`/`node.y`
directly — `spore_overlap.rb:49` inside `overlapping?`, and the
compaction twins — and `Node#x` defaults to nil:

```sh
bundle exec ruby -relkrb -e 'h={id:"root",children:[{id:"n1",width:100,height:60},{id:"n2",width:100,height:60}]}; %w[spore_overlap spore_compaction].each{|a| begin; Elkrb.layout(Marshal.load(Marshal.dump(h)),algorithm:a); puts "#{a} ok"; rescue=>e; puts "#{a}: #{e.class}: #{e.message}"; end}'
# spore_overlap: NoMethodError: undefined method '-' for nil
# spore_compaction: NoMethodError: undefined method '+' for nil
```

**spore_overlap does not converge** (spore-libavoid-vertiflex-4). It is a
pairwise half-push relaxation (`resolve_overlaps`, `spore_overlap.rb:63`)
under a hard cap read at `:15`
(`graph.layout_options&.[]("spore.maxIterations") || 50`). Pushes
ping-pong; on dense input the loop runs to the cap every time and leaves
real overlaps, and nothing tells the caller.

**vertiflex ignores edges** (spore-libavoid-vertiflex-8). The string
`edges` does not occur in `vertiflex.rb`; output is byte-identical with
and without them, verified by running `VertiFlex#layout` on the same
4-node graph twice, once with an edge and once without. Yet
`vertiflex.rb:18` says "This is an experimental algorithm matching the
Java ELK implementation", and `lib/elkrb.rb:252` registers it under
`category: "layered"`.

**libavoid's registry entry overstates it** (spore-libavoid-vertiflex-12):
`lib/elkrb.rb:240` says "Orthogonal connector routing with obstacle
avoidance" and `:241` `category: "routing"`. `README.adoc:45` says
`Libavoid:: "A*" pathfinding connector routing`. None of that is true
today.

**topdownpacking overwrites declared sizes** (tree-family-14).
`place_nodes_in_grid` (`topdown_packing.rb:153`) assigns
`node.width = node_width` and `node.height = node_height` at `:161-162`
for every node:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb.layout({id:"r",children:%w[a b c d].map{|i|{id:i,width:100,height:50}},edges:[]},algorithm:"topdownpacking"); p g.children.map{|n|[n.width,n.height]}.uniq'
# [[100.0, 100.0]]
```

**disco reads an undocumented arrangement key**: `disco.rb:110` reads
`disco.componentArrangement` (lower-case row/column/grid), while
README.adoc documents `disco.componentCompaction.strategy` and
`disco.spacing.componentComponent` (tree-family-13).

Corpus reach is very narrow. Only four dump files touch these
algorithms: `elkjs_layouters_disco`, `java_elk_disco`,
`java_elk_sporeOverlap`, `java_elk_sporeCompaction`. There is **no**
libavoid, vertiflex or topdownpacking case in the corpus at all, and
neither disco fixture carries any `disco.*` option. At `v2` the two
spore cases fail with `Elkrb::Error: Unknown layout algorithm:
sporeOverlap`; once 08 (S4) normalises the registered name they resolve
and fail with the nil-`x` `NoMethodError` above instead — that is the
state of this item's base.

## Do

1. **`libavoid.rb`** — start A\* from the **border point** of the source
   node facing the target, not `get_node_center` (`:131`). Bound the
   search to the graph bounding box plus padding, snap start and goal
   to the grid (or accept the goal within one step), and add a
   max-expansion cap that falls back to the direct path. Decouple
   `step_size` (`:215`) from `libavoid.routingPadding` so padding 0
   cannot produce a zero step.
2. **`libavoid.rb:74-91`** — `position_nodes_if_needed` assigns
   positions **only** to nodes whose `x`/`y` are nil, placing them
   beside the existing bounding box. Positioned nodes are never moved.
3. **`spore_overlap.rb` / `spore_compaction.rb`** — treat nil `x`/`y` as
   `0.0` at the top of `layout_flat`, as Java ELK does. Keep the
   iteration cap and make exhausting it observable rather than silent.
4. **`vertiflex.rb`** — describe it honestly: it is a column-grid
   approximation that ignores edges. Delete the "matching the Java ELK
   implementation" claim at `:18`. Correct
   `lib/elkrb.rb:251-252` (`description:` and `category:`) **in place**
   — edit those two lines, never append a row at the end of the table.
5. **`lib/elkrb.rb:240-241`** — same for libavoid: the description and
   category must match what step 1 actually delivers.
6. **`README.adoc:45-46`** — correct the libavoid and VertiFlex one-line
   claims in place. 30 (S24) rewrites the README wholesale later and must
   carry these corrections forward, not undo them.
7. **`topdown_packing.rb:153-162`** — only size-less nodes get the cell
   size. A node that declared `width`/`height` keeps them.
8. **`disco.rb:110`** — read the arrangement strategy through the
   resolver from `elk.disco.componentCompaction.strategy` (and the
   legacy `disco.componentArrangement` as an alias). Flip 08's
   pre-seeded `elk.disco.componentCompaction.strategy` row to
   `:honoured` — on its own line, in sorted position, never appended.

**D12 governs the bar: invariants, not goldens.** Do not author or
promote an elkjs golden for any of these five — elkjs 0.11.0 raises
`UnsupportedConfigurationException` for disco and topdownpacking, and
libavoid/vertiflex are elkrb-only. What each one promises is what gets
asserted: no overlap where overlap removal is promised, finite
coordinates, determinism, declared sizes preserved.

**Open item this slice must settle.** 03 (S0a) authors a
`spore_overlap4` golden and no later slice claims it. This item owns
spore. Either promote `spore_overlap4` to `tier: :structural` here, or
record in the report why it stays `pending` under D12 — it must not
reach 35 (S27b) unassigned.

**Specs first**, in the existing files
(`spec/elkrb/layout/algorithms/{libavoid,vertiflex,topdown_packing,spore_overlap,spore_compaction,disco}_spec.rb`),
replacing the tautologies they already carry:

- libavoid: the routed polyline does **not** intersect the blocker
  rectangle in the repro above, and has at least one bend.
- libavoid: `find_path` on a goal that is off the grid step returns
  within the expansion cap instead of spinning.
- libavoid: a graph with two positioned nodes and one unpositioned node
  leaves the two positioned ones exactly where they were.
- spore_overlap / spore_compaction: the nil-`x` graph above lays out and
  every coordinate is finite.
- topdownpacking: `[[100.0, 50.0]]` for the declared-size repro; a
  size-less node still gets the cell size.
- vertiflex: the spec asserts the column grid it actually is.
- disco: `elk.disco.componentCompaction.strategy` of ROW vs COLUMN
  produces different arrangements of the same components.

## Done when

- `bundle exec rake` green.
- The libavoid repro above returns a path with bends that misses `c`.
- The spore repro above prints `spore_overlap ok` and
  `spore_compaction ok`.
- The topdownpacking repro above prints `[[100.0, 50.0]]`.
- `Registry.status("elk.disco.componentCompaction.strategy") == :honoured`.
- `lib/elkrb.rb:240-241`, `lib/elkrb.rb:251-252`, `vertiflex.rb:18` and
  `README.adoc:45-46` each say only what the code does — read all four,
  a grep cannot tell a corrected claim from a stale one.
- `spore_overlap4`'s fate is recorded: promoted to structural, or
  `pending` with a written reason.

Mandatory gates: thermo-nuclear → execution-diff → Codex → copilot-review.
**dependency-contract-check is not required and the plan must say so:**
no external boundary — every read is our own model through the resolver.

**execution-diff intended differences** — driver
`bundle exec rake "corpus:dump[<dir>]"` (quoted) on the branch's base ref
— its merge-base with `v2`, or the `int/s18` stack base while 07, 10 and
11 are unmerged — and again on the branch, then `diff -r`. Exactly two
dump files change:
`java_elk_sporeOverlap` and `java_elk_sporeCompaction`, each going from
`{"error": "NoMethodError…"}` to real layout output — flip their
`KNOWN_FAILURES` `no_crash` rows in `corpus_spec.rb` in the same PR.
`elkjs_layouters_disco` and `java_elk_disco` stay byte-identical because
neither fixture carries a `disco.*` option; libavoid, vertiflex and
topdownpacking have no corpus case at all, so their fixes are
corpus-invisible and the specs are the only evidence. Say that plainly
in the report rather than presenting a two-file diff as full coverage.

The plan's `## Breaking` carrier list does not name this slice, and 37
(S30) builds `CHANGELOG.md` only from those sections. Two user-visible
promises change here: topdownpacking stops discarding declared sizes,
and libavoid stops moving positioned nodes. Put a `## Breaking` section
in the report so 37 can see them; the maintainer decides whether they
land in the 2.0.0 block. Do not edit `CHANGELOG.md`.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`lib/elkrb/layout/algorithms/{libavoid,spore_overlap,spore_compaction,vertiflex,topdown_packing,disco}.rb`,
`lib/elkrb.rb:240-241` and `:251-252`,
`lib/elkrb/options/registry.rb` (one row, in place),
`README.adoc:45-46`,
the six matching spec files under `spec/elkrb/layout/algorithms/`,
`spec/cross_validation/corpus_spec.rb` (two `KNOWN_FAILURES` rows).
