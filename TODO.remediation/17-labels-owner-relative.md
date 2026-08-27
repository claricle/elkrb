# 17 — Labels owner-relative
Slice S12 · branch `fix/s12-labels-owner-relative`

Can start after 10 (S6 moves `label_placer.rb`'s option reads onto the
resolver — this item reads ELK placement keys through it), 14 (S10 deletes
`place_hierarchical_labels` and the `place_labels` call that feeds it, hunks
that abut this item's edits; S10 must be in the base, not merged afterwards)
and 07 (S3b rewrites the `LayoutOptions.new` sites in `label_placer_spec.rb`).
The golden assertions need 03 (S0a); the XD gate needs 02 (S0b). Blocks the
START of 30 (S24 README), which documents label placement, and contributes a
`## Breaking` section to 37 (S30's CHANGELOG). Blocks nothing else's start —
it runs in parallel with 16 (S11) and 18 (S13). Medium (~250 lines).
**BREAKING.**

## Facts

Verified against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`.

Node label coordinates are absolute; ELK's are owner-relative
(elk-compat-15; pipeline-8):

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({"id"=>"root","children"=>[{"id"=>"a","width"=>100,"height"=>60,"labels"=>[{"text"=>"A","width"=>50,"height"=>15}]}]}); n=r.children[0]; puts "node (#{n.x},#{n.y}) label (#{n.labels[0].x},#{n.labels[0].y})"'
# node (12.0,12.0) label (37.0,34.5)
```

elkjs emits (25.0, 22.5) for the same input — exactly the elkrb value
minus the node origin. Every `place_label_*` method adds `node.x`/`node.y`:
`place_label_center` (`label_placer.rb:135-138`),
`place_label_outside_node` (`:83-101`), `place_label_inside_top/bottom/
left/right` (`:103-133`). `place_port_label` does the same via
`port_x = node.x + (port.x || 0)` (`:154-155`).

Port labels are only placed when the node itself has labels (gap4-4;
pipeline-9). `place_node_labels` guards with
`next unless node.labels && !node.labels.empty?` (`label_placer.rb:39`)
and calls `place_port_labels(node)` inside that branch (`:45`):

```sh
bundle exec ruby -relkrb -e 'g=Elkrb.layout({id:"r",children:[{id:"n",width:100,height:60,ports:[{id:"p",x:100,y:30,width:8,height:8,labels:[{text:"P",width:10,height:10}]}]}]},algorithm:"box"); l=g.children[0].ports[0].labels[0]; p [l.x,l.y]'
# [nil, nil]
```

The label is never touched. (The audit recorded `[0.0, 0.0]` for the
`Label.new` path; through JSON/Hash the coordinates stay `nil`, because
lutaml deserialization overwrites `Label#initialize`'s defaults. Either
way, placement never ran.)

ELK placement keys are never read (gap4-5). `label_placement_option`
(`label_placer.rb:326-332`) reads only the elkrb-private
`element.layout_options.properties["node.label.placement"]` /
`["label.placement"]`; `elk.nodeLabels.placement`,
`elk.portLabels.placement` and `elk.edgeLabels.placement` appear nowhere
in `lib/`:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.new(children:[Elkrb::Graph::Node.new(id:"n",width:100,height:60,labels:[Elkrb::Graph::Label.new(text:"L",width:80,height:20)],layout_options:Elkrb::Graph::LayoutOptions.new(properties:{"elk.nodeLabels.placement"=>"OUTSIDE V_TOP H_CENTER"}))]); Elkrb.layout(g); l=g.children[0].labels[0]; p [l.x,l.y]'
# [22.0, 32.0]
```

(22,32) is the default inside-centre position for a node at (12,12) —
the OUTSIDE key had no effect. Even when a private key is read, the
parser is a first-match regex, so `INSIDE H_LEFT V_TOP` lands centred.

Edge-label placement is hard-coded. `place_edge_label_on_section` sets
`placement = "CENTER" # Could be configurable` (`label_placer.rb:240`),
so the HEAD and TAIL arms at `:248-253` are unreachable (gap4-9).

A zero-length section gives NaN label coordinates and breaks `to_json`
(gap4-10). `calculate_edge_center` divides by `lengths[i]`
(`label_placer.rb:282`) with no zero guard:

```sh
bundle exec ruby -relkrb -rjson -e 'g=Elkrb::Graph::Graph.new(children:%w[a b].map{|i|Elkrb::Graph::Node.new(id:i,x:0,y:0,width:30,height:30)},edges:[Elkrb::Graph::Edge.new(id:"e",sources:["a"],targets:["b"],labels:[Elkrb::Graph::Label.new(text:"L",width:20,height:10)])]); Elkrb.layout(g,algorithm:"fixed"); l=g.edges[0].labels[0]; p [l.x,l.y]; begin; g.to_json; rescue => e; puts "RAISED #{e.class}: #{e.message}"; end'
# [NaN, NaN]
# RAISED JSON::GeneratorError: NaN not allowed in JSON
```

Outside node labels and port labels can land at negative coordinates
outside the graph's reported width/height, because `apply_padding`
sizes the graph from node rectangles and `place_labels` runs afterwards
(gap4-8, `base_algorithm.rb:119`).

The committed elkjs 0.11.0 goldens pin the target.
`spec/fixtures/golden/expected/labeled_node.json`: the 20×10 label on a
100×60 node at (12,12) sits at **(0,0)** — elkjs leaves an unplaced node
label alone. `spec/fixtures/golden/expected/labeled_node_placement.json`:
the same node with `"elk.nodeLabels.placement": "[H_CENTER,V_CENTER,INSIDE]"`
puts the label at **(40,25)** — owner-relative, `((100-20)/2, (60-10)/2)`.
Both goldens are `pending` in `spec/elkrb/golden_spec.rb` today ("RC8:
node labels are absolute, not owner-relative" and "RC8: ELK node label
placement keys are never read").

Consumer contract: sirena's transforms emit `labels: [{text:, width:,
height:}]` on nodes and edges, so every sirena diagram's label
coordinates move when this lands.

## Facts about frames (settled, do not re-derive)

Verified on elkjs 0.11.0: node labels stay at (0,0) unless
`elk.nodeLabels.placement` is set, while port and edge labels **are**
placed by default. A root-level `elk.nodeLabels.placement` does not
reach child nodes — only call-level globals do, and the resolver
(item 09 / S5) already handles globals.

## Do

Everything below is settled (design decision D9) — do not re-decide.

1. Node labels become node-relative: drop every `node.x` / `node.y` term
   in `place_label_center`, `place_label_outside_node` and the four
   `place_label_inside_*` methods.
2. If `get("elk.nodeLabels.placement", node)` is nil or empty, do not
   move the label at all — elkjs leaves it at (0,0). The resolution
   chain is the node only; globals are the resolver's job.
3. Parse a placement value as a token SET, not a first-match regex.
   Accept both `"[H_CENTER,V_CENTER,INSIDE]"` and
   `"INSIDE V_CENTER H_CENTER"`. Support INSIDE × {V_TOP, V_CENTER,
   V_BOTTOM} × {H_LEFT, H_CENTER, H_RIGHT} and OUTSIDE × the same
   (outside the node rectangle). Keep the existing `label.padding` and
   `label.margin` reads (`label_placer.rb:334-346`).
4. Port labels become port-relative and are placed by default:
   `elk.portLabels.placement` defaults to OUTSIDE (beside the port, away
   from the node); INSIDE puts them inside the node next to the port.
   Move `place_port_labels(node)` out of the `next unless node.labels`
   guard at `label_placer.rb:39-45` so a node with ports and no labels
   of its own still gets its port labels placed.
5. Edge labels stay in the edge container's frame — the same frame as
   the sections — and are placed by default at CENTER. Read
   `elk.edgeLabels.placement` (CENTER | HEAD | TAIL) from the label's own
   `layout_options`, falling back to the edge, which makes the HEAD/TAIL
   arms at `label_placer.rb:248-253` live.
6. Guard every division in `calculate_edge_center`: a zero-length
   segment contributes ratio 0.0, and `total_length.zero?` returns the
   start point. No NaN, no Infinity — the `have_finite_coordinates`
   invariant from item 03 must hold.
7. Rewrite the absolute expectations in
   `spec/elkrb/layout/label_placer_spec.rb` (`:44-45`, `:170-171`, and
   any sibling that asserts an absolute coordinate) as owner-relative
   values. Replace them; never delete an assertion without one. The same
   file carries vacuous assertions this item touches and must therefore
   fix: `:122` (`expect(label.x).to be < 50`, satisfied by a label that
   was never placed — gap4-16), `:92`, `:196-197`, `:371`, `:389` and
   `:423-424` (`not_to be_nil`). Give each a concrete expected value.
8. Add the invariant `have_labels_inside_owner` as its own file
   `spec/support/invariants/have_labels_inside_owner.rb`, ending with
   `INVARIANTS << :have_labels_inside_owner`. It applies to INSIDE
   placements. Never edit `corpus_spec`'s list.
9. Write the failing specs first: golden `labeled_node` with
   `fields: %i[labels]` at `tier: :exact` (label stays at (0,0)); golden
   `labeled_node_placement` exact ((40,25)); the string form
   `"INSIDE V_TOP H_LEFT"` gives (pad, pad); a port with a label on a
   node with no labels gets x/y; a zero-length edge label is finite and
   `to_json` succeeds.

Do not touch: label size estimation, port positions (item 18 owns them),
`CHANGELOG.md`.

## Done when

- `bundle exec rake` is green.
- The pipeline-8 repro with the label read appended prints `[0, 0]` —
  node-relative and untouched, because the input sets no placement key:
  `bundle exec ruby -relkrb -e 'Elkrb.layout({id:"r",children:[{id:"n1",width:100,height:60,labels:[{text:"N1"}]}]},algorithm:"box").children[0].labels[0].then { |l| p [l.x, l.y] }'`
- `bundle exec rspec spec/elkrb/golden_spec.rb -e labeled_node -e labeled_node_placement`
  passes with both `pending` markers removed — the goldens assert (0,0)
  and (40,25).
- The gap4-10 repro no longer produces NaN, and `g.to_json` returns
  instead of raising `JSON::GeneratorError`.
- `spec/support/invariants/have_labels_inside_owner.rb` exists and
  self-registers.

Mandatory gates, in order: `thermo-nuclear-review` → `execution-diff` →
Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. No dependency-contract-check: nothing here crosses
a boundary we do not own — say so in the report.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref and on the branch, then `diff -r`.
The exit status is informational; never chain on it.

INTENDED execution-diff differences, and nothing else:

- Every node label's `x`/`y` drops the owner's origin, so labelled cases
  change by exactly the node position.
- Node labels with no placement key stop being centred and stay at (0,0).
- Port labels on nodes without their own labels gain coordinates where
  they previously had none.
- Edge labels on zero-length sections become finite instead of NaN, so
  cases that crashed `to_json` now dump.
- **Node, port, edge and section coordinates are byte-identical.** Only
  `labels[].x` / `labels[].y` move.

Any other difference is a bug.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit):
label coordinates flip to owner-relative; default node labels stop being
centred. Migration lines: add the owner's x/y when drawing; set
`"elk.nodeLabels.placement": "[H_CENTER,V_CENTER,INSIDE]"` to keep
centred labels.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
