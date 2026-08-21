# 26 — `validate` correctness
Slice S20 · branch `fix/s20-validate`

Can start after 05 (S2 rewrites the loaders in `cli.rb` and in
`validate_command.rb#detect_and_parse`, and makes Thor exit non-zero —
this item builds on that loader and owns everything `validate` does with
what it returns). The XD gate and the subprocess specs need 02 (S0b's
`corpus:dump` driver, `run_elkrb`, and the `duplicate_ids` corpus
fixture). Blocks the START of 36 (S29), which rewrites `cli.rb` and
`cli_spec.rb` wholesale and needs this item's validate examples already
in the file. Medium (~220 lines). Not BREAKING for the library API;
`validate`'s exit codes, messages and output stream all change.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree.
`lib/elkrb/commands/validate_command.rb` is 241 lines and slice 1 did
not touch it, so the 6ac367c line numbers still hold.

`--strict` rejects every port-referenced edge (gap3-1). `collect_node_ids`
(`:226-238`) walks `children` only and never `ports`:

```sh
bundle exec exe/elkrb validate spec/fixtures/elkjs_bug7_complex.json --strict
# ❌ … has 33 error(s):
#   • edges[0]: Edge '…' references unknown target node '57da8b77fffd97e2179fc13f_0'
# exit 1 — all 33 are port ids on a valid ELK graph
```

It validates a model round trip, not the file (gap3-9). `load_any_format`
(`:32-58`) ends with `JSON.parse(graph.to_json, symbolize_names: true)`
(`:55-56`), so the validator sees lutaml's coercions instead of the
author's data: `"width":"x"` arrives as `0.0` (strict reports
`invalid width: 0.0` and never mentions `"x"`), `"sources":"a"` arrives
as `["a"]` while the model layout still holds the String, and unknown
`layoutOptions` keys are gone before validation.

Nested `edges` are never inspected (gap3-2). `validate_node`
(`:117-157`) walks `children` (`:145-148`) and `ports` (`:150-153`) and
never `node[:edges]`:

```sh
f=$(mktemp -d)/g.json
printf '{"id":"root","children":[{"id":"a","width":50,"height":30,"children":[{"id":"a1","width":20,"height":20}],"edges":[{"id":"ne","sources":["a1"]}]},{"id":"b","width":50,"height":30}],"edges":[]}' > $f
bundle exec exe/elkrb validate $f --strict; echo exit=$?
# ✅ … is valid    exit=0   (the nested edge has no targets)
```

No id-uniqueness check (gap3-3). `collect_node_ids` builds a plain Array
and nothing compares entries:

```sh
f=$(mktemp -d)/g.json
printf '{"id":"root","children":[{"id":"a","width":50,"height":30},{"id":"a","width":50,"height":30}],"edges":[]}' > $f
bundle exec exe/elkrb validate $f --strict; echo v=$?   # ✅ valid, v=0
bundle exec exe/elkrb layout $f --format json; echo l=$? # Error: undefined method '-' for nil, l=1
```

Dangling endpoints pass by default (gap3-15). The endpoint check is
gated on `@options[:strict]` (`:184`), so plain `validate` blesses an
edge to a non-existent id and exits 0; `layout` then returns that edge
with no sections and exit 0.

Six shape checks are unreachable (gap3-11): `Graph must be a Hash`
(`:90`), `Node must be a Hash` (`:120`), `Edge must be a Hash` (`:162`),
the two `sources/targets must be an array` branches (`:174-181`),
`Port must be a Hash` (`:204`) and the only `--strict` extra,
`layoutOptions must be a Hash` (`:219-221`). The loader raises
`Lutaml::Model::InvalidFormatError` on those shapes before
`validate_graph` runs, and the round trip coerces scalars to arrays.

`collect_node_ids(graph)` is called inside the edges loop (`:106`), so
the full recursive walk runs once per edge — even in non-strict mode,
where `validate_edge` never reads the result (gap3-12). Measured on
`v2`, non-strict, `validate_graph` alone:

```sh
bundle exec ruby -relkrb -rbenchmark -e 'require "elkrb/commands/validate_command"; [500,1000,2000].each{|n| g={id:"r",children:(0...n).map{|i|{id:"n#{i}",width:1,height:1}},edges:(0...2*n).map{|i|{id:"e#{i}",sources:["n#{i%n}"],targets:["n#{(i*7+1)%n}"]}}}; c=Elkrb::Commands::ValidateCommand.new("x",{}); printf("n=%d %.2fs\n", n, Benchmark.realtime{ c.send(:validate_graph,g) })}'
# n=500 0.08s   n=1000 0.28s   n=2000 1.07s
```

Four times the work for twice the size — quadratic. Extrapolated,
10k nodes / 20k edges is ~27 s.

The report goes to stdout. `run` (`:16-28`) prints both the ✅ line and
the ❌ error list with `puts`, then `exit 1`. Item 05 (S2) sends
`Cli#error_output` to stderr but is explicitly told not to touch
`validate` semantics, so the report is this item's to move.

`--output x.yml` writing JSON is NOT here — that is `cli.rb`'s `layout`
`--format`/`output_result`, owned by 36 (S29).

## Do

Everything below is settled — do not re-decide.

1. Validate the parsed document, never a model round trip. Replace
   `load_any_format`'s trailing `JSON.parse(graph.to_json, …)` (`:50-57`)
   with a loader that returns the raw parsed document: `JSON.parse(content,
   symbolize_names: true)` for `.json`, `YAML.safe_load` for `.yml`/`.yaml`,
   `ElktParser.parse` for `.elkt`, and for anything else the same
   first-non-whitespace-char sniff item 05 installed (`{` or `[` → JSON,
   else YAML, else ELKT). Validating the file is the point of the slice;
   the round trip is what hid every defect above.
2. Because the document is now raw, the six shape checks at `:90`,
   `:120`, `:162`, `:174-181`, `:204` and `:219-221` become reachable —
   keep them and give each one a spec. Do not delete them.
3. Collect ids ONCE into a Set before the edges loop, recursively, over
   node ids AND port ids (`collect_node_ids` → `collect_ids`), and pass it
   to `validate_edge`. Report `duplicate id: <id>` for any repeat across
   node ids, port ids and edge ids. This is O(N) and kills gap3-12 with
   gap3-3.
4. Make endpoint resolution a DEFAULT check, not a `--strict` extra
   (`:184`). An endpoint that names a port id is valid; reword the message
   to `references unknown source/target node or port '<id>'`.
5. In `validate_node`, iterate `node[:edges] || node["edges"]` and call
   `validate_edge(edge, "#{path}.edges[#{idx}]", ids)` with the hoisted
   id set.
6. Move the report to stderr — `$stderr.puts` for the ❌ header and every
   error line — and keep `exit 1` when any error was found. The ✅ line
   stays on stdout.
7. Write the specs first, via `run_elkrb` (02/S0b's subprocess runner),
   in their own `describe "S20"` section or a new
   `spec/elkrb/cli/validate_spec.rb`:
   - `validate spec/fixtures/elkjs_bug7_complex.json --strict` → exit 0.
   - the duplicate-id graph → exit 1 and stderr contains `duplicate id: a`.
     `spec/fixtures/corpus/duplicate_ids.json` is a
     `{"algorithm":…,"graph":…}` wrapper, which `validate` would read as a
     graph with no `id`/`children` — write its `["graph"]` member to a tmp
     file and validate that.
   - a compound node holding an edge with a dangling target → exit 1.
   - a 10 000-node / 20 000-edge document validates in under 2 s.

Do not touch: `cli.rb` (item 36 rewrites it), the `--output` extension →
format inference (item 36), the error classes `AlgorithmNotFoundError` /
`ValidationError` / `UnsupportedConfigurationException` and where they
are raised (items 09, 11 and 12 own those).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- `bundle exec exe/elkrb validate spec/fixtures/elkjs_bug7_complex.json --strict`
  exits 0 and prints no port-id errors.
- The duplicate-id repro above exits 1, and `duplicate id: a` appears on
  stderr, not stdout:
  `bundle exec exe/elkrb validate $f 2>/dev/null` prints nothing.
- The nested-edge repro above exits 1.
- The benchmark loop above stays flat: 10 000 nodes / 20 000 edges under
  2 s.

Mandatory gates, in order: `thermo-nuclear-review` → `execution-diff` →
Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. `dependency-contract-check` is not required once
step 1 lands, because the loader then rescues stdlib `JSON::ParserError`
and `Psych::SyntaxError` rather than a gem's error class — say that in
the report. If any `Graph.from_*` call survives in
`validate_command.rb`, DCC becomes mandatory: the rescued class is then
lutaml's.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s20` stack base — and again on the branch, then `diff -r` the two
dump dirs. `corpus:dump`'s exit status is informational; never chain on
it.

INTENDED execution-diff differences, and nothing else:

- **The corpus dump is byte-identical.** This item touches no layout
  code, so any difference there is a bug.
- The observable change is the `validate` exit-code / stream / message
  matrix, which the specs cover: port-referenced edges now pass strict;
  duplicate ids, dangling endpoints and nested-edge defects now fail;
  the report moves from stdout to stderr.

Record that matrix (command × before exit/stream → after exit/stream) in
the report.

The report carries no `## Breaking` section — `validate` is a CLI
command, not library API. Note in the report that a script relying on
`validate` exiting 0 for a dangling endpoint will now see exit 1, which
is the point.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
