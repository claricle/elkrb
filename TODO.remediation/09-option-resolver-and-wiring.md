# 09 — Resolver, wiring, precedence, CLI flags
Slice S5 · branch `fix/s5-option-resolver`

Can start after 05 (S2 — it rewrites the same hunks in `cli.rb` at `:12-17`
and `:160-222`, `diagram_command.rb:68-104` and `batch_command.rb:43-63`, and
this item's CLI specs use S0b's subprocess runner that S2 already builds on),
06 (S3 — a resolver has nothing to read until `layoutOptions` survives
deserialization) and 08 (S4 — `Registry.canonical`/`coerce`/`default` are the
resolver's whole vocabulary, and `Registry.status`/`note` drive the warning
pass). The XD gate needs 02 (S0b's `corpus:dump`). Blocks the start of 10
(S6), 13 (S9), 14 (S10), 25 (S19), 28 (S22), 35 (S27b) and 36 (S29). Parallel
with 07 (S3b) and 11 (S7). Large (~320 lines). **BREAKING.**

## Facts

Measured against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`.

`LayoutEngine.layout` picks the algorithm from `options[:algorithm]` only and
hard-defaults to `"layered"` (`layout_engine.rb:75-94`, selection at `:80-82`),
contradicting its own docstring at `:48-51` which says the graph's
`elk.algorithm` is consulted second (spore-libavoid-vertiflex-11; tests-7;
gap1-12; data-model-16):

```sh
bundle exec ruby -relkrb -rjson -e '
j=%q({"id":"root","layoutOptions":{"elk.algorithm":"box"},"children":[{"id":"a","width":30,"height":30},{"id":"b","width":30,"height":30}],"edges":[{"id":"e","sources":["a"],"targets":["b"]}]})
pin  = Elkrb::Layout::LayoutEngine.layout(Elkrb::Graph::Graph.from_json(j), {}).children.map{|c|[c.id,c.x,c.y]}
none = Elkrb::Layout::LayoutEngine.layout(Elkrb::Graph::Graph.from_json(j.sub(%q(,"layoutOptions":{"elk.algorithm":"box"}),"")), {}).children.map{|c|[c.id,c.x,c.y]}
box  = Elkrb::Layout::LayoutEngine.layout(Elkrb::Graph::Graph.from_json(j), algorithm:"box").children.map{|c|[c.id,c.x,c.y]}
p({pin_ignored: pin == none, pin: pin, box: box})'
# {pin_ignored: true, pin: [["a",12.0,12.0],["b",12.0,102.0]], box: [["a",12.0,12.0],["b",62.0,12.0]]}
```

Layered reads spacing only under Symbol keys. `NodePlacer#initialize`
(`layered/node_placer.rb:12-18`) takes `options[:layer_spacing]` and
`options[:spacing_node_node]` straight off the constructor Hash; `layered.rb:38`
hands it `@options`. `BaseAlgorithm#node_spacing` (`:99-101`) reads
`"spacing_node_node"`. Neither reads an ELK id (elk-compat-5; layered-9;
pipeline-5; tree-family-12):

```sh
bundle exec ruby -relkrb -e 'g=->{ {id:"r",children:[{id:"a",width:100,height:60},{id:"b",width:100,height:60},{id:"c",width:100,height:60}],edges:[{id:"e1",sources:["a"],targets:["b"]},{id:"e2",sources:["a"],targets:["c"]}]} }; p Elkrb.layout(g.call, "elk.spacing.nodeNode"=>80).children.map{|n|[n.x,n.y]}; p Elkrb.layout(g.call, spacing_node_node: 80).children.map{|n|[n.x,n.y]}'
# [[12.0,12.0],[12.0,132.0],[132.0,132.0]]   <- ELK id: no effect
# [[12.0,12.0],[12.0,132.0],[192.0,132.0]]   <- private key: works
```

`elk.padding` as a String is never parsed. `BaseAlgorithm#padding`
(`:106-115`) accepts only a Hash under `"padding"` and merges it into a
Symbol-keyed default, so a String-keyed Hash silently loses (elk-compat-6;
force-family-16; data-model-20):

```sh
bundle exec ruby -relkrb -e 'g=->{ {id:"root",children:[{id:"a",width:10,height:10}]} }; p Elkrb.layout(g.call, "elk.padding"=>"[top=50,left=50,bottom=50,right=50]").width, Elkrb.layout(g.call, padding: {top:50,left:50,bottom:50,right:50}).width'
# 34.0    <- ELK string: ignored, 12px default
# 110.0   <- Symbol Hash: honoured
```

`Logger` is not defined after `require "elkrb"` — neither `v2` nor 08 requires
it:

```sh
bundle exec ruby -relkrb -e 'p defined?(Logger)'   # nil
```

The CLI declares `option :algorithm, type: :string, default: "layered"` three
times — `cli.rb:17` (`layout`), `:77` (`diagram`), `:143` (`batch`). With a
Thor default, an omitted flag is indistinguishable from an explicit
`--algorithm layered`, so a graph's own pin can never win.
`build_layout_options` (`cli.rb:179-198`) always seeds `{algorithm:
options[:algorithm]}`; `DiagramCommand#build_layout_options`
(`diagram_command.rb:95-104`) does the same with `direction` and
`edge_routing`. `BatchCommand#process_file` (`batch_command.rb:53-62`) merges
its own options and delegates to `DiagramCommand`.

`AlgorithmNotFoundError#initialize` (`errors.rb:22-28`) raises
`"Algorithm not found: #{name}"`. `layout_engine.rb:86` raises a plain
`Elkrb::Error` with `"Unknown layout algorithm: …"`, and
`spec/elkrb/layout_engine_spec.rb:135-141` asserts
`raise_error(Elkrb::Error, /Unknown layout algorithm/)`. Switching the raise
to `AlgorithmNotFoundError` without changing the message breaks that spec.

`ElktParser.parse` returns a plain Hash, not a `Graph::Graph`
(`elkt_parser.rb:10-22`): `{id: "root", layoutOptions: {}, children: [],
edges: []}` with **Symbol** top-level keys. `DiagramCommand#load_graph` hands
that back for `.elkt` input, and `BatchCommand` reaches it through
`DiagramCommand`.

Item 06 left two lines behind for this item to delete —
`graph.layout_options["edge_routing"]` in
`base_algorithm.rb#get_edge_routing_style` and in
`edge_router.rb#get_routing_style`, each carrying the comment
`# legacy snake_case key; S5's resolver takes over alias handling and deletes
this line`. The registry alias `edge_routing` on `elk.edgeRouting` replaces
them.

Corpus is 47 cases (02/S0b).

Consumer contract: sirena emits root `elk.spacing.nodeNode` (50, 75, and the
C4 boundary `"60"` as a String), `elk.padding` as a String on C4 boundaries,
and bare `algorithm`. All three start working here.

## Do

Design decision D3 and ruled decision 1. Precedence is settled — do not
re-decide it.

**Precedence, one rule everywhere:** element `layoutOptions` > element
`properties` > call-level options > registry default. Call-level options are
globals; element options win. No parent→child inheritance (verified: a root
`elk.direction` does not reach compound children in elkjs). A caller who wants
"edge then graph" names both: `get("elk.edgeRouting", edge, graph)`.

1. `lib/elkrb.rb`: add `require "logger"` with the other stdlib requires.
   Define `Elkrb.logger` / `Elkrb.logger=` (default
   `Logger.new($stderr, level: Logger::WARN)`) at the top of `module Elkrb`,
   before the algorithm registrations at `:97`. Item 25 (S19) reuses it and
   must never redefine it. Add
   `require_relative "elkrb/options/resolver"` directly after the registry
   require.
2. New `lib/elkrb/options/resolver.rb`, ~80 lines:

   ```ruby
   class Elkrb::Options::Resolver
     def initialize(call_options = {})  # normalise once: { canonical_id => raw }
                                        # unknown keys kept under their own name
     def get(key, *elements, default: :registry)
       id = Registry.canonical(key) || key.to_s
       elements.each do |el|
         v = lookup(el&.layout_options, id, key); return coerce(id, v) unless v.nil?
         v = lookup(el&.properties,     id, key); return coerce(id, v) unless v.nil?
       end
       v = @call.fetch(id) { @call[key.to_s] };   return coerce(id, v) unless v.nil?
       default == :registry ? Registry.default(id) : default
     end
   end
   ```

   `lookup(map, id, key)` is nil-safe and tries the id, every alias of the id,
   then the raw key — each through `map.key?(k)` / `fetch`, **never**
   `map[k] || …`. An explicit `false` is a value, not a miss
   (`vertiflex.balanceColumns` defaults to `true`; today's `get_option`
   helpers get this right with `value.nil?` and `||` would reintroduce the
   defect). Then the same lookup inside `map["properties"]` when that is a
   Hash — a deprecated source; comment it as such.
   `elements` is the caller's explicit chain, in the caller's order.
3. `Resolver#report_unhonoured(graph)`, called once per `LayoutEngine.layout`.
   Collect every canonical key present in any `layoutOptions` at any level of
   the graph whose registry status is not `:honoured`. Log **one** warning per
   key: `:accepted`/`:unsupported` →
   `"elkrb: option <id> is accepted but not honoured in this version"`;
   `:partial` → `"elkrb: option <id> is partially honoured: <Registry.note(id)>"`.
   Keys the registry does not know at all are logged once at DEBUG —
   `"elkrb: unknown option <key>: stored and echoed"` — and never at WARN.
   Per layout, not per process: the same graph laid out twice warns twice.
4. `base_algorithm.rb`: `initialize(options = {})` keeps `@options` and adds
   `@resolver = Options::Resolver.new(options)`. `layout(graph)` sets
   `@graph = graph` **once** — it is never reassigned anywhere.
   `option(key, default: :registry)` → `@resolver.get(key, @graph, default:
   default)`, the same keyword and the same meaning as `Resolver#get`
   (`:registry` = registry default, `nil` = return nil), so there is one
   convention. Expose `resolver` via `attr_reader` for the mixins.
5. Perform the mechanical `option(key, literal)` → `option(key, default:
   literal)` rename in **all 15 positional callers**, keys unchanged: 4 in
   `base_algorithm.rb` (`:50`, `:64`, `:100`, `:108` at a008889) and 11 in
   `force.rb` (3), `stress.rb` (2), `box.rb` (1), `random.rb` (1),
   `libavoid.rb` (4). Verify the count on the branch base before starting.
   This rename is XD-neutral — no corpus graph carries those keys. The
   canonical-id migration of those reads is item 10's, not this one's.
6. `node_spacing` → `option("elk.spacing.nodeNode").to_f`. `padding` →
   `Registry.coerce("elk.padding", option("elk.padding"))` returned as the
   `{top:, right:, bottom:, left:}` Hash its callers already expect.
   `get_edge_routing_style(graph)` → `(@resolver.get("elk.edgeRouting",
   graph) || "ORTHOGONAL")` upcased, mapping `"UNDEFINED"` to `"ORTHOGONAL"`
   (today's default). Delete the two legacy `["edge_routing"]` lines item 06
   left behind, in `base_algorithm.rb` and `edge_router.rb`.
7. `layered/node_placer.rb:12-18` + `layered.rb:38` — moved here from item 10
   deliberately. `NodePlacer`'s constructor takes `layer_spacing:` and
   `node_spacing:` keywords; `LayeredAlgorithm` passes
   `option("elk.layered.spacing.nodeNodeBetweenLayers")` (registry default
   stays **60.0**; ELK's 20.0 lands in item 13) and `node_spacing`. Defaults
   and placement are unchanged. This is what makes `--spacing`,
   `--layer-spacing` and `spacing_node_node:` reach layered through the root
   `layoutOptions`.
8. `lib/elkrb/layout/hierarchical_processor.rb`: **untouched.** Nested levels
   keep resolving against the root graph until item 14 (S10) — that is
   today's behaviour (the `options` argument to `layout_flat` is ignored
   everywhere), so there is no `@graph` swap and this item's execution-diff
   stays clean for hierarchical cases.
9. `layout_engine.rb:75-94`: build `resolver = Options::Resolver.new(options)`;
   `algorithm_name = resolver.get("elk.algorithm", graph)` — that reads the
   graph's `layoutOptions["elk.algorithm"]`, then `properties["algorithm"]`,
   then `options[:algorithm]`, then the registry default `layered`. An
   unknown name raises `AlgorithmNotFoundError`. Include `lib/elkrb/errors.rb`
   in this slice: change `AlgorithmNotFoundError#initialize` to
   `super("Unknown layout algorithm: #{algorithm_name}")` and strengthen
   `spec/elkrb/layout_engine_spec.rb:135-141` to
   `raise_error(Elkrb::AlgorithmNotFoundError, /Unknown layout algorithm: nonexistent/)`.
10. `lib/elkrb/cli.rb`: drop the `default: "layered"` from **all three**
    `option :algorithm` declarations (`:17`, `:77`, `:143`). Delete
    `build_layout_options`. Add `apply_flags_to_root(graph)` writing only the
    flags that were explicitly given onto `graph.layout_options` (creating the
    Hash when nil), through one table: `algorithm → "elk.algorithm"`,
    `spacing → "elk.spacing.nodeNode"`,
    `layer_spacing → "elk.layered.spacing.nodeNodeBetweenLayers"`, padding
    flags → `"elk.padding" => "[top=…,left=…,bottom=…,right=…]"` (only when
    any padding flag is given; missing sides 12),
    `direction → "elk.direction"`, `edge_routing → "elk.edgeRouting"`. Then
    call `LayoutEngine.layout(graph, {})`. `apply_flags_to_root` must accept
    both a `Graph::Graph` and the Symbol-keyed Hash `ElktParser.parse`
    returns — convert a Hash root with `Graph::Graph.from_hash` first.
    `verbose_output "Using algorithm: …"` reads the resolved name.
11. `lib/elkrb/commands/diagram_command.rb:95-104`: the same table.
    `--direction` and `--edge-routing` join it (decision 9) and are added as
    Thor declarations on `layout` and `batch` too, not just `diagram`. Item 13
    (S9) makes layered honour `elk.direction`; until then the key is stored
    and echoed. `batch` reaches the table through `DiagramCommand`, so
    `batch_command.rb` needs no edit beyond item 05's exit code.
12. Specs first. `spec/elkrb/options/resolver_spec.rb`, a truth table built
    from `Graph.from_json` / `Graph.from_hash` elements. For
    `elk.spacing.nodeNode`, source ∈ {element `layoutOptions` under the
    canonical id, under `spacing.nodeNode`, under
    `org.eclipse.elk.spacing.nodeNode`, under `spacing_node_node`; element
    `properties["spacing.nodeNode"]`; element
    `layoutOptions["properties"]["elk.spacing.nodeNode"]` (deprecated); call
    `"elk.spacing.nodeNode" => v`; call `spacing_node_node: v`; none} × value
    ∈ {40, `"40"`, 40.0} → always `40.0` as a Float, or the registry default
    20.0 for "none". Precedence rows: element layoutOptions 50 + element
    properties 60 + call 70 → 50; properties 60 + call 70 → 60; call 70 only
    → 70. `get("elk.edgeRouting", edge, graph)`: edge beats graph, graph beats
    call. Conflict row: one element carrying both
    `"elk.spacing.nodeNode" => 50` and `"spacing_node_node" => 70` → the
    canonical id wins (50) — that is exactly the state the CLI creates when it
    writes a canonical key onto a root that already carried an alias.
    `elk.padding` from `"[top=5,left=7,bottom=9,right=11]"`, `{top: 5}` and
    `7` → `ElkPadding` values. Unknown key with `default:` returns the
    default. **Boolean row** for `vertiflex.balanceColumns` (registry default
    `true`): element `false` → `false`; call `false` → `false`; element
    `false` + call `true` → `false`; absent → `true`.
13. `spec/elkrb/layout_engine_spec.rb`: a JSON graph pinning
    `"elk.algorithm":"box"` positions `b` at `(a.x + 10 + 20, a.y)`; the same
    graph with an `algorithm: "random"` kwarg still runs box (the pin wins);
    `spec/fixtures/elkjs_basic.json` (which carries `properties.algorithm`)
    with `{}` runs layered;
    `Elkrb.layout(simple_graph_json, algorithm: "box", spacing_node_node: 50)`
    differs from `Elkrb.layout(simple_graph_json, algorithm: "box")` — pass
    `algorithm: "box"` in **both** runs, because the fixture has no pin and
    `simple_graph.json` is a chain that `nodeNode` spacing cannot move;
    `algorithm: "nonexistent"` raises `Elkrb::AlgorithmNotFoundError`.
14. `spec/elkrb/cli_spec.rb`, in its own `describe "S5"` section or a new
    `spec/elkrb/cli/layout_flags_spec.rb`: `layout` of a file pinning
    `"elk.algorithm":"box"` without `--algorithm` produces box output; with
    `--algorithm random` produces random output and the output JSON's
    `layoutOptions["elk.algorithm"] == "random"`;
    `layout spec/fixtures/simple_graph.json --layer-spacing 50` changes
    coordinates (a chain, so `nodeNode` spacing cannot); `--spacing 50` on a
    fan-out fixture changes coordinates and is echoed as
    `"elk.spacing.nodeNode":50`; a graph with no pins still defaults to
    layered. Warning spec: a graph carrying `elk.hierarchyHandling:
    INCLUDE_CHILDREN` (partial) and `elk.spacing.edgeNode` (accepted) produces
    exactly two warnings of those two shapes, none for honoured keys, and an
    unknown `foo.bar` produces no WARN; laying the same graph out twice warns
    twice.

Do not touch: the remaining resolver migrations inside the algorithms, the
router and the label placer (item 10) — item 06's compatibility edits in those
files, the `default:` rename, the `NodePlacer`/`layered.rb` keyword-ctor
change and the `BaseAlgorithm` changes above are in scope; direction semantics
(item 13); `hierarchical_processor.rb` at all (item 14); `CHANGELOG.md`
(item 37).

## Done when

- `bundle exec rake` green (spec + rubocop; 04/S28 made that the bar).
- The three audit repros print the same result for the ELK id and the elkrb
  alias: pipeline-5, elk-compat-5 and elk-compat-7. elk-compat-5 is layered
  and passes here because the `NodePlacer` keyword-ctor migration is in this
  slice.
- `bundle exec exe/elkrb layout spec/fixtures/simple_graph.json --layer-spacing 50`
  differs in coordinates from the default run, and `--spacing 50` differs in
  the echoed `layoutOptions` (and in coordinates on a fan-out graph).
- `bundle exec ruby -relkrb -e 'p defined?(Logger)'` → `"constant"`.
- The two legacy `["edge_routing"]` lines item 06 left behind are gone —
  check by reading `base_algorithm.rb` and `edge_router.rb`, not by grepping
  for the comment.

Gates, in this order: `thermo-nuclear-review` → `dependency-contract-check`
(**mandatory**) → `execution-diff` (**mandatory**) → Codex (max reasoning,
read-only, verify-before-critique) → `copilot-review` last.

dependency-contract-check: construct the real Thor command and prove that with
no `default:` an absent flag is **absent from** `options`, not present-and-nil
— for `--algorithm` and for `--spacing`. Then run `ElkPadding.parse` against
the real strings this slice generates, including the partial-flag form where
missing sides fall back to 12.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s5` stack base while 05, 06 and 08 are unmerged — and again on the
branch, then `diff -r` the two dump dirs. The rake exit status is
informational; never chain on it.

INTENDED execution-diff differences, and nothing else:

- Corpus cases whose graph carries an ELK-named `algorithm`, `spacing`,
  `padding` or `edgeRouting` now honour it. List every one of them by name in
  the report, with the option that moved it.
- CLI outputs gain the explicitly given flags, echoed in `layoutOptions`.
- Every other case byte-identical. The `option(key, literal)` →
  `option(key, default: literal)` rename is XD-neutral.

Any other difference is a bug.

The report carries the truth-table output, the list of corpus cases whose
output changed with the option that caused it, and a `## Breaking` section (no
`CHANGELOG.md` edit): a graph's `elk.algorithm` pin now beats the `algorithm:`
kwarg and the `--algorithm` flag's old default; the Thor `--algorithm` default
is gone; ELK-named options on the graph are honoured where they were ignored.
Migration: pin on the graph to force an algorithm.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then Gate B
(Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.

## Files

`lib/elkrb/options/resolver.rb` (new), `lib/elkrb.rb`, `lib/elkrb/errors.rb`,
`lib/elkrb/layout/layout_engine.rb`,
`lib/elkrb/layout/algorithms/base_algorithm.rb`,
`lib/elkrb/layout/algorithms/layered/node_placer.rb`,
`lib/elkrb/layout/algorithms/layered.rb`, `lib/elkrb/layout/edge_router.rb`
(the one legacy line), `lib/elkrb/layout/algorithms/{force,stress,box,random,libavoid}.rb`
(the `default:` rename only), `lib/elkrb/cli.rb`,
`lib/elkrb/commands/diagram_command.rb`,
`spec/elkrb/options/resolver_spec.rb` (new), `spec/elkrb/layout_engine_spec.rb`,
`spec/elkrb/cli_spec.rb` or `spec/elkrb/cli/layout_flags_spec.rb` (new).
