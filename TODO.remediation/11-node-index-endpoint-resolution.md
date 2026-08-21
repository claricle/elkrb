# 11 — NodeIndex: endpoint resolution, duplicate ids, disco
Slice S7 · branch `fix/s7-node-index`

Status: done, branch `fix/s7-node-index` @ 3d91c5e, awaiting PR. Gate A and
Gate B both approved that SHA; the branch is not pushed yet because the plan
PR is still unapproved. The rest of this file is the record of what was built
and how it was verified.

Can start: closed. It needed 01 (S1, in `v2` — S1 added the mrtree visited set
and the layer-assigner self-loop skip this item rewrites) and 02 (S0b) for the
XD gate and the `duplicate_ids` corpus fixture. Blocks the START of 12 (S8 —
`CycleBreaker` and `LayerAssigner` take the index in the ctor), 07 (S3b), 10
(S6), 14 (S10), 16 (S11), 20 (S14), 23 (S17) and 24 (S18). Medium (~250 lines;
measured 16 files, +956/-155). BREAKING: a duplicate node or port id within one
level now raises.

## Facts

Measured on `v2` (a008889) in the worktree at `/private/tmp/elkrb-v2`, and on
the branch head 3d91c5e in `~/.claude/pipeline/worktrees/elkrb/s7-node-index`.

Edges whose endpoints are port ids were invisible to layering (layered-4;
elk-compat-9). The repo's own 29-node elkjs fixture came back as one row:

```sh
bundle exec ruby -relkrb -rjson -e 'r=Elkrb.layout(JSON.parse(File.read("spec/fixtures/elkjs_bug7_complex.json"))); puts "#{r.children.map(&:y).uniq.size} #{r.width}x#{r.height}"'
# v2:  1 6748.0x104.0
# 3d91c5e: 21 1470.0x2904.0
```

Disco compared `Node` objects to String ids, so every node was its own
component (tree-family-2):

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.from_hash({"id"=>"r","children"=>%w[a b c].map{|i|{"id"=>i,"width"=>10,"height"=>10}},"edges"=>[{"id"=>"e","sources"=>["a"],"targets"=>["b"]}]}); p Elkrb::Layout::Algorithms::Disco.new.send(:find_connected_components,g).size'
# v2: 3   3d91c5e: 2
```

mrtree matched `edge.sources`/`edge.targets` against `node.id` only, so a
port-referenced tree was a row of roots (tree-family-11):

```sh
bundle exec ruby -relkrb -e 'g=Elkrb.layout(Elkrb::Graph::Graph.from_hash({"id"=>"r","children"=>[{"id"=>"a","width"=>10,"height"=>10,"ports"=>[{"id"=>"pa"}]},{"id"=>"b","width"=>10,"height"=>10,"ports"=>[{"id"=>"pb"}]}],"edges"=>[{"id"=>"e","sources"=>["pa"],"targets"=>["pb"]}]}),algorithm:"mrtree"); p g.children.map{|n|[n.id,n.x,n.y]}'
# v2: a(12,12) b(42,12)     3d91c5e: a(12,12) b(12,92)
```

Duplicate node ids passed `validate` and then died on nil arithmetic
(gap3-3):

```sh
bundle exec ruby -relkrb -e 'Elkrb.layout({"id"=>"root","children"=>[{"id"=>"a","width"=>30,"height"=>30},{"id"=>"a","width"=>30,"height"=>30}],"edges"=>[]})'
# v2: NoMethodError: undefined method '-' for nil
# 3d91c5e: Elkrb::ValidationError: duplicate id: a
```

Force and stress resolved endpoints with `graph.children.index { |n| n.id == source_id }`
once per edge per iteration, which both dropped port ids and cost O(E·N·iterations)
(force-family-10; force-family-15).

Six duplicated lookups existed across the layout tree: `EdgeRouter#build_node_map`
and `#find_node_with_port`, `CycleBreaker`'s `@graph.find_node` walk,
`LayerAssigner`'s `@graph.find_node` walk, and the `children.index` scans in
`force.rb` and `stress.rb`.

## Do

1. New `lib/elkrb/layout/node_index.rb` — `NodeIndex.build(graph)` indexes one
   hierarchy level: `graph.children` by node id, plus each child's ports by port
   id, both pointing at the owning node. `#node(id)` returns the node or nil;
   `#endpoint_nodes(ids)` returns the resolved nodes, compacted. No memoisation
   — callers build one per `layout_flat` / `route_edges` call, O(N+P). Ids are
   only unique within a level, so an index is never shared across levels.
2. Raise `Elkrb::ValidationError, "duplicate id: #{id}"` when a node or port id
   repeats within the level (D4, ruled: a clear error beats nil arithmetic).
   A nil id raises `Elkrb::ValidationError, "node without id"` — without it the
   nil key silently collides with the next id-less node.
3. `edge_router.rb`: `route_edges` builds the index when the caller passes none;
   delete `build_node_map` and `find_node_with_port`. Keep the parameter name
   `node_map` — it is an index now, and renaming it churns four call sites S11
   rewrites anyway. `route_edge`, `route_spline_edge` and `route_self_loop` all
   go through `node_map.node(id)`.
4. `layered/cycle_breaker.rb` and `layered/layer_assigner.rb` take the index in
   the ctor. Replace `@graph.find_node(...)` and `edge.targets&.include?(node.id)`
   with index lookups on resolved endpoint nodes. Leave reversal semantics and
   the recursion alone — 12 (S8) owns those.
5. `layered.rb`: build the index once in `layout_flat` and pass it to both
   phases.
6. `mrtree.rb`: `find_root_nodes` and `find_children` resolve ids through the
   index. `disco.rb`: BFS over ids with the index; keep the private
   `find_connected_components(graph)` name and arity so the tree-family-2 repro
   still runs.
7. `force.rb` and `stress.rb`: index lookups instead of the per-edge
   `children.index` scan.
8. Specs first, from JSON/Hash input: `spec/elkrb/layout/node_index_spec.rb`
   (node ids resolve, port id resolves to owner, duplicate node id raises naming
   the id, duplicate port id likewise, distinct levels may reuse an id,
   end-to-end `duplicate_ids.json` raises `/duplicate id: a/`);
   `edge_router_spec.rb`'s `#route_edge` / `#route_spline_edge` contexts put
   node1/node2 into `graph.children` and build `node_map` with
   `NodeIndex.build(graph)`; `disco_spec.rb` (`a→b`, `c` isolated → 2
   components); `layered_spec.rb` (bug7 fixture → more than one distinct layer
   coordinate); `mrtree_spec.rb` (edge `p1 → b` where `p1` is a port of `a`
   puts `b` below `a`).

Do not touch: cycle-breaker reversal semantics, layering recursion, hyperedges
(12), hierarchy (14), `validate` (26).

## Done when

Recorded as done. `bundle exec rspec` on 3d91c5e: **653 examples, 0 failures**.

Acceptance, both run on 3d91c5e:

```sh
bundle exec ruby -relkrb -rjson -e 'r=Elkrb.layout(JSON.parse(File.read("spec/fixtures/elkjs_bug7_complex.json"))); p r.children.map(&:y).uniq.size'   # 21, was 1
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.from_hash({"id"=>"r","children"=>%w[a b c].map{|i|{"id"=>i,"width"=>10,"height"=>10}},"edges"=>[{"id"=>"e","sources"=>["a"],"targets"=>["b"]}]}); p Elkrb::Layout::Algorithms::Disco.new.send(:find_connected_components,g).size'   # 2, was 3
```

Gates that ran: thermo-nuclear, execution-diff, Codex, copilot-review. No
dependency-contract-check — the change is internal, it crosses no boundary the
repo does not own.

The execution-diff's intended differences were: corpus cases with port-id
endpoints (`port_id_edges`, `elkjs_bug7_complex`, and the layered/force/stress/
mrtree imported cases), every disco case, and `duplicate_ids` flipping from a
`NoMethodError` to `Elkrb::ValidationError`. Everything else byte-identical.

What the gates caught:

- Codex approved after 5 rounds.
- Gate A (multi-agent-review): 3 Medium + 6 Low, all fixed. The Mediums were
  self-reference bugs the index made reachable — a hyperedge whose first target
  is one of its own source's ports made `dfs` see the source's in-progress frame
  as a cycle and reverse the edge (`SystemStackError`, reproduced); a hyperedge
  `[a,b] → a` made `calculate_layer` recurse on `a` before memoisation; and disco
  accumulated each component edge twice, once per endpoint side. The fixes are
  `first_other_target` / `first_other_source` / `incoming_to?` in the two layered
  phases, plus computing a component's edges once from the finished node set.
- Gate B (Codex ultra on 3d91c5e): APPROVE. One Low recorded and not applied —
  the dedupe in `CycleBreaker#dfs` uses `Array#include?`, which is lutaml's
  structural `==` on `Edge`, not identity. It is correct here and 12 (S8)
  rewrites the file.

Carried into 12 (S8), which owns the follow-ups this slice deliberately did not
take:

- `LayerAssigner`'s `@in_progress` guard is partial groundwork. It warns and
  returns layer 0 for a cycle `CycleBreaker` could not see. S8 rejects
  hyperedges before phase 1, which removes the only way to reach it.
- Structural `==` on `Node`/`Edge` objects (`endpoint_nodes(...).include?(node)`,
  `find { |t| t != node }`) is O(subtree) per comparison and is what actually
  blows the stack first: a 4000-node chain raises `SystemStackError` inside
  `lutaml/model/comparable_model.rb:22`, reproduced at 3d91c5e; 3500 passes.
  S8's iterative rewrite compares ids.
- `EdgeRouter`'s `self_loop?` / `get_self_loop_index` still compare raw ids, so
  two loops on the same port share offset 0. That is 19 (S13b).

`## Breaking` text carried into the PR body (D4): a duplicate node or port id
within one hierarchy level raises `Elkrb::ValidationError` naming the id,
instead of producing nil arithmetic. Ids may still repeat across levels.
