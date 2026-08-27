# 06 — LayoutOptions open map
Slice S3 · branch `fix/s3-open-options-map`

Status: **merged into `v2`** via PR #4, at 36e0eb1. Closed. Gate B (Codex
`ultra`) approved that SHA after seven rounds; the approval artifact is
`.claude/codex-approvals/s3-open-options-map@36e0eb1.txt`.

Can start: now — 01 (S1 crash guards) is already the `v2` seed, and this item
replaces the nil-`@properties` typed class that slice 1 guarded. The XD gate
needs 02 (S0b's `corpus:dump` driver); the build may start before that by
materialising the driver from `fix/s0b-corpus-cli-harness` uncommitted. Blocks
the start of 07 (S3b), 09 (S5 — the resolver has nothing to read until options
survive deserialization), 27 (S21 ELKT parser), 29 (S23 data model) and 34
(S27a consumer fixtures). Parallel with 05 (S2), 08 (S4) and 11 (S7). Medium
(~300 lines including specs). **BREAKING.**

## Facts

Measured against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`.
`bundle exec rspec` there: 625 examples, 0 failures.

`Graph.from_hash` maps snake_case attribute names, not the JSON mapping, so
the camelCase `layoutOptions` key every README and docstring example uses is
dropped at graph, node and edge level (data-model-3; gap4-2; dups pipeline-4,
layered-15, tree-family-8, elk-compat-2):

```sh
bundle exec ruby -relkrb -e 'p Elkrb::Graph::Graph.from_hash({id:"root", layoutOptions:{"elk.algorithm"=>"force"}, children:[{id:"n1",width:10,height:10}]}).layout_options'
# nil
```

`LayoutOptions`'s `json do` block is a fixed key list (`git show
a008889:lib/elkrb/graph/layout_options.rb`, block at `:26-48`) with no
catch-all, so every unmapped `elk.*` key vanishes on read and is absent from
`to_json` (data-model-2; elk-compat-18/19/20):

```sh
bundle exec ruby -relkrb -e 'puts Elkrb::Graph::Graph.from_json(%q({"id":"r","layoutOptions":{"elk.direction":"DOWN","elk.spacing.nodeNode":40}})).to_json'
# {"id":"r"}
```

Two mappings point at the same attribute — `"edgeRouting"` and
`"elk.edgeRouting"` at `layout_options.rb:33-34`, `spline.curvature` /
`elk.spline.curvature` at `:35-36`, `spline.segments` / `elk.spline.segments`
at `:37-38`. Lutaml resolves reads by the last rule, so the bare key is dead
on read and both keys are emitted on write (data-model-7).

The constructor drops options on both paths (data-model-8; tree-family-15;
elk-compat-18). A braceless string-keyed argument binds to `**attributes`,
takes the `super(**attributes)` branch, and lutaml discards unknown keys; a
braced positional Hash skips `super`, so lutaml's set-tracking never marks the
attributes and `to_json` emits `{}`. ~45 spec lines rely on the braceless
form and assert nothing.

`Graph#initialize` constructs the shim at `graph.rb:52`
(`@layout_options ||= LayoutOptions.new`).

Typed-getter read sites at `v2` — these are what the open map removes:

- `hierarchical_processor.rb:73-77` (`extract_node_options` → `.properties`)
  and `:116-124` (`get_padding` → `.properties&.[]`)
- `label_placer.rb:326-332`, `:334-338`, `:341-345` (three `.properties&.[]`
  helpers; slice 1 moved these down ~10 lines from the audit's numbers)
- `base_algorithm.rb:169-179` (`get_edge_routing_style`, term
  `graph.layout_options.edge_routing` at `:174`)
- `edge_router.rb:242-250` (`get_routing_style`, same term at `:247`)
- `dot_serializer.rb:110-113` (`graph.layout_options&.direction`)

Spec/example sites using the typed API at `v2`:
`spec/elkrb/serializers/dot_serializer_spec.rb:295` and `:307-321`;
`spec/elkrb/layout/edge_router_spec.rb:352,416`;
`spec/elkrb/layout/self_loop_spec.rb:624`;
`examples/port_constraints_demo.rb:162-164`.

`LayoutOptions` references across `spec/` and `examples/` at `v2`: **97
`LayoutOptions.new` sites plus one class reference** (`layout_options_spec.rb:5`)
across 15 files. The audit and the original card say 89 — that was 6ac367c;
slice 1 added 8 more. Item 07 (S3b) rewrites them, so use the measured number:

```sh
git grep -o "LayoutOptions" a008889 -- spec examples | wc -l   # 98
```

The corpus (02/S0b) is 47 cases.

Consumer contract: sirena builds Ruby Hashes and calls `Elkrb.layout(hash)`
with a camelCase **symbol** `layoutOptions:` key at the root, and C4 puts a
per-node `layoutOptions` on each boundary (`elk.algorithm: box`,
`elk.box.packingMode`, `elk.padding`, `elk.spacing.nodeNode: "60"` as a
String). Every one of those is dropped today. This item is what makes them
arrive.

## Facts about what shipped

The branch went beyond the original design in three places, each forced by a
gate finding. Treat these as settled, not as drift to undo.

1. `LayoutOptions` is a `::Hash` subclass, but not a bare one
   (`lib/elkrb/graph/layout_options.rb` on the branch, 99 lines). It keeps
   `[]`/`[]=` key stringification, a `merge` that mutates self and returns
   self (matching the removed pre-S3 method, unlike `::Hash#merge`), and a
   private `LEGACY_KWARG_ELK_KEYS` table that translates the old typed
   keyword names to ELK ids for the bare-keyword form only, warning once per
   key per process. An explicit canonical key always wins over a same-call
   legacy alias, in any argument order. `hierarchical` is deliberately
   excluded — decision 7 says it has no ELK counterpart.
   Gate B round 1 also corrected `spacing_node_label:` to
   `elk.spacing.labelNode` (`elk.spacing.nodeLabel` is not an ELK id).
2. Symbol keys are normalised at **two** boundaries, not one.
   `Graph.from_hash` deep-stringifies the whole input tree, and all five
   models (Graph/Node/Edge/Port/Label) carry a `layout_options=` override
   for Symbol keys assigned through a Ruby constructor or setter, which
   bypasses `from_hash` entirely. Both call a shared
   `Elkrb::Graph::DeepStringifyKeys` module (new file
   `lib/elkrb/graph/deep_stringify_keys.rb`, `private_constant`). The
   override calls the lutaml primitives directly —
   `value_set_for(:layout_options)`, then
   `self.class.attributes(lutaml_register)[:layout_options].cast_value(...)`,
   then `instance_variable_set` — because `super` has no ancestor
   implementation to find (lutaml defines the setter on the class itself) and
   a failed `super` falls through to `method_missing`, which installs a
   permanently broken singleton method on that instance. A `Type::Hash`
   subclass was also probed and rejected: `Attribute#hash_type?` does exact
   class equality, so a subclass takes the wrong cast branch and crashes.
3. `graph.layout_options.edge_routing` was NOT simply dropped. Removing it
   broke legacy snake_case YAML — verified against a real `origin/v2`
   worktree: base gives 2 bend points (SPLINES) for a self-loop with
   `layout_options: {edge_routing: SPLINES}`, the first cut gave 4. Both
   `edge_router.rb#get_routing_style` and
   `base_algorithm.rb#get_edge_routing_style` now read
   `graph.layout_options["edge_routing"]` instead, each with the comment
   `# legacy snake_case key; S5's resolver takes over alias handling and
   deletes this line`. **Item 09 (S5) deletes both lines** — the registry
   alias `edge_routing` replaces them.

## Do

Design decision D1, ruled. Do not re-decide any of it.

1. `lib/elkrb/graph/layout_options.rb` becomes the `::Hash`-subclass
   constructor shim described above, marked
   `# @deprecated Migration shim for 1.x call sites; removed in S3b — pass a
   plain Hash.` It is a shim, not 2.0 API.
2. In `graph.rb`, `node.rb`, `edge.rb` (Edge and EdgeSection), `port.rb`,
   `label.rb`, `node_constraints.rb` (both classes) and `geometry/point.rb`,
   rename `json do … end` to `key_value do … end` with the same body. Keep
   every `yaml do … end` block. In the five models that have it, change
   `attribute :layout_options, LayoutOptions` to
   `attribute :layout_options, :hash`; `NodeConstraints` and `Point` get only
   the `key_value` rename.
3. `graph.rb:52` becomes `@layout_options ||= {}`. This is a change, not a
   keep — item 07's `grep -rn LayoutOptions lib` acceptance needs it gone.
4. Override `Graph.from_hash` to deep-stringify keys recursively before
   `super`. Symbol keys otherwise leak into YAML as `:elk.x:`.
5. Add the `layout_options=` override on all five models (see "what
   shipped" item 2). One shared `DeepStringifyKeys` module, not five copies.
6. Rewrite the read sites listed in Facts: `.properties&.[](k)` → `&.[](k)`;
   `.edge_routing` → `["edge_routing"]` with the S5-deletes-this comment;
   `.direction` → `["elk.direction"] || ["direction"]`.
7. Keys are stored **verbatim**. No alias rewriting here — that is the
   resolver's job in item 09.
8. Rewrite slice 1's `spec/elkrb/graph/layout_options_spec.rb`: keep the
   graph/node/edge-level pipeline examples, drop the typed-getter examples.
   Rewrite the "graph-level layoutOptions from_hash" example (v2
   `layout_options_spec.rb:78-84`), which uses the snake_case
   `layout_options:` key this item intentionally stops mapping — kept
   verbatim it would be vacuous. Use `layoutOptions:` with a value assertion
   (`graph.layout_options == {"elk.direction" => "DOWN"}`).
9. Specs first, all driven from input strings and Hashes:
   `Graph.from_json` with `layoutOptions` at graph, node, port, label and
   edge level carrying `elk.algorithm`, `elk.spacing.nodeNode: 40` (Integer
   40 stays Integer), `elk.padding: "[top=1,left=2,bottom=3,right=4]"`,
   `foo.bar: true` and a nested Hash → every map intact and
   `JSON.parse(graph.to_json)["layoutOptions"]` equals the input map; the
   same document through `from_yaml`/`to_yaml`; `Graph.from_hash` with mixed
   Symbol and String keys → `{"elk.algorithm"=>"box","elk.x"=>1}` and
   `to_yaml` containing `elk.x: 1`, not `:elk.x:`; the four shim constructor
   forms; `Graph.new(id: "r").to_json` has no `layoutOptions` key and neither
   does `Graph.from_json('{"id":"r","layoutOptions":{}}')`;
   `Graph.from_json('{"id":"r","children":[…]}').layout_options` is nil and
   `Elkrb.layout(graph)` still runs; mutation through the getter sticks.
10. Pin the two lutaml quirks the DCC found, and state the promise honestly:
    **every dotted / ELK-style key survives the round trip; the bare keys
    `text` and `elements` are reserved by lutaml-model and are not supported
    inside layoutOptions.** Put that sentence in the `LayoutOptions`
    docstring; item 30 (S24) carries it into the README.

Do not touch: alias resolution, precedence or algorithm selection (item 09);
`Graph.from_hash`'s snake_case `layout_options:` support (intentionally
dropped); README (item 30); `CHANGELOG.md` (item 37 assembles it from the
merged PR bodies' `## Breaking` sections).

## Done when

Verified on the branch at `3089e99`:

- `bundle exec rspec` → **642 examples, 0 failures** (v2 baseline 625).
- Flat round trip:
  `bundle exec ruby -relkrb -e 'puts Elkrb::Graph::Graph.from_json(%q({"id":"r","layoutOptions":{"elk.direction":"DOWN","elk.spacing.nodeNode":40}})).to_json'`
  → `{"id":"r","layoutOptions":{"elk.direction":"DOWN","elk.spacing.nodeNode":40}}`
- Hash input with mixed key types:
  `Graph.from_hash({id:"r", layoutOptions:{"elk.algorithm"=>"box", :"elk.x"=>1}}).layout_options`
  → `{"elk.algorithm" => "box", "elk.x" => 1}`
- Empty map omitted: `Graph.new(id: "r").to_json` has no `layoutOptions` key.
- The two reserved keys behave as pinned:
  `{"layoutOptions":{"text":"v"}}` raises `Lutaml::Model::InvalidFormatError`;
  `{"layoutOptions":{"elements":{"a":1},"b":2}}` comes back as `{"a"=>1}`.
- `grep -rn "\.properties" lib/elkrb/layout lib/elkrb/serializers` shows only
  element-level `properties` reads — no `layout_options.properties`.

Gates, in this order. `thermo-nuclear-review` → `dependency-contract-check`
(**mandatory**) → `execution-diff` (**mandatory**) → Codex (max reasoning,
read-only, verify-before-critique) → `copilot-review` last.

The dependency-contract-check ran the truth table against the real
lutaml-model 0.8.19 gem: a `:hash` attribute × {nil, `{}`, `{"k"=>1}`,
`LayoutOptions.new("k"=>1)`, `{sym: 1}`, nested Hash, `{"text"=>"v"}`,
`{"elements"=>{"a"=>1},"b"=>2}`} × {from_json, from_yaml, from_hash with and
without the override, `.new(layout_options:)`, setter then mutate the
original, getter identity, to_json, to_yaml}. It is what found the two
reserved keys and what proved the `Type::Hash` subclass and the `super`-based
setter both broken. The table itself is not tracked; what it established is
pinned by the committed examples in `spec/elkrb/graph/layout_options_spec.rb`
at `3089e99` — the JSON, YAML and Hash round trips at `:59-182`, the
constructor / setter / getter-mutation and empty-map cases at `:184-235`, and
the two reserved keys at `:322-335`.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's merge-base with `v2`, then on the branch, then
`diff -r` the two dump dirs. The rake exit status is informational; never
chain on it.

INTENDED execution-diff difference, and nothing else: `layoutOptions` is now
present and flat in the output of every case that carried it on input.
Anything else is a bug. The post-Gate-A re-run over the same 47-case dump was
byte-identical to the pre-Gate-A branch dump — the Gate A fixes restore base
behaviour on paths no committed fixture exercises (no fixture carries
snake_case `edge_routing`, none constructs `layout_options` with Symbol keys
directly).

Gate B (Codex `ultra`) went a further five rounds after this record was
written, and approved the branch at `36e0eb1`. That is the SHA merged into
`v2` by PR #4. The approval artifact is
`.claude/codex-approvals/s3-open-options-map@36e0eb1.txt`.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit):
`layoutOptions` is echoed flat; the `layoutOptions.properties` nesting is no
longer serialised; typed getters and setters are gone; the snake
`layout_options:` Hash key is dropped. Migration: move keys one level up, use
ELK ids, index with `[]`.

## Files

`lib/elkrb/graph/layout_options.rb`, `lib/elkrb/graph/deep_stringify_keys.rb`
(new), `lib/elkrb/graph/{graph,node,edge,port,label,node_constraints}.rb`,
`lib/elkrb/geometry/point.rb`, `lib/elkrb.rb` (one require),
`lib/elkrb/layout/hierarchical_processor.rb`,
`lib/elkrb/layout/label_placer.rb`,
`lib/elkrb/layout/algorithms/base_algorithm.rb`,
`lib/elkrb/layout/edge_router.rb`, `lib/elkrb/serializers/dot_serializer.rb`,
`spec/elkrb/graph/layout_options_spec.rb`, plus the five spec/example lines
listed in Facts.
