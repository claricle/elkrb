# 13 — Layered: direction, ELK spacing, cross-axis centring
Slice S9 · branch `fix/s9-layered-direction`

Can start after 09 (S5 — the resolver, and the `--direction` /
`--edge-routing` flags that S5 installs on all three commands; this item only
makes layered honour the key those flags write), 10 (S6 — every remaining
option read moves onto the resolver, including the `@options[:layer_spacing]`
/ `@options[:spacing_node_node]` reads in `NodePlacer` that this item
replaces) and 12 (S8 — layers must come from the real edge set before their
coordinates are worth pinning). Goldens need 03 (S0a); the XD gate and the CLI
spec's `run_elkrb` need 02 (S0b). Blocks the START of 14 (S10 — the compound
goldens are stated in this item's coordinates), 16 (S11) and 31 (S25a). Merge
before 36 (S29) touches `cli_spec.rb`: this item adds a `describe` section
there and 36 rewrites the file wholesale. Small (~180 lines). **BREAKING:
every layered coordinate moves.**

## Facts

Measured on 11's head (3d91c5e) in
`~/.claude/pipeline/worktrees/elkrb/s7-node-index`. Nothing between here and
this item's real base touches `node_placer.rb`.

`elk.direction` is ignored by every algorithm (layered-5; elk-compat-4;
cli-security-9; elk-compat-23). All four values give byte-identical output:

```sh
bundle exec ruby -relkrb -e 'g={id:"r",children:%w[n1 n2 n3].map{|i|{id:i,width:30,height:30}},edges:[{id:"e1",sources:["n1"],targets:["n2"]},{id:"e2",sources:["n2"],targets:["n3"]}]}; %w[RIGHT DOWN LEFT UP].each{|d| r=Elkrb.layout(Marshal.load(Marshal.dump(g)),algorithm:"layered","elk.direction"=>d); puts "#{d}: "+r.children.map{|n|"#{n.id}(#{n.x},#{n.y})"}.join(" ")+" root #{r.width}x#{r.height}"}'
# RIGHT: n1(12.0,12.0) n2(12.0,102.0) n3(12.0,192.0) root 54.0x234.0
# DOWN:  identical.  LEFT: identical.  UP: identical.
```

That input is `spec/fixtures/simple_graph.json` — three 30×30 nodes in a chain.
The committed elkjs golden for it (`spec/fixtures/golden/expected/chain3.json`)
is n1 (12,12), n2 (62,12), n3 (112,12), root 154×54, with `e1_s0` running
(42,27) → (62,27).

`NodePlacer` hard-codes the axes. `calculate_layer_y_positions`
(`node_placer.rb:48-59`) advances layers along y; `place_layer` (`:61-72`)
stacks nodes within a layer along x. Neither reads any direction.

The layer gap is 60, not ELK's 20. `node_placer.rb:16-17`:

```ruby
@layer_spacing = options[:layer_spacing] || 60.0
@node_spacing = options[:spacing_node_node] || 20.0
```

Those are raw symbol reads off the options Hash, so `"elk.layered.spacing.nodeNodeBetweenLayers"`
never lands. 08's registry row for that key already carries the same 60.0, with
the description saying so. Registry rows are one per line sorted by id, so the
key is the locator — line numbers in `lib/elkrb/options/registry.rb` move as
later slices insert rows.

There is no cross-axis centring. `place_layer` starts every layer at `x = 0`
under a comment that says "Center the layer horizontally". The layer widths
`calculate_layer_widths` computes are passed in as `_layer_width` and dropped.

Two other registry defaults are already right and must not be touched:
`elk.spacing.nodeNode` is already 20.0 and `elk.padding` is already
`"[top=12,left=12,bottom=12,right=12]"`.

`elk.direction`'s registry row has default `"UNDEFINED"`, with `UNDEFINED` in
its enum values.

`cli.rb` today declares `--direction` on `diagram` only (`cli.rb:79-80`). 09
puts it on all three commands and makes it write canonical `elk.direction` onto
the root.

Golden cases this item pins, all committed by 03:

| case | elkjs expected |
|---|---|
| `chain3` | n1 (12,12) n2 (62,12) n3 (112,12), root 154×54 |
| `direction_down` | n1 (12,12) n2 (12,62) n3 (12,112), root 54×154 |
| `spacing_override` (both spacings 40) | n1 (12,12) n2 (82,12) n3 (152,12), root 194×54 |
| `cycle3` | a (12,18) b (62,23) c (112,18), root 154×65 |

## Do

1. Defaults are settled (D6, ruled): `elk.direction` RIGHT,
   `elk.layered.spacing.nodeNodeBetweenLayers` 20, `elk.spacing.nodeNode` 20,
   padding 12. Only one registry row actually moves — flip
   `elk.layered.spacing.nodeNodeBetweenLayers` from 60.0 to 20.0 and rewrite its
   description, which today explains the 60.0 deviation. The other three are
   already those values.
2. `elk.direction` keeps ELK's `UNDEFINED` default in the registry, and layered
   treats `UNDEFINED` as `RIGHT` at the read site — that is what ELK does
   (aspect ratio 1.6 ≥ 1), and it means an explicit `"UNDEFINED"` from a
   consumer behaves the same as an absent key. Read it through the resolver:
   `@resolver.get("elk.direction", graph)`.
3. Place in a (layer axis, cross axis) frame, then map to x/y. This is the ruled
   formula; do not re-derive it:
   - Layer *i* starts at `sum(max extent of layers 0..i-1 along the layer axis) + i * layer_gap`.
   - Within a layer, nodes stack along the cross axis separated by `node_gap`.
   - Each layer is centred on the cross axis against the widest layer:
     `offset = (max_layer_extent - this_layer_extent) / 2`.
   - RIGHT → (layer→x, cross→y). DOWN → (layer→y, cross→x). LEFT → mirror x
     within the bbox. UP → mirror y.
4. This reproduces elkjs exactly for chains, DOWN chains and the compound case.
   It does not for fan-out: elkjs's Brandes-Köpf puts the parent at y = 17, this
   formula gives 37. Do not chase it — decision 7 defers BK and keeps fan-out at
   the structural tier.
5. `layered.rb` reads the two spacings and the direction through the resolver
   and hands them to `NodePlacer`; `NodePlacer` stops reading `@options` by
   symbol key.
6. No `cli.rb` change. The flags and their help table are 09's, on all three
   commands; this item only makes layered honour `elk.direction`.
7. No `CHANGELOG.md` edit. The breaking text goes in the report; 37 (S30)
   assembles the changelog from the merged PR bodies.
8. Specs first:
   - Goldens: `chain3` `fields: %i[nodes graph]` `tier: :exact`;
     `direction_down` same, exact; `chain2`; `spacing_override` exact for nodes;
     `cycle3` `fields: %i[nodes graph]` `tier: :structural` — un-pend it, 12 left
     it pending for exactly this reason.
   - LEFT and UP: every node inside the graph bounds, and the layer order
     reversed against RIGHT / DOWN.
   - Value spec: `"elk.layered.spacing.nodeNodeBetweenLayers": 40` →
     `n2.x == n1.x + 30 + 40`; `Elkrb.layout(g, layer_spacing: 40)` gives the
     same, through the alias.
   - CLI, in its own `describe "S9"` section or `spec/elkrb/cli/direction_spec.rb`:
     `layout --direction DOWN` differs from the default run and echoes
     `"elk.direction":"DOWN"` in the output graph.

Do not touch: routing (16), hierarchy (14), crossing minimisation (31),
`CHANGELOG.md`.

## Done when

`bundle exec rake` green.

```sh
bundle exec exe/elkrb layout spec/fixtures/simple_graph.json
# n1 (12,12)  n2 (62,12)  n3 (112,12)  root 154x54
```

The four goldens in the table above pass at the tier listed, `cycle3` included,
with no `pending`.

Mandatory gates: thermo-nuclear, execution-diff, Codex, copilot-review. No
dependency-contract-check — the change is internal geometry.

The execution-diff's intended differences: **every layered corpus case changes**,
which is the whole point of the slice. Verify three of them by hand against the
formula in step 3 and put the arithmetic in the report. Non-layered cases
(`box`, `force`, `stress`, `random`, `fixed`, `mrtree`, `radial`, `disco`,
`rectpacking`, the two SPOrE cases) must be byte-identical — a diff there means
the spacing change leaked out of layered.

Report which goldens were promoted to `exact`, and the `## Breaking` text.

`## Breaking` (D6): layered's default direction is RIGHT, not DOWN, and its
default layer gap is 20, not 60. Every layered coordinate moves. Migration is
two keys on the root: `"elk.direction": "DOWN"` and
`"elk.layered.spacing.nodeNodeBetweenLayers": 60` reproduce the 1.x look.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
