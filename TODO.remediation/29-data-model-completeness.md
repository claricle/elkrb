# 29 — Data-model completeness
Slice S23 · branch `fix/s23-data-model`

Can start after 06 (S3) — S3 renames every `json do` block to
`key_value do` and swaps `attribute :layout_options, LayoutOptions` for
`:hash` in the same five model files this item extends, so starting
earlier means writing the new mappings twice. Blocks the START of 37
(S30), which documents the model this item completes. Medium (~250 lines).
Not BREAKING — every change here is additive on read or fixes a method
that always raised.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree. Slice 1
touched `graph/graph.rb` and `graph/layout_options.rb` only, so the other
model files still carry their 6ac367c line numbers.

`junctionPoints`, `container` and `incomingSections`/`outgoingSections`
are not modelled (data-model-11). `Edge` (`graph/edge.rb:65`) declares
`id`, `sources`, `targets`, `labels`, `sections`, `layout_options`,
`properties` (`:66-72`) and nothing else; `EdgeSection` (`:9`) declares
`id`, `start_point`, `end_point`, `bend_points`, `incoming_shape`,
`outgoing_shape` (`:10-15`):

```sh
bundle exec ruby -relkrb -e 'puts Elkrb::Graph::Edge.from_json(%q({"id":"e","sources":["a"],"targets":["b"],"junctionPoints":[{"x":1,"y":1}],"container":"root"})).to_json'
# {"id":"e","sources":["a"],"targets":["b"]}
```

`Label` (`graph/label.rb:7`) has no `properties` attribute (`:8-14`), so
the elkjs key that `spec/fixtures/elkjs_bug7_complex.json` uses is
dropped on labels.

elkjs primitive edges are silently dropped (elk-compat-17). Only
`sources`/`targets` are mapped, so `source`/`target`/`sourcePort`/
`targetPort` produce an edge with no endpoints and no sections:

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({"id"=>"root","children"=>[{"id"=>"a","width"=>10,"height"=>10},{"id"=>"b","width"=>10,"height"=>10}],"edges"=>[{"id"=>"e","source"=>"a","target"=>"b"}]}); puts r.to_json'
# {…,"edges":[{"id":"e"}]}
```

`Rectangle#position` and `#center` always raise (data-model-15). Both
call `Point.new(@x, @y)` positionally (`geometry/rectangle.rb:19` and
`:53`) while `Point#initialize` is `(**attributes)`
(`geometry/point.rb:21`). `Rectangle` is what
`BaseAlgorithm#calculate_bounding_box` returns:

```sh
bundle exec ruby -relkrb -e 'p Elkrb::Geometry::Rectangle.new(1,2,3,4).center'
# geometry/point.rb:21:in 'initialize': wrong number of arguments (given 2, expected 0) (ArgumentError)
```

`Bezier.calculate_curve` raises for `segments == 1` (data-model-21):
`t = i.to_f / (segments - 1)` at `geometry/bezier.rb:25` is `0/0`, and
the clamp then compares Float with NaN. `segments == 0` returns `[]`.

`Elkrb.layout` has no input type check (gap3-8). Anything that is not a
Hash or a Graph reaches the algorithm and dies deep inside:

```sh
bundle exec ruby -relkrb -e '[nil,"{}",[],42].each{|x| begin; Elkrb.layout(x); rescue => e; puts "#{x.inspect}: #{e.class}"; end}'
# nil: NoMethodError   "{}": NoMethodError   []: NoMethodError   42: NoMethodError
```

`Elkrb.layout` mutates its Graph argument and returns the same object
(gap3-17). `lib/elkrb.rb:285-287` delegates to
`Layout::LayoutEngine.layout`, which writes x/y/width/height/sections
onto the passed graph and returns it (`layout_engine.rb:75-94`); a Hash
argument is converted to a fresh Graph and left untouched. The YARD
`@return` at `lib/elkrb.rb:268` hints at it; nothing states it.

`NodeConstraints` maps YAML in camelCase while every other model maps it
in snake_case (constraints-6; data-model-13). Its `yaml do` block is at
`graph/node_constraints.rb:81-89` (`fixedPosition`, `alignGroup`, …):

```sh
bundle exec ruby -relkrb -e 'p Elkrb::Graph::Graph.from_yaml("id: r\nchildren:\n- id: a\n  width: 1\n  height: 1\n  constraints:\n    fixed_position: true\n").children[0].constraints.fixed_position'
# false
```

No spec round-trips any model (data-model-22). Five calls to
`Graph.from_json`/`from_yaml` sit outside the command specs —
`spec/elkrb/graph/layout_options_spec.rb:39`, `:47`, `:63`, `:74` and
`spec/elkrb/layout/label_placer_spec.rb:395` — and every one of them
asserts only `not_to raise_error`. No spec anywhere compares a
parse-then-serialize result to its source, which is why every loss above
passes the suite.

gap4-13 (duplicate `edgeRouting` / `spline.*` JSON mappings on
`LayoutOptions`) is NOT this item's: item 06 deletes the whole typed
mapping, so there is nothing left to de-duplicate. Confirm it is gone
rather than re-fixing it.

## Do

Everything below is settled — do not re-decide.

1. `graph/edge.rb`: accept the legacy elkjs keys `source`, `target`,
   `sourcePort`, `targetPort` on READ and normalise them into
   `sources`/`targets`. Write only `sources`/`targets` — one output
   vocabulary. Put the read mapping in the `key_value do` block item 06
   renamed.
2. `graph/edge.rb`: add `junction_points` (a `Geometry::Point`
   collection) and `container` (`:string`) to `Edge`; add
   `incoming_sections` and `outgoing_sections` (string collections) to
   `EdgeSection`. Map each in both the `key_value do` and the `yaml do`
   block.
3. `graph/label.rb`: add `properties` (`:hash`) to `Label`, mapped in
   both blocks.
4. `geometry/rectangle.rb`: `Point.new(x: …, y: …)` at `:19` and `:53`.
   Delete the unreachable positional branch in `Point#initialize`
   (`geometry/point.rb:21-30`) — it can only be hit by unknown keywords,
   where it silently yields (0,0). Add geometry specs; there are none for
   `Point`, `Rectangle`, `Vector` or `Dimension` today.
5. `geometry/bezier.rb`: guard `segments < 2` at `:25` — return
   `[start_point, end_point]` rather than raising, and spec both
   `segments == 0` and `segments == 1`.
6. `lib/elkrb.rb:285`: raise
   `ArgumentError, "graph must be a Hash or Elkrb::Graph::Graph, got #{graph.class}"`
   unless the argument is one of those two, and state in the YARD
   (`:258-284`) that a Graph argument is mutated in place and returned
   while a Hash argument is converted and left untouched. The guard goes
   in `Elkrb.layout`, not in `LayoutEngine.layout` — item 09 rewrites
   `layout_engine.rb:75-94` and the two hunks must stay apart. Record in
   the report that `Elkrb::Layout::LayoutEngine.layout` called directly is
   still unguarded, so item 09 can pick it up.
7. `graph/node_constraints.rb:81-89`: map snake_case YAML keys
   (`fixed_position`, `align_group`, `align_direction`, `relative_to`,
   `relative_offset`, `position_priority`) and keep the camelCase
   spellings as READ aliases, so existing YAML keeps working.
8. Write the specs first, from input strings: round-trip
   `JSON.parse(Graph.from_json(src).to_json) == JSON.parse(src)` for every
   `spec/fixtures/*.json` and for a synthetic elkjs graph carrying
   `layoutOptions`, ports, labels, sections, `junctionPoints`, `container`
   and `incomingSections`; a legacy `source`/`target` edge laying out with
   real sections; `Rectangle#center` and `#position` returning a `Point`;
   `Bezier.calculate_curve(…, 1)`; the four bad `Elkrb.layout` arguments
   raising `ArgumentError`; `fixed_position: true` in YAML arriving as
   `true`.

Do not touch: `LayoutOptions` and its mappings (item 06 owns them),
`layout_engine.rb` (item 09), the ELKT parser's `sourcePort`/`targetPort`
keys (item 27 deletes them at the source), `README.adoc` (item 30).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- Every repro in Facts is fixed, checked by running it:
  - the `Edge.from_json` command echoes `junctionPoints` and `container`;
  - the primitive-edge command returns an edge with `sources`, `targets`
    and a section;
  - `Rectangle.new(1,2,3,4).center` returns a `Point`;
  - `Bezier.calculate_curve(…, 1)` returns two points;
  - all four bad arguments raise `ArgumentError` naming the class;
  - the YAML command prints `true`.
- `grep -rn "edgeRouting" lib/elkrb/graph/` returns nothing — item 06's
  deletion of the typed mapping is confirmed, not re-done.
- The round-trip spec passes for every fixture in `spec/fixtures/`.

Mandatory gates, in order: `thermo-nuclear-review` →
`dependency-contract-check` → Codex (max reasoning, read-only,
verify-before-critique) → `copilot-review` last.

dependency-contract-check is mandatory and its subject is lutaml-model
0.8.19. Construct the real objects and run a truth table rather than
trusting the mapping DSL from memory:

- a legacy read alias — two `map` entries pointing at one attribute —
  and which one wins on read and on write;
- a `collection: true` attribute of `:string` versus of a model class,
  from JSON, from YAML and from Hash;
- an attribute that is nil on write: is the key omitted or emitted as
  `null`? The goldens compare `container`, so an emitted `null` would
  break them;
- camelCase and snake_case YAML aliases on one attribute.

Put the table in the PR report.

No execution-diff gate: this item changes no layout code. Say so
explicitly rather than skipping silently, and prove it by running
`bundle exec rake "corpus:dump[<dir>]"` (quote the brackets) on the base
ref and on the branch and confirming `diff -r` is empty — an unintended
difference here means a mapping change leaked into output.

The report carries no `## Breaking` section. Note instead that output
gains `junctionPoints`, `container`, `incomingSections`/`outgoingSections`
and label `properties` when the input carried them, and that legacy
`source`/`target` input is now rewritten to `sources`/`targets` on
output.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
