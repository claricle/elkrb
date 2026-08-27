# 25 — Constraints
Slice S19 · branch `fix/s19-constraints`

Can start after 09 (S5 defines `Elkrb.logger` — this item routes every
violation through it and must not redefine it), 12 (S8 rewrites
`LayerAssigner` to take the reversed-edge set and iterate; the layer
constraint is honoured inside that rewritten assigner, not the old one)
and 14 (S10 makes `BaseConstraint#all_nodes` / `#find_node` and
`ConstraintProcessor#has_constraints?` this-level-only, which is what
stops alignment averaging across parents). The XD gate needs 02 (S0b).
Blocks the START of 37 (S30) — this item's `## Breaking` section is part
of the CHANGELOG inventory 37 assembles, so 37 cannot begin until this one
is merged. Blocks nothing else; runs in parallel with 16–24. Medium
(~300 lines).

## Facts

Verified against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`.
None of the constraint files changed in slice 1, so these line numbers
are the same at `main` and at `v2`.

The layer constraint is a silent no-op (constraints-1; layered-12;
tests-6). `LayerConstraint#apply` writes
`node.properties["_constraint_layer"]` (`layer_constraint.rb:33`) and
`#validate` reads `node.properties["_assigned_layer"]`
(`:54`, `:57`). Nothing writes `_assigned_layer`, and
`lib/elkrb/layout/algorithms/layered/layer_assigner.rb` never mentions
either key:

```sh
bundle exec ruby -relkrb -e 'r=Elkrb.layout({id:"r",children:[{id:"a",width:10,height:10,constraints:{layer:2}},{id:"b",width:10,height:10,constraints:{layer:0}}],edges:[{id:"e",sources:["a"],targets:["b"]}]},algorithm:"layered"); r.children.each{|n| puts "#{n.id} y=#{n.y} props=#{n.properties.inspect}"}'
# a y=12.0 props={"_constraint_layer" => 2}
# b y=82.0 props={"_constraint_layer" => 0}
```

`a` is pinned to layer 2 and `b` to layer 0, and they come back in edge
order. The marker also leaks into output.

Scratch state is written into `properties`, which is serialised
(constraints-5; data-model-12). `FixedPositionConstraint#apply` writes
`_constraint_fixed`, `_constraint_original_x` and `_constraint_original_y`
(`fixed_position_constraint.rb:33-35`), and `restore_fixed_positions`
keys off `_constraint_fixed` alone (`:50`), never
`node.constraints.fixed_position`:

```sh
bundle exec ruby -relkrb -rjson -e 'g=Elkrb::Graph::Graph.new(id:"r"); a=Elkrb::Graph::Node.new(id:"a",width:100,height:60,x:500,y:100,constraints:Elkrb::Graph::NodeConstraints.new(fixed_position:true)); b=Elkrb::Graph::Node.new(id:"b",width:100,height:60); g.children=[a,b]; h=JSON.parse(Elkrb.layout(g,algorithm:"layered").to_json); p h["children"][0]["properties"]'
# {"_constraint_fixed" => true, "_constraint_original_x" => 500.0, "_constraint_original_y" => 100.0}
```

Feeding that output back in re-pins the node even after the user sets
`fixedPosition: false`.

Alignment stacks nodes on top of each other (constraints-4).
`align_horizontally` (`alignment_constraint.rb:106-113`) and
`align_vertically` (`:116-123`) overwrite the coordinate with the group
average and never re-space along the other axis:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.new(id:"r"); a=Elkrb::Graph::Node.new(id:"a",width:100,height:60); b,c=%w[b c].map{|i| Elkrb::Graph::Node.new(id:i,width:100,height:60,constraints:Elkrb::Graph::NodeConstraints.new(align_group:"g",align_direction:"vertical"))}; g.children=[a,b,c]; g.edges=[Elkrb::Graph::Edge.new(id:"e1",sources:["a"],targets:["b"]),Elkrb::Graph::Edge.new(id:"e2",sources:["a"],targets:["c"])]; Elkrb.layout(g,algorithm:"layered"); puts "b=(#{b.x},#{b.y}) c=(#{c.x},#{c.y})"'
# b=(72.0,132.0) c=(72.0,132.0)
```

Two siblings land at exactly the same point. The same methods average
`nodes.filter_map(&:y).sum / nodes.length.to_f` — nodes with nil
coordinates bias the average toward 0 and are then assigned it
(constraints-12).

Relative-position chains resolve in child order (constraints-7).
`RelativePositionConstraint#apply` (`relative_position_constraint.rb:29`)
sorts only by `position_priority` and walks `all_nodes` order:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.new(id:"r"); a=Elkrb::Graph::Node.new(id:"a",width:100,height:60); b=Elkrb::Graph::Node.new(id:"b",width:100,height:60,constraints:Elkrb::Graph::NodeConstraints.new(relative_to:"a",relative_offset:Elkrb::Graph::RelativeOffset.new(x:0,y:100))); c=Elkrb::Graph::Node.new(id:"c",width:100,height:60,constraints:Elkrb::Graph::NodeConstraints.new(relative_to:"b",relative_offset:Elkrb::Graph::RelativeOffset.new(x:0,y:100))); g.children=[a,c,b]; Elkrb.layout(g,algorithm:"box"); puts "a=(#{a.x},#{a.y}) b=(#{b.x},#{b.y}) c=(#{c.x},#{c.y})"'
# Layout constraint violation: Node 'c' relative position incorrect. Expected (12.0, 212.0), got (252.0, 112.0)
# a=(12.0,12.0) b=(12.0,112.0) c=(252.0,112.0)
```

`c` is listed before `b`, so it reads `b`'s pre-move position. The
violation is printed and the wrong layout is returned anyway.

Violations go through bare `Kernel#warn` and never affect exit status
(constraints-8). `base_algorithm.rb:207` does
`warn "Layout constraint violation: #{error}"` and
`relative_position_constraint.rb:95` warns a second time for the same
dangling reference:

```sh
printf '{"id":"root","children":[{"id":"a","width":100,"height":60},{"id":"b","width":100,"height":60,"constraints":{"relativeTo":"ghost","relativeOffset":{"x":10,"y":0}}}]}' > /tmp/rel.json
bundle exec exe/elkrb layout /tmp/rel.json --algorithm box >/dev/null; echo "exit=$?"
# Warning: Node 'b' references non-existent node 'ghost' for relative positioning
# Layout constraint violation: Node 'b' has relative_to constraint referencing 'ghost' which doesn't exist
# exit=0
```

`BaseConstraint#applies_to?` calls ActiveSupport's `present?`
(`base_constraint.rb:39-41`), which is not a dependency, so any caller
gets `NoMethodError`. It has no callers in `lib/` or `spec/`
(constraints-11).

`validate_all` and `apply_all` crash on an unlaid-out graph
(gap2-13; constraints-12): `RelativePositionConstraint#validate` does
`ref_node.x + …` and `(node.x - expected_x).abs` at
`relative_position_constraint.rb:71-76`, and `#apply_relative_position`
does the same at `:104-105`, both with no nil guard. Both entry points
are public and documented as pre-layout checks
(`constraint_processor.rb:90`, `:101`).

The existing spec asserts only the markers. "applies layer constraint"
(`spec/elkrb/layout/constraints/constraint_processor_spec.rb:66-75`)
checks `node.properties["_constraint_layer"] == 2` and nothing about
where the node ends up; the fixed-position example checks
`_constraint_fixed` / `_constraint_original_x` / `_constraint_original_y`
at `:61-63`. That is why all of the above passes today (tests-6;
constraints-14). The five individual constraint classes have no
dedicated spec at all.

Consumer contract: `elk.layered.layering.layerConstraint` is registered
`:accepted` by item 08 (S4). This item is what flips it to `:honoured`,
so item 09's once-per-key "accepted but not honoured" warning stops
firing for it.

## Do

Everything below is settled — do not re-decide.

1. `lib/elkrb/layout/algorithms/layered/layer_assigner.rb`: honour the
   layer constraint. Read FIRST / LAST / FIRST_SEPARATE / LAST_SEPARATE
   from `get("elk.layered.layering.layerConstraint", node)` and honour
   `node.constraints.layer` as well. Flip item 08's pre-seeded registry
   row from `:accepted` to `:honoured` — edit that one line in place, in
   its sorted position.
2. `ConstraintProcessor`: move every piece of scratch state into an
   instance Hash keyed by node id. Delete every write of
   `properties["_constraint_fixed"]`, `["_constraint_original_x"]`,
   `["_constraint_original_y"]`, `["_constraint_layer"]` and
   `["_assigned_layer"]`. Nothing internal may live in a serialised
   attribute.
3. `restore_fixed_positions` (`fixed_position_constraint.rb:48-58`) keys
   off the processor's own map plus `node.constraints&.fixed_position`,
   so unsetting `fixedPosition` in a re-fed output actually releases the
   node.
4. Alignment averages within ONE parent (item 14 already made
   `all_nodes` this-level-only — build on it, do not re-add recursion)
   and re-spaces the group along the other axis so members do not
   overlap. Divide by the count of non-nil coordinates, not by
   `nodes.length`, and skip a node with no coordinate rather than
   assigning it the biased average.
5. Resolve relative-position chains in topological order over the
   `relative_to` edges, detecting cycles. `position_priority` becomes a
   tie-break only, not the ordering.
6. Guard the arithmetic in `RelativePositionConstraint#validate`
   (`relative_position_constraint.rb:71-76`) and
   `#apply_relative_position` (`:104-105`): a node or reference with a
   nil coordinate produces an error string, never a `NoMethodError`.
7. Route every violation through `Elkrb.logger.warn` — the accessor
   item 09 added. Do not redefine `Elkrb.logger`. Drop the duplicate
   warn inside `apply_relative_position`
   (`relative_position_constraint.rb:95`) so one dangling reference
   produces exactly one line; validate reports it.
8. `BaseConstraint#applies_to?` drops `present?`
   (`base_constraint.rb:39-41`) — implement it as `!node.constraints.nil?`
   or delete it. It has no callers, so deleting is the smaller change;
   pick one and say which in the report.
9. Write the failing specs first, from JSON input through `Elkrb.layout`:
   a node with FIRST gets the smallest layer coordinate and one with
   LAST the largest, even when the edges imply otherwise; the output
   JSON contains no `_constraint_*` or `_assigned_layer` key anywhere;
   two aligned same-layer siblings do not overlap; the `a <- b <- c`
   chain with `c` listed before `b` resolves to (12,212) for `c`; a
   dangling `relativeTo` logs exactly once through `Elkrb.logger`;
   `ConstraintProcessor#validate_all` on a graph with no coordinates
   returns error strings instead of raising. Replace the marker
   assertions in
   `spec/elkrb/layout/constraints/constraint_processor_spec.rb` with
   layout assertions — the markers will not exist any more: `:74`
   (`_constraint_layer`, in the "applies layer constraint" example at
   `:66-75`) and `:61-63` (`_constraint_fixed`,
   `_constraint_original_x/y`).

Do not touch: `Elkrb.logger`'s definition (item 09 owns it),
`BaseConstraint#all_nodes` / `#find_node` recursion (item 14 already
settled it), `CHANGELOG.md`.

## Done when

- `bundle exec rake` is green.
- The layer-constraint repro above puts `a` at a LARGER layer coordinate
  than `b`, and both `props` hashes come back empty or absent.
- The fixed-position repro prints no `_constraint_*` key in
  `h["children"][0]["properties"]`.
- The alignment repro prints two DIFFERENT coordinates for `b` and `c`.
- The relative-chain repro prints `c=(12.0,212.0)` and logs no violation.
- The dangling-`relativeTo` repro prints exactly ONE line, and it comes
  from `Elkrb.logger`, not `Kernel#warn`.
- `grep -rn '_constraint_\|_assigned_layer' lib` returns nothing.
- `Elkrb::Options::Registry.status("elk.layered.layering.layerConstraint")`
  returns `:honoured`.

Mandatory gates, in order: `thermo-nuclear-review` → `execution-diff` →
Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. No dependency-contract-check: nothing here crosses
a boundary we do not own — say so in the report.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref and on the branch, then `diff -r`.
The exit status is informational; never chain on it.

INTENDED execution-diff differences, and nothing else:

- Every node that carried a constraint loses its `_constraint_*` /
  `_assigned_layer` keys from `properties`. Cases whose `properties`
  becomes empty drop the key entirely.
- Layered cases carrying a layer constraint change their layer
  assignment — that is the point of the item; list them.
- Cases carrying an alignment group change coordinates, because members
  are re-spaced instead of stacked.
- Cases carrying a relative-position chain change coordinates, because
  the chain now resolves in dependency order.
- Violation text moves from stdout/stderr `Kernel#warn` to the logger,
  and a dangling reference produces one line instead of two. The corpus
  dump records the layout, not the log, so this shows up only in the
  CLI examples.
- **Every case with no `constraints` key is byte-identical.** Most of
  the corpus has none, so most files must not move.

Any other difference is a bug.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit):
`_constraint_*` and `_assigned_layer` scratch keys no longer appear in
output `properties`; constraint violations go through `Elkrb.logger`
instead of `Kernel#warn`; a layer constraint now actually moves the node.
Note whether `applies_to?` was deleted or fixed.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
