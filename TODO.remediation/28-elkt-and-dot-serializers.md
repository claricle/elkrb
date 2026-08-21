# 28 — ELKT and DOT serializers
Slice S22 · branch `fix/s22-serializers`

Can start after 27 (S21) — the ELKT round-trip specs are written against
the new parser, and a serializer fixed against the old line-regex parser
would be specified against a moving target; after 09 (S5), because
`rankdir` is read through the resolver, which S5 introduces; and after 07
(S3b), which rewrites the `LayoutOptions.new` sites in
`spec/elkrb/serializers/*_spec.rb`. The XD gate needs 02 (S0b's
`corpus:dump` driver). Blocks the START of 37 (S30), which documents the
formats this item settles and folds this item's `## Breaking` section into
the CHANGELOG. Large (~350 lines). Not BREAKING for `Elkrb.layout` output;
ELKT and DOT text both change shape.

If the combined diff runs past ~350 lines, split into two branches —
`fix/s22a-elkt-serializer` and `fix/s22b-dot-serializer`. The
orchestrator opens both PRs; the implementer never does.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree.
`lib/elkrb/serializers/elkt_serializer.rb` is 236 lines,
`lib/elkrb/serializers/dot_serializer.rb` is 339; slice 1 touched
neither, so the 6ac367c line numbers still hold.

### DOT

Nested edges are emitted twice (formats-5). `format_subgraph` writes
`node.edges` inside the cluster (`:175-180`) and `format_node` writes
them again after it (`:143-148`):

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.from_json(%q({"id":"root","children":[{"id":"p","children":[{"id":"c1","width":40,"height":40},{"id":"c2","width":40,"height":40}],"edges":[{"id":"i","sources":["c1"],"targets":["c2"]}]}],"edges":[]})); puts Elkrb.export_dot(g).scan("c1 -> c2").size'
# 2
```

Edges to ports or compound nodes invent phantom Graphviz nodes
(formats-6). `format_edge` (`:235`) always writes
`sanitize_id(sources.first) -> sanitize_id(targets.first)`; ports are
never emitted and compounds are `subgraph cluster_…`:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.from_json(%q({"id":"root","children":[{"id":"n1","width":100,"height":60,"ports":[{"id":"p1"}]},{"id":"n2","width":100,"height":60,"ports":[{"id":"p2"}]}],"edges":[{"id":"e1","sources":["p1"],"targets":["p2"]}]})); puts Elkrb.export_dot(g)'
#   n1 [...]
#   n2 [...]
#   p1 -> p2        <- p1 and p2 are declared nowhere
```

Invalid bare ids are left unquoted (formats-7). `quote_value` (`:296`)
only quotes when a non-`[A-Za-z0-9_]` character is present, so
digit-leading ids and DOT keywords come out bare and Graphviz rejects the
file:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.from_json(%q({"id":"root","children":[{"id":"1st","width":40,"height":40}],"edges":[]})); puts Elkrb.export_dot(g)'
#   n1st [label=1st, …]      <- label=1st is not a valid DOT ID
```

`sanitize_id` collides distinct ids (formats-19). At `:309` it maps every
non-word character to `_` with no collision check:

```sh
bundle exec ruby -relkrb -e 'g=Elkrb::Graph::Graph.from_json(%q({"id":"root","children":[{"id":"a-b","width":40,"height":40},{"id":"a.b","width":40,"height":40}],"edges":[{"id":"e1","sources":["a-b"],"targets":["a.b"]}]})); puts Elkrb.export_dot(g)'
#   a_b [label="a-b", …]
#   a_b [label="a.b", …]
#   a_b -> a_b
```

Multi-label `\n` is double-escaped and the spec locks it in (formats-20).
`build_node_attributes` joins labels with the two-character DOT escape
`\n` (`:194`), then `quote_value` escapes the backslash, so Graphviz
renders a literal `\n`.
`spec/elkrb/serializers/dot_serializer_spec.rb:133` asserts
`include('label="Hello World\\\\nSecond Line"')` — the wrong output.

Positions are emitted as `pos="x,y!"` in ELK y-down coordinates
(formats-21, `:207`) while `diagram` renders with `-Kdot`, which ignores
`pos`. Engines that honour it (`neato -n2`) draw the graph upside down,
and a 3-point edge `pos` violates Graphviz's 3n+1 B-spline rule and is
discarded with a warning.

`rankdir` comes from a raw hash read (formats-22, `:110`). Item 06 (S3)
already changed that line to
`graph.layout_options&.[]("elk.direction") || graph.layout_options&.[]("direction")`,
so the canonical key works; what is still missing is alias and
`org.eclipse.elk.` handling, which only the resolver has.

### ELKT

User edge ids are stripped and auto ids collide (formats-12). `:209`
skips any id matching `/^e\d+$/`, and `generate_edge_id` (`:244` in the
parser) counts per node:

```sh
bundle exec exe/elkrb convert spec/fixtures/simple_graph.json -o /tmp/s.elkt
bundle exec exe/elkrb convert /tmp/s.elkt -o /tmp/s.json
ruby -rjson -e 'p JSON.parse(File.read("/tmp/s.json"))["edges"].map{|e|e["id"]}'
# ["e0", "e1"]     input was ["e1", "e2"]
```

Edge ids containing `:` round-trip into garbage (formats-3). The
serializer writes ids verbatim as `edge <id>: src -> tgt` (`:209-210`)
and the parser splits at the first `:`, so
`spec/fixtures/elkjs_bug7_complex.json`'s `A:B` ids come back as id `A`
with source `B: A`.

Labels and ids are written unescaped (formats-13, `:134`). A label
containing `"` produces invalid ELKT; a hyphenated or dotted id
(`node-1`, `a.b`) is written bare, the parser ignores the line, the node
disappears on re-parse and its size and labels attach to whatever block
is open.

Node and port options, port geometry, edge labels and extra hyperedge
endpoints are dropped (formats-15, `serialize_node_block` at `:116`).
A bogus `properties: {…}` line used to be emitted for the nested
`LayoutOptions#properties` hash (formats-14); item 06 (S3) deleted that
nesting, so this item's job is to confirm no `properties:` line survives
and to add the spec that keeps it gone.

`convert x.elkt -o x.yaml` writes a Ruby-symbol, camelCase YAML that
elkrb's own reader cannot fully read (formats-18,
`convert_command.rb:110`):

```sh
d=$(mktemp -d); printf 'algorithm: layered\nnode n1\n' > $d/y.elkt
bundle exec exe/elkrb convert $d/y.elkt -o $d/y.yaml && head -3 $d/y.yaml
# ---
# :id: root
# :layoutOptions:
```

`spec/elkrb/serializers/elkt_serializer_spec.rb:550` asserts nothing that
would catch any of the above (formats-26), and
`lib/elkrb/parsers/elkt_parser.rb:23` is dead code (formats-25).

## Do

Everything below is settled — do not re-decide.

1. ELKT serializer: escape `\` and `"` in label text; write ids that are
   not valid ELKT identifiers through a deterministic sanitiser with a
   collision counter, and record the mapping in the report — ELK itself
   quotes nothing, so mangle-and-warn is the honest option.
2. ELKT serializer: always emit the edge id when the edge has one. Delete
   the `/^e\d+$/` strip at `:209`. Item 27 already made auto ids
   graph-wide and collision-free.
3. ELKT serializer: emit `key: value` lines for node, port and edge
   `layoutOptions`; `layout [ position: … size: … ]` for ports; `label`
   lines and `{ }` blocks for edge labels; comma-separated endpoint lists
   for hyperedges. Confirm no `properties:` line is emitted and pin it
   with a spec.
4. DOT serializer: quote every id and every attribute value that is not
   `/\A[A-Za-z_][A-Za-z0-9_]*\z/` or a numeral, and quote DOT keywords
   (`node`, `edge`, `graph`, `digraph`, `subgraph`, `strict`, any case)
   unconditionally. Replace `sanitize_id` (`:309`) with quoting; where an
   id must still be sanitised, keep a `original => sanitised` Hash and
   append a counter on collision.
5. DOT serializer: emit each node's edges once, at the deepest common
   container. Delete the duplicate write at `format_node` (`:143-148`)
   and rely on `format_subgraph`.
6. DOT serializer: emit ports as `node:port` and give compound endpoints
   a representative child with `compound=true` and `lhead=`/`ltail=`, so
   no phantom node is invented.
7. DOT serializer: emit `pos="x,y!"` ONLY when the caller asks for neato
   (`engine: "neato"`); otherwise omit it. `dot` re-lays out the graph
   and a stale `pos` is worse than none.
8. DOT serializer: read `rankdir` from `resolver.get("elk.direction",
   graph)` so aliases and the `org.eclipse.elk.` prefix resolve.
9. DOT serializer: escape each label's text first, then join with the
   two-character `\n` OUTSIDE `quote_value`, and fix
   `spec/elkrb/serializers/dot_serializer_spec.rb:133` to
   `label="Hello World\\nSecond Line"`. The current expectation asserts
   the bug — replace it, do not delete it.
10. `convert_command.rb:110`: convert the ELKT Hash to a `Graph` before
    exporting, so every exporter sees one model and YAML output follows
    the gem's own schema instead of `Hash#to_yaml`.
11. Delete the dead code at `lib/elkrb/parsers/elkt_parser.rb:23`.
12. Write the specs first. JSON → ELKT → JSON is equal for every
    `spec/fixtures/*.json` and every `spec/fixtures/elkt/*` case item 27
    committed, including `elkjs_bug7_complex.json` with its `A:B` edge
    ids and its ports. DOT output goes through the real `dot -Tcanon`
    when Graphviz is on PATH, and through 02's fake dot otherwise,
    asserting the argv.

Do not touch: the ELKT grammar and the parser (item 27), option aliases
and precedence (items 08 and 09), `README.adoc` (item 30),
`CHANGELOG.md` (item 37 assembles it from the merged PR bodies'
`## Breaking` sections).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- Every repro in Facts is fixed, checked by running it:
  - the nested-edge command prints `1`, not `2`;
  - the port-edge command declares `n1:p1 -> n2:p2` and Graphviz invents
    no node — `… | dot -Tplain | grep -c '^node'` prints `2`;
  - the `1st` command emits `"1st"` quoted and `… | dot -Tplain` exits 0;
  - the `a-b` / `a.b` command yields two distinct DOT nodes;
  - the `simple_graph.json` round trip prints `["e1", "e2"]`.
- `bundle exec exe/elkrb convert spec/fixtures/elkjs_bug7_complex.json -o /tmp/b7.elkt`
  then back to JSON preserves every edge id and every port-referenced
  endpoint.
- `convert x.elkt -o x.yaml` produces string-keyed YAML in the gem's own
  schema, and reading it back keeps the layout options.
- `dot -Tsvg` on a two-label node renders two lines, not a literal `\n`.

Mandatory gates, in order: `thermo-nuclear-review` →
`dependency-contract-check` → `execution-diff` → Codex (max reasoning,
read-only, verify-before-critique) → `copilot-review` last.

dependency-contract-check is mandatory and its subject is Graphviz.
Construct the real boundary: run the generated DOT through
`dot -Tcanon` and `neato -n2 -Tplain` and read what comes back — do not
reason about DOT's ID grammar from memory. Cover a digit-leading id, a
DOT keyword id, a quoted-with-escape label, a `node:port` edge, a
`cluster_` endpoint with `lhead`/`ltail`, and the `pos` path with and
without `engine: "neato"`. Record which Graphviz version answered.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s22` stack base — and again on the branch, then `diff -r` the two
dump dirs. `corpus:dump`'s exit status is informational; never chain on
it.

INTENDED execution-diff differences, and nothing else:

- **The corpus dump is byte-identical.** `corpus:dump` writes layout JSON
  and this item changes no layout code; any difference there is a bug.
- The observable change is the ELKT and DOT text, plus
  `convert x.elkt -o x.yaml`. Drive it separately: run `convert` to each
  format over `spec/fixtures/*.json` and `spec/fixtures/elkt/*.elkt` on
  the base ref and on the branch, and diff those two output trees. Every
  difference must be one of quoting, escaping, a restored edge id, a
  de-duplicated nested edge, a `node:port` endpoint, an omitted `pos`, or
  the YAML schema — nothing else.

The report carries a `## Breaking` section (no `CHANGELOG.md` edit): ELKT
output now escapes labels and sanitises invalid ids deterministically and
always writes user edge ids; DOT output quotes ids and values, emits each
nested edge once, routes port edges as `node:port`, and omits `pos`
unless neato is asked for. Include the id-mapping table from step 1.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
