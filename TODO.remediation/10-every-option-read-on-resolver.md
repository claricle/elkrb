# 10 — Every remaining option read onto the resolver
Slice S6 · branch `fix/s6-resolver-everywhere`

Can start after 09 (S5 — the `Resolver`, `BaseAlgorithm#resolver`, the
`option(key, default:)` keyword and the once-set `@graph` are all its work,
and this item is nothing but callers of them) and 11 (S7 — its `NodeIndex`
rewrites the endpoint lookups in the same `edge_router.rb` hunks). The XD gate
needs 02 (S0b's `corpus:dump`). Blocks the start of 13 (S9), 14 (S10), 16
(S11), 17 (S12), 18 (S13), 20 (S14), 22 (S16), 23 (S17), 24 (S18) and 35
(S27b) — every one of those reads an option, and none should be written
against two conventions. Parallel with 07 (S3b), 12 (S8), 26 (S20) and 27
(S21). Large (~350 lines). Not breaking — pure re-routing of reads.

## Facts

Measured against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`, and
against the item-06 branch (`fix/s3-open-options-map` @ `3089e99`) where the
count changes.

Two opposite conventions live side by side. `libavoid.rb` reads its options
only from the constructor Hash through `BaseAlgorithm#option`, never from
`graph.layout_options`; `spore_overlap.rb`, `spore_compaction.rb`,
`vertiflex.rb`, `topdown_packing.rb` and `disco.rb` read only from
`graph.layout_options`, never from the constructor
(spore-libavoid-vertiflex-6/7; force-family-7). Neither honours an ELK id.

The read sites, with their current line numbers at `v2`:

- `edge_router.rb:175-177` `should_use_orthogonal_routing?` — matches the
  private, case-sensitive `edge.layout_options["edge.routing"] ==
  "orthogonal"`. The `"elk.edgeRouting" => "ORTHOGONAL"` the README puts on
  edges is never read (gap4-11):

  ```sh
  bundle exec ruby -relkrb -rjson -e 'j=%q({"id":"r","children":[{"id":"a","x":0,"y":0,"width":30,"height":30},{"id":"b","x":100,"y":80,"width":30,"height":30}],"edges":[{"id":"e","sources":["a"],"targets":["b"],"layoutOptions":{"elk.edgeRouting":"ORTHOGONAL"}}]}); g=Elkrb::Graph::Graph.from_json(j); Elkrb.layout(g,algorithm:"fixed"); p g.edges[0].sections[0].bend_points.size'
  # 0     <- ORTHOGONAL ignored; the private "edge.routing" => "orthogonal" gives 2
  ```

- `edge_router.rb:242-250` `get_routing_style` — a second, duplicate copy of
  `BaseAlgorithm#get_edge_routing_style` (`:169-179`).
- `edge_router.rb:354-360` `get_spline_curvature(edge)` — edge only.
- `edge_router.rb:392-398` `get_routing_direction(edge)` — edge only.
- `edge_router.rb:709-726` `get_self_loop_side(edge, node)` — edge then node.
- `label_placer.rb:326-332`, `:334-338`, `:341-345` — the private keys
  `node.label.placement`, `label.placement`, `label.padding`, `label.margin`.
  ELK's `elk.nodeLabels.placement` / `elk.portLabels.placement` /
  `elk.edgeLabels.placement` appear nowhere in `lib/` (gap4-5).
- `hierarchical_processor.rb:116-124` `get_padding(node)` plus its private
  `parse_padding`.
- `force.rb:28-30` (`iterations`, `repulsion`, `temperature`; constants at
  `:20-22` are 300 / 5.0 / 0.001), `stress.rb:27-28` (`iterations`,
  `epsilon`; constants at `:20-21` are 500 / 0.0001), `box.rb:18` and
  `random.rb:17` (`aspect_ratio` 1.6), `disco.rb:20`, `:26`, `:110`
  (`disco.componentAlgorithm` `"layered"`, `disco.componentSpacing` 20.0,
  `disco.componentArrangement` `"row"`), `spore_overlap.rb:15-16` (50 /
  10.0), `spore_compaction.rb:15-16` (`"both"` / 10.0), `vertiflex.rb:41-68`
  plus its private `get_option` at `:89`, `topdown_packing.rb:100-137` plus
  its private `get_option` at `:137`, `libavoid.rb:95`, `:158`, `:159`,
  `:215` (10 / 1.0 / 2.0 / 10).

`elk.selfLoopOffset` and `elk.selfLoopRouting` have **no read site at all** in
the layout path — only dead accessors in `layout_options.rb:213-222`, which
item 06 deletes (elk-compat-20). There is nothing to migrate for them. Item 08
already registers both as `:accepted` with a "not yet wired" note; leave that
status alone.

The acceptance grep's baseline:

```sh
# on v2 (a008889)
grep -rn 'layout_options\[\|layout_options&\.\[\|options\[:' lib/elkrb/layout | wc -l   # 24
# on the item-06 branch, after .properties&.[] becomes &.[]
grep -rn 'layout_options\[\|layout_options&\.\[\|options\[:' lib/elkrb/layout | wc -l   # 32
```

After item 06 the 32 lines sit in nine files: `edge_router.rb` 12,
`label_placer.rb` 4, `disco.rb` 3, `base_algorithm.rb` 3, `layout_engine.rb` 2,
`hierarchical_processor.rb` 2, `spore_overlap.rb` 2, `spore_compaction.rb` 2,
`layered/node_placer.rb` 2. Item 09 clears `node_placer.rb` and part of
`base_algorithm.rb`; this item clears the rest. `layout_engine.rb:49` is a
stale docstring line (`# 1. options[:algorithm] …`) that would keep the grep
non-empty on its own — delete it.

Two spec files build the router as a bare mixin host with no `@resolver` and
no `@graph` (`edge_router_spec.rb:6-11`, `self_loop_spec.rb:6-11`):

```ruby
let(:router_class) { Class.new { include Elkrb::Layout::EdgeRouter } }
let(:router)       { router_class.new }
```

Both harnesses break the moment the mixin reads `@resolver`.

Corpus is 47 cases (02/S0b).

Consumer contract: `elk.edgeRouting` is defined but not yet emitted by sirena;
`elk.spacing.nodeNode` is emitted and must be honoured by every algorithm,
including the C4 boundary value `"60"` given as a String. String coercion is
the registry's job (item 08), reached through the resolver here.

## Do

Ruled: this is **pure re-routing of reads**. Every default moves into the
registry verbatim. **No semantic change.** The corpus dump must come out
byte-identical.

1. `edge_router.rb`: delete `get_routing_style` outright — `BaseAlgorithm`'s
   `get_edge_routing_style` is the one path.
2. `should_use_orthogonal_routing?(edge)` →
   `@resolver.get("elk.edgeRouting", edge, default: nil)&.to_s&.upcase ==
   "ORTHOGONAL"`. **Edge only** — exactly today's scope. The registry alias
   `edge.routing` covers the legacy key, and the comparison is
   case-insensitive because today's value is lowercase `"orthogonal"`. Item
   16 (S11) is what extends the chain to `@graph` and decides what a
   graph-level ORTHOGONAL means; do not do it here.
3. `get_spline_curvature(edge)` → `get("elk.spline.curvature", edge, default:
   0.5)` — edge only, as today. `get_routing_direction(edge)` →
   `get("elk.direction", edge, default: nil)` — edge only, as today.
   `get_self_loop_side(edge, node)` → `get("elk.selfLoopSide", edge, node)`.
   There are no offset or routing twins to migrate (see Facts).
4. `label_placer.rb:326-345`: `label_placement_option(element, key)` →
   `get("elk.nodeLabels.placement", element)`, with the registry aliases
   `node.label.placement` and `label.placement` doing the legacy work.
   `label_padding_option` → `get("label.padding", element)`;
   `label_margin_option` → `get("label.margin", element)`.
5. `hierarchical_processor.rb`: `get_padding(node)` →
   `Registry.coerce("elk.padding", @resolver.get("elk.padding", node))`;
   delete `parse_padding`. Item 14 (S10) depends on this item and deletes both
   afterwards — there is no ordering conflict.
6. Migrate the keys and reads in `force.rb:28-30`, `stress.rb:27-28`,
   `box.rb:18`, `random.rb:17`, `disco.rb:20/26/110`,
   `spore_overlap.rb:15-16`, `spore_compaction.rb:15-16`, `vertiflex.rb:41-68`,
   `topdown_packing.rb:100-137` and `libavoid.rb:95/158/159/215` to canonical
   ids through the resolver. Delete the private `get_option` helpers in
   `vertiflex.rb` and `topdown_packing.rb`. Item 09 already switched these
   call sites from `option(key, literal)` to `option(key, default: literal)`;
   this item changes the keys and the lookup, not the shape.
7. `layered/node_placer.rb` and `layered.rb`: **do not touch.** The
   keyword-ctor change is item 09's and is already done when this starts.
8. Registry: add any elkrb-private id these sites read that item 08 missed,
   with the literal default from the call site. One row per line, inserted in
   sorted id position, never appended.
9. Give both spec harnesses a resolver:
   `attr_reader :resolver; def initialize(opts = {}); @resolver =
   Elkrb::Options::Resolver.new(opts); end` in `router_class`, and set
   `@graph` wherever a graph is routed. Item 16 (S11) extends the chain to
   `@graph` on top of this harness, so build it once and build it right.
10. Delete the stale docstring line `layout_engine.rb:49`
    (`# 1. options[:algorithm] or options["algorithm"]`) — item 09 already
    made the selection order wrong there, and the acceptance grep matches it.
11. Specs first: `spec/elkrb/options/option_plumbing_spec.rb`. Build a table
    over `Registry.for_algorithm(name).select { |id| Registry.status(id) ==
    :honoured }` for each registered algorithm. For each (algorithm, id) with
    a sensible test value, lay out a 4-node fixture through
    `Elkrb.layout(Graph.from_json(json_with_option_at_root))` and assert the
    canonical JSON **differs** from the run without the option — value-
    changing, never `not_to raise_error`. For an id that cannot move a 4-node
    output (`elk.stress.epsilon`), pick a value that does: a huge epsilon
    stops after one iteration. Only when that is genuinely impossible, spy on
    `Resolver#get` (`instance_spy` with `and_call_original`) and assert the id
    was read. `:partial` rows assert the bounded effect named in the
    registry's `note:`. `:accepted` and `:unsupported` rows assert the output
    is byte-identical with and without the key. Plus one direct row:
    `"elk.edgeRouting":"ORTHOGONAL"` on an **edge**, via JSON, yields the bend
    points that `edge.routing: "orthogonal"` used to.

Do not touch: any default value's *meaning*; port constraint reads (item 18 —
`properties.portConstraints` is explicitly out of scope here); label placement
semantics (item 17); `CHANGELOG.md` (item 37).

## Done when

- `grep -rn 'layout_options\[\|layout_options&\.\[\|options\[:' lib/elkrb/layout`
  returns **no lines**. `Resolver` lives in `lib/elkrb/options/`, so it does
  not match; `BaseAlgorithm#option` no longer contains `options[:` after item
  09; `layout_engine.rb:49` is deleted.
- `bundle exec rake` green (spec + rubocop; 04/S28 made that the bar).
- `spec/elkrb/options/option_plumbing_spec.rb` covers every honoured id of
  every registered algorithm, and each row asserts a value change or a
  verified read — no row asserts only that nothing raised.
- The gap4-11 repro now yields bend points for a per-edge
  `"elk.edgeRouting":"ORTHOGONAL"`.
- `grep -rn "def get_option" lib/elkrb` returns nothing.

Gates, in this order: `thermo-nuclear-review` → `execution-diff` (**mandatory
and strict**) → Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. **No dependency-contract-check** — every boundary this
item touches is elkrb's own, and item 09 already proved the Thor and
`ElkPadding` contracts. Say that in the report rather than skipping it
silently.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s6` stack base while 09 and 11 are unmerged — and again on the branch,
then `diff -r` the two dump dirs. The rake exit status is informational; never
chain on it.

INTENDED execution-diff differences: **none.** The corpus must be
byte-identical across all 47 cases. If a case differs, trace it to a graph
carrying a key that previously only worked as a call-level option, and record
it in the report with the key that caused it — the orchestrator carries that
into the PR body. An untraced difference is a bug, not a diff to accept.

The report carries the plumbing table (algorithm × id → "changes output" /
"read verified") and any read site that could not be migrated, with the
reason.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then Gate B
(Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`lib/elkrb/layout/edge_router.rb`, `lib/elkrb/layout/label_placer.rb`,
`lib/elkrb/layout/hierarchical_processor.rb`,
`lib/elkrb/layout/layout_engine.rb` (one docstring line),
`lib/elkrb/layout/algorithms/{force,stress,box,random,disco,spore_overlap,spore_compaction,vertiflex,topdown_packing,libavoid}.rb`,
`lib/elkrb/options/registry.rb` (any missing private ids),
`spec/elkrb/options/option_plumbing_spec.rb` (new),
`spec/elkrb/layout/edge_router_spec.rb`, `spec/elkrb/layout/self_loop_spec.rb`.
