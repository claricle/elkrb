# 14 — Hierarchy: bottom-up sizing, per-level routing
Slice S10 · branch `fix/s10-hierarchy-bottom-up`

Can start after 09 (S5 — `@resolver`, which the rewritten processor uses to read
a compound's own `elk.algorithm` and padding), 10 (S6 — S6 edits
`hierarchical_processor.rb`'s `get_padding`, which this item deletes; landing
second means a merge conflict either way, so this item goes after), 11 (S7 —
`NodeIndex` is what "an endpoint not in this level" is decided against), 13 (S9
— the compound goldens are stated in S9's coordinates) and 07 (S3b — S3b
rewrites the four `LayoutOptions.new` sites in `hierarchical_processor_spec.rb`,
which this item rewrites wholesale). Goldens need 03 (S0a); the XD gate needs 02
(S0b). Blocks the START of 15 (S10b), 16 (S11), 17 (S12), 21 (S15) and 25 (S19).
Large (~300 lines, mostly deletions). BREAKING: the `hierarchical` option
becomes a no-op and declared compound sizes are recomputed.

## Facts

Measured on 11's head (3d91c5e) in
`~/.claude/pipeline/worktrees/elkrb/s7-node-index`. Line numbers are `v2`
(a008889); nothing before this item touches `hierarchical_processor.rb` except
10. `spec/fixtures/corpus/compound_unsized.json` is 02's (S0b) file and only
was added by 02 (S0b) at `e512617` and is in every later head of that branch, including `22231fd`, so the repro below feeds it in from there; on this
item's real base, where 02 is merged, the plain path works.

Hierarchical layout runs in the wrong order (pipeline-2; layered-6;
elk-compat-14; spore-libavoid-vertiflex-10). `layout_hierarchical` lays out the
parent level at `hierarchical_processor.rb:21` and only grows the compound at
`:30`. Run the `compound_unsized` corpus fixture:

```sh
git show 22231fd:spec/fixtures/corpus/compound_unsized.json > /tmp/compound_unsized.json
bundle exec ruby -relkrb -rjson -e 'g=JSON.parse(File.read("/tmp/compound_unsized.json"))["graph"]; r=Elkrb.layout(g); r.children.each{|n| puts "#{n.id} (#{n.x},#{n.y}) #{n.width}x#{n.height}"}; puts "root #{r.width}x#{r.height}"; p_=r.children[0]; p_.children.each{|c| puts "  #{c.id} (#{c.x},#{c.y})"}; puts "  inner sections #{p_.edges[0].sections.inspect}"'
# p (12.0,12.0) 54.0x144.0
# q (12.0,72.0) 30.0x30.0
# root 54.0x114.0
#   c1 (24.0,24.0)
#   c2 (24.0,114.0)
#   inner sections nil
```

Four separate defects in that one output:

- `p` spans y 12→156 and `q` spans y 72→102. `q` sits **inside** `p`. Siblings
  overlap because `p` was placed at its pre-layout size.
- Root is 54×114 while `p` alone reaches 156. The root bbox does not enclose its
  own children.
- `c1` is at (24,24). Padding is applied twice — once by `apply_padding` inside
  `layout_flat` (`base_algorithm.rb:140-155`) and again by
  `adjust_children_for_padding` (`hierarchical_processor.rb:150-157`).
- The edge inside `p` has no sections at all (pipeline-10).

The committed elkjs golden for the same graph
(`spec/fixtures/golden/expected/compound_chain.json`) is: `p` (12,12) 104×54
with `c1` (12,12) and `c2` (62,12); `q` (136,24); root 178×78.

Cross-level edges get no sections either (elk-compat-14). Root edge `c2 → q`,
where `c2` lives inside `p`:

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({"id"=>"root","children"=>[{"id"=>"p","width"=>1,"height"=>1,"children"=>[{"id"=>"c1","width"=>50,"height"=>30},{"id"=>"c2","width"=>50,"height"=>30}],"edges"=>[{"id"=>"pe","sources"=>["c1"],"targets"=>["c2"]}]},{"id"=>"q","width"=>60,"height"=>40}],"edges"=>[{"id"=>"e2","sources"=>["c2"],"targets"=>["q"]}]}); p_=r.children[0]; puts "root #{r.width}x#{r.height}; p right edge #{p_.x+p_.width}; pe #{p_.edges[0].sections.inspect}; e2 #{r.edges[0].sections.inspect}"'
# root 105.0x64.0; p right edge 86.0; pe nil; e2 nil
```

An unsized compound produces a root that does not contain it at all:

```sh
bundle exec ruby -relkrb -e 'c=Elkrb::Graph::Node.new(id:"c",children:[Elkrb::Graph::Node.new(id:"a",width:50,height:30)]); r=Elkrb.layout(Elkrb::Graph::Graph.new(id:"r",children:[c]),algorithm:"box"); puts "c #{c.width}x#{c.height} root #{r.width}x#{r.height}"'
# c 74.0x54.0 root 24.0x24.0
```

Per-compound options are threaded and then dropped (pipeline-17; layered-21).
`layout_children_recursively` passes `extract_node_options(node)`
(`hierarchical_processor.rb:73-77`) down to `layout_flat`, and all 15
`layout_flat` implementations name the parameter `_options` and read `@options`
instead. A compound's own `elk.algorithm` is never honoured.

Four pipeline steps walk past this level, which is what makes per-level anything
impossible today. All verified on `v2`:

| walk | where | effect |
|---|---|---|
| `LabelPlacer#place_hierarchical_labels` | called at `label_placer.rb:21`, defined `:308-323` | the root instance places every descendant's labels |
| `BaseConstraint#all_nodes` | `constraints/base_constraint.rb:64-68`, `graph.children.flat_map(&:all_nodes)` | alignment groups span levels and average coordinates from different frames (constraints-4) |
| `BaseConstraint#find_node` | `base_constraint.rb:50-58`, calls the recursive `Node#find_node` | a relative-position reference resolves to a descendant in another frame |
| `ConstraintProcessor#has_constraints?` / `#has_constraints_recursive?` | `constraint_processor.rb:113-119` and `:124-130` | descends into `node.children` |

`Force#collect_all_edges` (`force.rb:169-176` at 11's head, `:154-161` on `v2`)
and `Stress#collect_all_edges` (`stress.rb:171-178` / `:165-172`) both append
every child's `node.edges` — the next level's contained edges — to this level's
edge list.

Two steps are already this-level-only and must be left alone.
`EdgeRouter#route_edges` (`edge_router.rb:18-29` at 11's head) iterates
`graph.edges` and builds its index over `graph.children`.
`PortConstraintProcessor#apply_port_constraints` (`port_constraint_processor.rb:17-22`)
iterates `graph.children`.

`process_node_ports` returns early for a node without a positive width and
height (`port_constraint_processor.rb:31-32`). That is why order matters: an
unsized compound's own ports would never be processed if ports ran before
sizing (pipeline-7).

`hierarchical_processor.rb` is 299 lines on `v2`.

08's registry has an elkrb-private `hierarchical` boolean row (find it by key —
rows are one per line sorted by id). `base_algorithm.rb:50` reads it as
`option("hierarchical", false) || graph.hierarchical?`.

`Elkrb::AlgorithmNotFoundError` exists (`lib/elkrb/errors.rb:21`) and
`AlgorithmRegistry.get(name)` exists (`algorithm_registry.rb:16`).

## Do

1. **A compound node is a graph** (D7, ruled — this is the whole design; do not
   re-derive it). Rewrite `lib/elkrb/layout/hierarchical_processor.rb` to about
   40 lines. It provides one method:

   ```ruby
   def size_compound_children(graph)
     graph.children.each do |node|
       next unless node.hierarchical?

       child_graph = Elkrb::Graph::Graph.new(
         id: "#{node.id}_children", children: node.children,
         edges: node.edges, layout_options: node.layout_options,
       )
       pin   = @resolver.get("elk.algorithm", child_graph, default: nil)
       klass = pin ? (Layout::AlgorithmRegistry.get(pin) || raise(AlgorithmNotFoundError.new(pin))) : self.class
       klass.new(@options).layout(child_graph)
       node.width  = child_graph.width
       node.height = child_graph.height
     end
   end
   ```

   `Elkrb::Graph` is a module with no `.new`; the class is `Graph::Graph`, as
   `v2`'s `hierarchical_processor.rb:64` already writes it. The child instance
   runs the whole of `BaseAlgorithm#layout`, so recursion happens inside that
   call and deeper compounds are sized first. A nested `elk.algorithm` pin wins
   (decision 12); an absent pin uses the parent's class; an **invalid** pin
   raises `AlgorithmNotFoundError` — never a silent fallback.

2. Reorder `BaseAlgorithm#layout`:

   ```
   size_compound_children(graph) if graph.hierarchical?
   apply_port_constraints(graph)
   apply_pre_layout_constraints(graph)
   layout_flat(graph, @options) if graph.children
   enforce_post_layout_constraints(graph)
   apply_edge_routing(graph)
   place_labels(graph) unless option("label.placement.disabled", default: false)
   ```

   Sizing goes first because `process_node_ports` skips an unsized node, so an
   unsized compound's own ports would otherwise never be processed. Keep 01's
   nil-children dispatch guard (`if graph.children`) and its
   `base_algorithm_spec.rb` examples — an explicit `[]` must still reach
   `layout_flat`. Only the `option("hierarchical")` / `layout_hierarchical`
   branch goes.

3. No `with_current_graph`, no `@graph` reassignment. Each algorithm instance
   owns exactly one level and `@graph` is set once in `layout`.

4. Make every step this-level-only. Delete `LabelPlacer#place_hierarchical_labels`
   and its call at `label_placer.rb:21` — the child instance places its own
   labels. Change `BaseConstraint#all_nodes` to `graph.children`, which also
   removes constraints-4's cross-parent averaging (note it in the report; 25/S19
   builds on it). Make `BaseConstraint#find_node` search `graph.children` only.
   Make `ConstraintProcessor#has_constraints?` check `graph.children` only and
   delete `has_constraints_recursive?`. Restrict `Force#collect_all_edges` and
   `Stress#collect_all_edges` to `graph.edges`. After the rewrite, re-grep
   `node.children|all_nodes|all_edges|find_node` under `lib/elkrb/layout` and
   report any other walk.

5. Delete from `hierarchical_processor.rb`: `layout_hierarchical`,
   `layout_children_recursively`, `apply_parent_constraints`, `get_padding`,
   `parse_padding`, `default_padding` (padding comes from the resolver through
   `apply_padding` inside `layout_flat`), `adjust_children_for_padding`,
   `handle_cross_hierarchy_edges`, `find_node_in_hierarchy`, `crosses_hierarchy?`,
   `node_depth`, `adjust_edge_for_hierarchy`, `update_parent_bounds`,
   `calculate_children_bounds`, `extract_node_options`. `apply_child_layout`
   goes or stays on the dependency-contract-check result below.

6. Cross-hierarchy edges get no sections here — that is elkjs `SEPARATE_CHILDREN`
   behaviour and it is 15 (S10b) that adds the bounded `INCLUDE_CHILDREN` form.
   `route_edge` already returns early when an endpoint does not resolve; keep it
   that way, and make sure 16 does not create a section for them either.

7. Drop the `hierarchical` call option. Hierarchy is detected from the graph.
   Remove the row from 08's registry aliases and put the line in the report's
   `## Breaking` — no `CHANGELOG.md` edit.

8. Rewrite `spec/elkrb/layout/hierarchical_processor_spec.rb` from JSON, dropping
   the vacuous and double-padding examples.

9. Specs first, all from JSON:
   - `spec/fixtures/corpus/compound_unsized.json`'s graph → `p` 104×54 at
     (12,12), `q` at (136,24), root 178×78; golden `compound_chain`
     `fields: %i[nodes graph]` `tier: :exact`.
   - `c1` at (12,12) inside `p` — padding applied once.
   - `p.edges[0].sections.first` start and end inside `0..p.width` × `0..p.height`
     — the inner edge is routed in `p`'s frame.
   - A root edge `c1 → q` (second JSON) has `sections` nil or empty.
   - Per-node `"elk.padding":"[top=30,left=30,bottom=30,right=30]"` on `p` →
     `c1` at (30,30), `p` 140×90.
   - Golden `compound_nested` at `tier: :structural`.
   - Sibling compounds do not overlap (invariant).
   - `p` with a declared 10×10 is resized. Document it as ELK behaviour.
   - An unsized compound with two ports and one leaf child → after layout the
     compound has a computed size **and** its ports have x/y on its border.
   - A compound pinning `"elk.algorithm":"box"` inside a layered root is laid out
     by box (assert its children's box row positions) while the root stays
     layered. A compound pinning `"elk.algorithm":"nope"` raises
     `Elkrb::AlgorithmNotFoundError`.
   - Decision 5 boundary: in `compound_unsized`, `p` gets a computed size while
     an unsized **leaf** in the same graph still has no `width`/`height` in
     `to_json`. The `omit_size_for_unsized_input` invariant exempts nodes with
     children, so both hold together.
   - Hierarchy spec where a leaf id is reused at two levels (11 allows that) to
     prove contained edges no longer resolve against parent-level nodes.

Do not touch: border clipping and section ids (16); `INCLUDE_CHILDREN` (15);
20's `rng`, which sits directly below `option` in `base_algorithm.rb`;
`CHANGELOG.md`.

## Done when

`bundle exec rake` green.

The layered-6 and elk-compat-14 repros print correct sizes — `p` sized from its
children, `q` clear of it, the root enclosing both, and the inner edge carrying
a section. pipeline-2 was a crash repro and prints nothing; the specs in step 9
cover it.

```sh
bundle exec ruby -relkrb -rjson -e 'g=JSON.parse(File.read("spec/fixtures/corpus/compound_unsized.json"))["graph"]; r=Elkrb.layout(g); r.children.each{|n| puts "#{n.id} (#{n.x},#{n.y}) #{n.width}x#{n.height}"}; puts "root #{r.width}x#{r.height}"'
# p (12,12) 104x54   q (136,24) 30x30   root 178x78
```

Goldens `compound_chain` (exact, nodes + graph) and `compound_nested`
(structural) pass with no `pending`.

Mandatory gates: thermo-nuclear, **dependency-contract-check**, execution-diff,
Codex, copilot-review.

The dependency-contract-check question is one lutaml fact, and it decides step
5's last clause: does
`Elkrb::Graph::Graph.new(children: node.children).children[0].equal?(node.children[0])`?
Construct the real objects and answer it. If the child graph shares the `Node`
instances, `apply_child_layout` copies a node onto itself and is deleted. Put
the answer in the report — do not infer it from the lutaml docs.

The execution-diff's intended differences: every hierarchical corpus case changes
(`compound_unsized`, `compound_declared_size`, `elkjs_basic_hierarchical`,
`java_elk_hierarchical`, `java_elk_compound`, and any imported case with nested
children). Check two by hand. Flat corpus cases must be byte-identical — a diff
on a flat case means the `BaseAlgorithm#layout` reorder changed something it
should not have.

Report: lines deleted from `hierarchical_processor.rb` (299 today); the
dependency-contract-check answer; every hierarchical case and its new size; any
extra cross-level walk the re-grep found; the `## Breaking` text.

**Decision 5 revisit — a required, explicit report item.** With bottom-up sizing
in, state whether the rule still holds: leaf nodes without an input size omit
`width`/`height`, nodes with children always get a computed size (the
`omit_size_for_unsized_input` exemption). Say whether any corpus case argues for
changing it. If the answer moves ruling 5, the orchestrator amends the
`## Rulings` table in `00-overview.md` in the same PR.

`## Breaking` (D7): the `hierarchical` option is a no-op — hierarchy is detected
from the graph. A compound node's declared `width`/`height` are recomputed from
its children, as ELK does. A compound that pins its own `elk.algorithm` is laid
out by that algorithm; an unknown pin raises `Elkrb::AlgorithmNotFoundError`
instead of quietly using the parent's.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
