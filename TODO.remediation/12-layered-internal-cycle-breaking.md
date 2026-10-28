# 12 — Layered: internal cycle breaking, all endpoints, hyperedges raise
Slice S8 · branch `fix/s8-layered-cycles`

Can start after 11 (S7 — `CycleBreaker` and `LayerAssigner` already take the
`NodeIndex` in their ctor and resolve endpoints through it; this item rewrites
what they do with it). The golden assertions need 03 (S0a), which owns
`golden_spec.rb` and `match_elkjs_golden`. The XD gate needs 02 (S0b), which
owns `corpus:dump` and the `cycle3` / `hyperedge` corpus cases. Blocks the
START of 13 (S9 — direction and spacing only make sense once layers are
assigned from the real edge set) and of 25 (S19 — the layer constraint is
honoured inside this item's rewritten assigner). Blocks the CLOSE of 33 (S26),
whose 4000-node layered budget is measured on a base that contains this item.
Medium (~250 lines). BREAKING: hyperedges raise, and `properties["reversed"]`
disappears from output.

## Facts

Measured on 11's head (3d91c5e) in
`~/.claude/pipeline/worktrees/elkrb/s7-node-index`, which is this item's base.

The cycle breaker permanently rewrites the user's edges and leaks a scratch key
(elk-compat-10; layered-3; tests-10):

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({id:"r",children:%w[a b c].map{|i|{id:i,width:10,height:10}},edges:[{id:"e1",sources:["a"],targets:["b"]},{id:"e2",sources:["b"],targets:["c"]},{id:"e3",sources:["c"],targets:["a"]}]},algorithm:"layered"); r.edges.each{|e| puts "#{e.id} #{e.sources}->#{e.targets} #{e.properties.inspect}"}'
# e1 ["a"]->["b"] nil
# e2 ["b"]->["c"] nil
# e3 ["a"]->["c"] {"reversed" => true}
```

`e3` went in as `c → a` and comes back as `a → c`. `CycleBreaker#reverse_edges`
(`cycle_breaker.rb:88-97`) does the swap and the stamp; nothing ever restores
either.

Hyperedges are laid out silently instead of rejected (layered-10). elkjs errors
on the same input — the committed golden `spec/fixtures/golden/expected/hyperedge.json`
is exactly `{"error": "java.lang.IllegalArgumentException: Passed edge is not 'simple'."}`.

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({id:"r",children:%w[a b c].map{|i|{id:i,width:10,height:10}},edges:[{id:"e",sources:["a"],targets:["b","c"]}]},algorithm:"layered"); p r.children.map{|n|[n.id,n.x,n.y]}'
# [["a", 12.0, 12.0], ["b", 12.0, 82.0], ["c", 42.0, 82.0]]
```

`Elkrb::UnsupportedConfigurationException` is declared in
`lib/elkrb/errors.rb:8` and has zero callers anywhere in `lib/` or `spec/`
(`grep -rn UnsupportedConfigurationException lib/ spec/` finds only the
definition, plus 03's golden block which already rescues it).

Both phases are recursive, and a 4000-node chain still dies (layered-11):

```sh
bundle exec ruby -relkrb -e 'k=4000; Elkrb.layout({id:"r",children:(0...k).map{|i|{id:"n#{i}",width:30,height:30}},edges:(0...k-1).map{|i|{id:"e#{i}",sources:["n#{i}"],targets:["n#{i+1}"]}}},algorithm:"layered")'
# stack level too deep (SystemStackError), from lutaml/model/comparable_model.rb:22
# k=3500 passes.
```

The trace names lutaml's `ComparableModel#eql?` because 11's endpoint checks
compare `Node` objects with `==` / `include?`, which is a structural, whole-
subtree comparison. It is both the stack cost and a per-comparison O(subtree)
cost.

`layered.rb:34` throws away what `break_cycles` returns, and `:37` builds
`LayerAssigner.new(graph, index)` with no reversal set — the two phases only
agree today because phase 1 mutated the edges in place. `layered.rb:41` also
hands `NodePlacer` the raw `@options` Hash; that is 13's problem, not this
item's.

`node.edges` is read two ways. `CycleBreaker#get_outgoing_edges`
(`cycle_breaker.rb:74-86`) concatenates a node's own `edges` as if they left
that node; `LayerAssigner#get_incoming_edges` (`layer_assigner.rb:93-112`) scans
them by their real targets (layered-13). In ELK JSON a node's `edges` are the
edges *contained* in that compound node, so both readings of them as this
level's edges are wrong.

03's `golden_spec.rb` already has the blocks this item un-pends: `cycle3`
(`tier: :structural`, pending "RC7: cycle breaker permanently reverses edges…"),
`hyperedge` (rescues `Elkrb::UnsupportedConfigurationException` and compares
against the recorded error, pending "RC7: layered silently mis-routes
hyperedges…") and `ports_simple` (`tier: :structural`). The `cycle3` golden
keeps `e3` as `["c"] → ["a"]` and puts the three nodes at x = 12 / 62 / 112.

## Do

1. `layered/cycle_breaker.rb`: `break_cycles` returns a `Set` of edge ids to
   treat as reversed. It never touches `edge.sources` / `edge.targets` and never
   writes `properties` — that is D5, ruled, because a laid-out graph must be the
   user's graph. Delete `reverse_edges`.
2. Make the DFS iterative with an explicit stack, from every node, over outgoing
   edges. An edge is outgoing from `n` when any resolved source endpoint is `n`,
   and it leads to every resolved target endpoint. Compare node **ids**, not
   `Node` objects — structural `==` is what the 4000-chain trace above dies in.
3. `node.edges` are not this level's edges. Ignore them in `CycleBreaker`;
   `LayerAssigner` already treats them as contained. That settles layered-13 in
   the direction ELK uses.
4. `layered/layer_assigner.rb`: ctor takes the index and the reversed set.
   Longest-path layering, iterative — explicit stack or a memoised topological
   order. A node's predecessors are the resolved sources of its non-reversed
   incoming edges, plus the resolved targets of its reversed ones. Self-loops
   stay skipped (01/S1). Drop 11's `@in_progress` warn-and-return-0 guard
   (`layer_assigner.rb:62-68`): step
   5 removes the only input that could reach it.
5. `layered.rb`: reuse the index 11 already builds, do not build a second one.
   Capture `reversed = cycle_breaker.break_cycles` and construct
   `LayerAssigner.new(graph, index, reversed)`. Before phase 1, raise
   `Elkrb::UnsupportedConfigurationException.new("layered does not support hyperedges (edge #{id})", option: "edge", value: id)`
   when any edge at this level has more than one source or more than one target.
   D5 and decision 10 ruled this: splitting a hyperedge internally is not
   semantics-preserving, and it is what ELK and elkjs do.
6. Specs first, in `spec/elkrb/layout/algorithms/layered_spec.rb`, from JSON:
   - `a→b→c→a` — after layout every edge's `sources`/`targets` equal the input,
     and `edge.properties` is nil or has no `"reversed"` key; the three nodes get
     three distinct layer coordinates.
   - `a→[b,c]` — `expect { Elkrb.layout(g) }.to raise_error(Elkrb::UnsupportedConfigurationException)`.
   - A 5000-node chain built in the spec lays out with no `SystemStackError`, in
     under 5 s.
7. Goldens: un-pend `hyperedge` (it asserts the recorded elkjs error and elkrb
   now raises too) and `ports_simple` if it passes. Leave `cycle3` pending here
   and assert the three distinct layer coordinates and the preserved directions
   directly instead — the structural tier also needs 13's RIGHT/20/20 spacing for
   layer grouping and graph size, and 16's border clipping for section endpoints.
   13 promotes it for nodes and graph; 16 for sections.
8. Corpus: flip the `hyperedge` case in 02's ledger. Add `"expect": "error"` to
   `spec/fixtures/corpus/hyperedge.json` so `corpus_runner`'s exit status keeps
   reflecting unexpected failures only, and record the raise as expected
   behaviour rather than a `KNOWN_FAILURES` row.

Do not touch: node placement, direction, spacing (13); crossing minimisation
(31).

## Done when

`bundle exec rake` is green (spec + rubocop; 04/S28 is merged by now).

The elk-compat-10 repro prints the input directions and no `properties`:

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({id:"r",children:%w[a b c].map{|i|{id:i,width:10,height:10}},edges:[{id:"e1",sources:["a"],targets:["b"]},{id:"e2",sources:["b"],targets:["c"]},{id:"e3",sources:["c"],targets:["a"]}]},algorithm:"layered"); r.edges.each{|e| puts "#{e.id} #{e.sources}->#{e.targets} #{e.properties.inspect}"}'
# e3 ["c"]->["a"] nil
```

The hyperedge repro raises `Elkrb::UnsupportedConfigurationException` naming the
edge id. The chain that ran out of stack now does not:

```sh
bundle exec ruby -relkrb -e 'k=5000; t=Time.now; Elkrb.layout({id:"r",children:(0...k).map{|i|{id:"n#{i}",width:30,height:30}},edges:(0...k-1).map{|i|{id:"e#{i}",sources:["n#{i}"],targets:["n#{i+1}"]}}},algorithm:"layered"); puts Time.now-t'
```

Report the largest chain length verified.

`spec/elkrb/golden_spec.rb`'s `hyperedge` block passes without `pending`.

Mandatory gates: thermo-nuclear, execution-diff, Codex, copilot-review. No
dependency-contract-check — nothing here crosses a boundary the repo does not
own.

The execution-diff's intended differences, against a base dump taken on the
branch's base ref — its merge-base with `v2`, or the `int/s8` stack base while
11 is unmerged:

- Cyclic corpus cases (`cycle3`, and any imported case with a back edge) keep
  their input edge directions in the output and lose `properties.reversed`.
  Their sections may move because the router now sees the original direction.
- `hyperedge` flips from laid-out output to an error record.
- Acyclic, non-hyperedge cases byte-identical.

Anything else in the diff is a bug.

`## Breaking` in the report, carried into the PR body (D5): layered raises
`Elkrb::UnsupportedConfigurationException` for an edge with more than one source
or target, matching ELK and elkjs. Edges keep the direction they went in with,
and `properties["reversed"]` is never written. A consumer that read that key to
find back edges has nothing to read — the reversal is internal now.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
