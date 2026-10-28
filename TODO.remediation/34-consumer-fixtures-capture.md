# 34 — Consumer fixtures: capture
Slice S27a · branch `fix/s27a-sirena-capture`

Can start after 06 (S3) — S3 is what makes a Hash with a symbol
`layoutOptions:` key survive `Graph.from_hash`, and the whole point of
these fixtures is that a sirena Hash lays out and echoes its options.
Blocks the START of 35 (S27b), which reads these fixtures — this item is
what turns "the consumer sends this shape" from a claim into a committed
file. Small (~120 lines). Spec-only, no `lib/` change. Not BREAKING.

## Facts

Verified 2026-08-21 against `claricle/sirena` at `942499a` and against
elkrb `v2` (a008889) extracted to a scratch tree. Re-read both before
capturing — sirena moves.

Sirena's transforms build **Ruby Hashes with symbol keys** and will call
`Elkrb.layout(hash)`. `C4Transform#to_graph` returns
(`lib/sirena/transform/c4.rb:48-60`):

```ruby
{ id:, children:, edges:, layoutOptions: layout_options(diagram), metadata: {…} }
```

Two things about that root on `v2`:

```sh
bundle exec ruby -relkrb -e 'h={id:"r",children:[{id:"a",width:10,height:10}],edges:[],layoutOptions:{"elk.algorithm"=>"layered"},metadata:{level:"Context"}}; g=Elkrb::Graph::Graph.from_hash(h); p g.layout_options'
# nil
```

The camelCase symbol key `layoutOptions:` is dropped — item 06 fixes
that. The unknown `metadata:` key is silently ignored and does not raise,
which is the behaviour these fixtures must keep pinning.

Shapes emitted today:

- flowchart, class, state, ER, sequence and user-journey graphs are
  **flat** — no nesting.
- **C4 nests boundaries recursively.** `transform_boundary`
  (`c4.rb:81-123`) calls itself at `:90` and hangs per-node
  `layoutOptions` on each boundary at `:115`, from
  `boundary_layout_options` (`c4.rb:276-285`):
  `elk.algorithm: "box"`, `elk.box.packingMode: "GROUP_MIXED"`,
  `elk.padding: "[top=…,left=…,bottom=…,right=…]"`, and
  `elk.spacing.nodeNode` as a **String** (`ELEMENT_SPACING.to_s`).
- C4 **keeps relationships at the root** — edges whose endpoints live
  inside boundaries. That is the case item 15 (S10b) routes.
- mindmap returns `{nodes:, connections:, width:, height:, root:}`
  (`mindmap.rb:46-52`), not an ELK graph. Out of contract until sirena
  adapts it — do not capture it.
- No transform emits ports or per-edge `layoutOptions`.
- Root `algorithm` is always `"layered"` today. `stress`, `force`,
  `mrtree` and `sporeOverlap` are defined constants
  (`lib/sirena/transform/base.rb:44-48`) that nothing emits yet.
- Root spacings are numeric; only the C4 boundary spacing is a String.
- `elk.layered.considerModelOrder.strategy: "NODES_AND_EDGES"` comes from
  the shared default at `base.rb:163`.
- `elk.hierarchyHandling: "INCLUDE_CHILDREN"` is emitted by four
  transforms: `c4.rb:271`, `class_diagram.rb:276`, `er_diagram.rb:199`,
  `user_journey.rb:202`.

The capture path runs through private methods on `Sirena::Engine`
(`lib/sirena/engine.rb`, `private` at `:119`): `detect_diagram_type`
(`:126`), `retrieve_handlers` (`:143`), `parse_diagram` (`:159`),
`transform_diagram` (`:173`). `retrieve_handlers` returns a Hash with
`:parser` and `:transform`. They are private and they have moved before —
verify the names against `engine.rb` at capture time, not against this
file.

## Do

Everything below is settled — do not re-decide.

1. Write small hand-written mermaid sources under
   `spec/fixtures/consumers/sirena/src/`, one per shape: `flowchart_td`,
   `flowchart_lr`, `class_flat`, `state`, `er`, `sequence`,
   `user_journey`, and `c4_nested` — the last with **two nested
   boundaries and a relationship between a member of each**, because that
   is the case item 15 (S10b) has to route and 35 (S27b) asserts.
2. Capture each transform's real Hash with this script, run from the
   sirena checkout, and commit the JSON next to its source as
   `spec/fixtures/consumers/sirena/<name>.json`:

   ```sh
   cd ~/claricle/sirena && bundle exec ruby -rjson -rsirena -e \
     'src=File.read(ARGV[0]); eng=Sirena::Engine.new;
      t=eng.send(:detect_diagram_type, src);
      h=eng.send(:retrieve_handlers, t);
      d=eng.send(:parse_diagram, src, h[:parser]);
      g=eng.send(:transform_diagram, d, h[:transform], Date.today);
      puts JSON.pretty_generate(g)' \
     spec/fixtures/consumers/sirena/src/<name>.mmd
   ```

   Pin the date (`Date.today` is passed explicitly so a fixture cannot
   drift with the clock) and do not hand-edit the output. A hand-written
   fixture proves nothing about the consumer.
3. Commit `spec/fixtures/consumers/sirena/README.md` holding the script
   verbatim, the sirena commit sha the capture ran against, and the date.
   Without the sha nobody can tell a stale fixture from a changed
   consumer.
4. Add `synthetic_mrtree.json`, `synthetic_stress.json`,
   `synthetic_force.json` and `synthetic_sporeOverlap.json` beside them,
   built from the constants at `base.rb:44-48`. Name them `synthetic_*`
   so nobody mistakes them for a capture — sirena does not emit these
   algorithms yet.
5. `spec/elkrb/consumers/sirena_capture_spec.rb`, one example per
   fixture:
   - `Elkrb.layout(JSON.parse(File.read(f), symbolize_names: true))` does
     not raise;
   - `JSON.parse(result.to_json)["layoutOptions"]` equals the input's
     `layoutOptions` byte for byte, at the root AND on every C4 boundary
     node;
   - the unknown `metadata:` key is accepted and does not appear in the
     output.
   Where an assertion cannot hold until item 09 (S5) merges, mark it
   `pending: "RC2: <one line>"` — `pending`, never `skip`, so it fails
   loudly the day it starts passing.

Do not touch: `lib/`, `exe/`, the registry, the resolver. This item
captures; 35 (S27b) asserts the contract.

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- `bundle exec rspec spec/elkrb/consumers/sirena_capture_spec.rb` has 0
  failures, with every remaining `pending` naming an RC and a slice.
- `spec/fixtures/consumers/sirena/` holds 8 captured JSON files, their 8
  `.mmd` sources, 4 `synthetic_*.json`, and the README with the sirena
  sha.
- `c4_nested.json` really nests: at least two levels of `children`, a
  `layoutOptions` map on each boundary carrying `elk.algorithm: "box"`,
  and at least one root edge whose endpoints are inside different
  boundaries. Check it by reading the file, not by trusting the capture.
- `git diff --stat` shows no change under `lib/` or `exe/`.

Mandatory gates, in order: `thermo-nuclear-review` → Codex (max
reasoning, read-only, verify-before-critique) → `copilot-review` last.

No dependency-contract-check and no execution-diff. Say so explicitly in
the report rather than skipping silently: the fixtures ARE the boundary
record, captured from the real consumer rather than remembered, and the
slice changes no runtime code — prove the second half with
`git diff --stat`.

The report carries no `## Breaking` section. Record instead: the sirena
sha, one line per fixture saying what shape it captures, and every
assertion left `pending` with the slice that will un-pend it.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
