# 18 — Ports
Slice S13 · branch `fix/s13-ports`

Can start after 10 (S6 gives `PortConstraintProcessor` and `EdgeRouter`
their resolver reads) and 16 (S11 owns the section reset, the ids and
`clip_to_border`; this item changes where a ported edge anchors, which
only makes sense on top of that). The golden `ports_simple` needs 03
(S0a); the XD gate needs 02 (S0b). Blocks the start of 19 (S13b
self-loops), which needs a resolved port anchor before it can tell a
port-to-port loop from an ordinary edge. Runs in parallel with 17 (S12)
— item 17 owns port LABEL placement, this item owns port POSITION; they
must not touch each other's code. Medium (~300 lines). Output shape
changes, so the report carries a `## Breaking` section.

## Facts

Verified against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`.

`elk.portConstraints` is never consulted — every port is re-spaced
regardless (pipeline-7). `apply_port_constraints`
(`port_constraint_processor.rb:17-23`) calls `process_node_ports`
(`:30-46`) on every top-level child, which unconditionally runs
`detect_port_sides` → `group_ports_by_side` → `order_ports_on_side` →
`position_ports_on_boundaries`. Nothing reads a constraint value:

```sh
bundle exec ruby -relkrb -e 'n=Elkrb::Graph::Node.new(id:"n",width:100,height:60,ports:[Elkrb::Graph::Port.new(id:"p",x:100,y:10)]); n.layout_options=Elkrb::Graph::LayoutOptions.new("elk.portConstraints"=>"FIXED_POS"); Elkrb.layout(Elkrb::Graph::Graph.new(id:"r",children:[n]),algorithm:"box","elk.portConstraints"=>"FIXED_POS"); p n.ports.map{|q|[q.x,q.y,q.side]}'
# [[100.0, 30.0, "EAST"]]
```

The port was given y=10 and FIXED_POS on both the node and the call; it
moved to y=30.

Nested nodes' ports are never processed. `apply_port_constraints`
iterates `graph.children` only (`port_constraint_processor.rb:20`) and
never recurses into `node.children`.

elkjs's port option keys are ignored (elk-compat-8; data-model-10). Only
the elkrb-private top-level `side` attribute works:

```sh
bundle exec ruby -relkrb -e 'h={"id"=>"root","children"=>[{"id"=>"a","width"=>100,"height"=>50,"ports"=>[{"id"=>"p1","width"=>10,"height"=>10,"layoutOptions"=>{"elk.port.side"=>"SOUTH"}},{"id"=>"p2","width"=>10,"height"=>10,"properties"=>{"port.side"=>"SOUTH"}},{"id"=>"p3","width"=>10,"height"=>10,"side"=>"SOUTH"}]}]}; Elkrb.layout(h).children[0].ports.each{|p| puts [p.id,p.x,p.y,p.side].inspect}'
# ["p1", nil, nil, "UNDEFINED"]
# ["p2", nil, nil, "UNDEFINED"]
# ["p3", 50.0, 50.0, "SOUTH"]
```

The shipped fixture uses `properties: {"port.side": …}`, so all 33 of its
top-level ports stay UNDEFINED with nil coordinates after layout:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.from_json(File.read("spec/fixtures/elkjs_bug7_complex.json")); Elkrb.layout(g); ps=g.children.flat_map{|n| n.ports||[]}; puts "ports=#{ps.size} undefined=#{ps.count{|p| p.side == %q(UNDEFINED)}} nil_x=#{ps.count{|p| p.x.nil?}}"'
# ports=33 undefined=33 nil_x=33
```

`Port#side=` drops the side from output (data-model-4). The hand-written
setter at `port.rb:64-71` assigns `@side` directly and never calls
lutaml's `value_set_for(:side)`, and because `:side` has a `default:`
lambda (`port.rb:16`) lutaml treats it as still-default and omits it:

```sh
bundle exec ruby -relkrb -e 'p Elkrb::Graph::Port.from_json(%q({"id":"p","side":"WEST"})).to_json'
# "{\"id\":\"p\",\"index\":-1,\"offset\":0.0}"
```

The side vanished and two elkrb-only keys appeared. That is
`index`'s and `offset`'s `default:` lambdas at `port.rb:17-18` firing on
the deserialization path — elkjs never emits either key. Note the
`Port.new` path already behaves:
`Elkrb::Graph::Port.new(id: "p").to_json` → `{"id":"p"}`. Only
`from_json`/`from_hash` materialise the defaults, which is why the
regression must be pinned on the deserialization path.

The golden pins the elkjs anchor, and it is NOT the port centre.
`spec/fixtures/golden/expected/ports_simple.json`: node `a` at (12,12)
30×30, port `p1` at local (30,12) sized 6×6, and the section is
`e1_s0` **(48,27)** → (68,27) with `incomingShape "p1"`. 48 =
`node.x + port.x + port.width` (the port's outer border), 27 =
`node.y + port.y + port.height/2` (the port's centre on the cross axis).
The port centre would be (45,27).

Corpus ledger rows this item is expected to clear:
`spec/cross_validation/corpus_spec.rb` lists
`["port_id_edges", "invariants"] => "RC8"` and
`["elkjs_bug7_complex", "invariants"] => "RC8"`.

Consumer contract: no sirena transform emits ports today, so this item
changes nothing sirena sees. It is required for the ELK/elkjs
round-trip promise and for anything that feeds elkrb real ELK JSON.

## Ruled: the anchor is the port BORDER, not the centre

An earlier design for this slice put the section endpoint at the port
centre (`node.x + port.x + port.width/2`). The committed elkjs 0.11.0
golden above disproves it: elkjs anchors at the port's outer border on
the port's side, centred on the cross axis. **elkjs wins.** Implement
the border anchor and say so in the `## Breaking` section. Do not
implement the centre and then "reconcile later".

## Do

1. `lib/elkrb/layout/port_constraint_processor.rb`: read
   `constraint = get("elk.portConstraints", node)` per node — the
   registry alias `portConstraints` covers the bare form, and the
   resolver already reads `properties` because
   `spec/fixtures/elkjs_bug7_complex.json` carries
   `properties.portConstraints`. Then branch:
   - `FIXED_POS` — keep x/y untouched; only detect and record the side.
   - `FIXED_SIDE` / `FIXED_ORDER` — keep the given side
     (`get("elk.port.side", port)`, alias `port.side`, else detect from
     position) and the given order (`elk.port.index`, alias
     `port.index`, else input order), then re-space along that side.
   - `UNDEFINED` / `FREE` — today's behaviour, unchanged.
2. Recurse into `node.children` so nested nodes' ports are processed the
   same way. `apply_port_constraints` iterates `graph.children` only
   today (`:20`).
3. `lib/elkrb/graph/port.rb`: delete the custom `side=` at `:64-71` and
   let lutaml's generated setter run, so an assigned side serialises.
   Move the SIDES validation into a small `valid_side?` helper called by
   `detect_side`'s callers — it must not sit in the setter. Delete the
   three `default:` lambdas at `:16-18` (`side`, `index`, `offset`) so a
   port that never had them emits nothing; read sites become
   `port.side || "UNDEFINED"` and `port.index || -1`.
4. `lib/elkrb/layout/edge_router.rb`: `get_port_position`
   (`:151-165`) returns the port ORIGIN today
   (`node.x + port.x`, `node.y + port.y`). Change it to the elkjs
   anchor — the port's outer border along its side, centred on the
   cross axis — per the ruling above. Update the `ports_simple`
   expectations to the golden's values.
5. Set `incoming_shape` / `outgoing_shape` to the PORT id when the edge
   named a port (item 16 wrote the node id as given; a ported edge names
   the port, so this follows for free — assert it).
6. Drop the port exclusion from
   `spec/support/invariants/have_edges_on_node_borders.rb` (item 16's
   file), which was written to skip ported edges until this item lands.
7. Write the failing specs first: `Elkrb.layout(bug7)` gives every port
   an x and a y; ports carrying `properties["port.side"] == "NORTH"`
   sit on the node's top edge (assert the concrete convention the code
   uses, not a range); `FIXED_POS` keeps (100,10);
   `Port.from_json('{"id":"p","side":"WEST"}').to_json` contains
   `"side":"WEST"`; `JSON.parse(Port.from_json('{"id":"p"}').to_json) ==
   {"id" => "p"}` — no `index`, no `offset`; golden `ports_simple` at
   `tier: :structural`.

Do not touch: self-loops (item 19), port LABEL placement (item 17 owns
it), `CHANGELOG.md`.

## Done when

- `bundle exec rake` is green.
- The elk-compat-8 repro above prints a real side and real coordinates
  for `p1` and `p2`, not `UNDEFINED`/nil.
- `bundle exec ruby -relkrb -e 'p Elkrb::Graph::Port.from_json(%q({"id":"p","side":"WEST"})).to_json'`
  prints `{"id":"p","side":"WEST"}` — the side survives, `index` and
  `offset` are gone.
- `bundle exec rspec spec/elkrb/golden_spec.rb -e ports_simple` passes at
  `tier: :structural` with its `pending` marker removed.
- `spec/cross_validation/corpus_spec.rb`'s `["port_id_edges",
  "invariants"]` and `["elkjs_bug7_complex", "invariants"]` rows are
  removed from `KNOWN_FAILURES` and the guard example still passes.

Mandatory gates, in order: `thermo-nuclear-review` →
`dependency-contract-check` → `execution-diff` → Codex (max reasoning,
read-only, verify-before-critique) → `copilot-review` last.

The dependency-contract-check is mandatory because step 3 changes how
elkrb uses lutaml-model 0.8.19: construct a real `Port` and run the
truth table over {attribute with a `default:` lambda, attribute with
none} × {`.new`, `from_json`, `from_hash`, `from_yaml`, assignment
through the generated setter, assignment through a custom setter} ×
{`to_json`, `to_yaml`, `to_hash`} — and check `value_set_for` /
`value_set_for?` behaviour directly rather than from memory. The
question it must answer: does an attribute with no default get omitted
on every path, and does assignment through the generated setter mark it
set?

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref and on the branch, then `diff -r`.
The exit status is informational; never chain on it.

INTENDED execution-diff differences, and nothing else:

- Ports stop emitting `index: -1` and `offset: 0.0`; ports never given a
  side stop emitting `side: "UNDEFINED"`.
- A side that came from `from_json` or from side detection now appears
  in output, where it was dropped before.
- Port-carrying cases (`port_id_edges`, `elkjs_bug7_complex`,
  `java_elk_ports`) gain port coordinates and sides, and their edge
  sections move from the port origin to the port's outer border.
- Nested nodes' ports gain coordinates and sides for the first time.
- Cases with FIXED_POS keep their declared port coordinates instead of
  being re-spaced.
- **Every case with no ports is byte-identical.**

Any other difference is a bug.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit):
ports no longer emit `index: -1` / `offset: 0.0` / `side: "UNDEFINED"`
unless set; a ported edge's endpoint moves from the port origin to the
port's outer border; FIXED_POS ports stop moving. Include the before /
after port JSON for `spec/fixtures/elkjs_bug7_complex.json` in the
report, and the correction to the centre-anchor design ruled out above.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
