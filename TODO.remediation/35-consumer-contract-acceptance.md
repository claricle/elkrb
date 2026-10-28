# 35 — Consumer contract: acceptance
Slice S27b · branch `fix/s27b-sirena-contract`

Can start only when the contract is complete — every slice the table below
cites is merged: 09 (S5 resolver and precedence), 10 (S6 every option read on
the resolver), 13 (S9 layered direction and spacing), 14 (S10 nested
`elk.algorithm` dispatch), 15 (S10b cross-level edge routing), 16 (S11 edge
routing), 22 (S16 box packing), 23 (S17 mrtree direction), 31 (S25a the two
layered strategy keys), 32 (S25b long-edge dummies), 33 (S26 performance), 36
(S29 `elkrb options`). It also reads 34 (S27a)'s captured fixtures. **36
carries a higher number than this item** — the numbering follows the effort's
overall dependency order, not this item's, so read the list, not the ordering.
The direct blockers are 15, 22, 23, 32, 33, 34 and 36 — each names this item;
09, 10, 13, 14, 16 and 31 reach it through them (13 and 31 via 32, 14 and 16
via 15, 09 via 10). Blocks the START of 37 (S30), the final slice. Small (~150
lines). Spec-only, no `lib/` change. Not BREAKING.

This is the adoption gate. It is the spec that says a consumer can pick
elkrb 2.0 up and get what the docs promised.

## Facts

The contract was read from `claricle/sirena` on 2026-08-19 and verified
against `lib/sirena/transform/*.rb`. It is reproduced here in full
because this file has to stand alone — and because the spec copies it in
as DATA, so it cannot drift silently.

| key | sirena today / defined-future | elkrb 2.0 registry status | owning item |
|---|---|---|---|
| `algorithm` (bare) | emits `layered`; defines stress, force, mrtree, `sporeOverlap` | `:honoured` — camelCase `sporeOverlap` resolves through registry name normalisation | 08, 09 |
| `elk.direction` | emits DOWN/UP/LEFT/RIGHT | `:honoured` — layered (13), mrtree (23); bare `direction` is a registered alias | 13, 23 |
| `elk.spacing.nodeNode` | emits 50 and 75; C4 boundaries emit the String `"60"` | `:honoured` by every algorithm; the String is coerced by the registry | 09, 10 |
| `elk.layered.spacing.nodeNodeBetweenLayers` | emits 50 | `:honoured` | 13 |
| `elk.spacing.edgeNode` | emits 20–40 | `:accepted` | 08 |
| `elk.spacing.edgeEdge` | emits 20–40 | `:accepted` | 08 |
| `elk.layered.nodePlacement.strategy` | emits SIMPLE and NETWORK_SIMPLEX | `:accepted` — SIMPLE is what elkrb does; NETWORK_SIMPLEX and BRANDES_KOEPF fall back to it | 13 |
| `elk.layered.considerModelOrder.strategy` | emits NODES_AND_EDGES | `:honoured` from 31 — input order is the tie-break | 31 |
| `elk.layered.crossingMinimization.strategy` | defined, not emitted | `:honoured` from 31 — LAYER_SWEEP and NONE; any other value falls back to LAYER_SWEEP | 31 |
| `elk.layered.compaction.postCompaction.strategy` | defined, not emitted | `:accepted` | 08 |
| `elk.hierarchyHandling` | emits INCLUDE_CHILDREN | `:partial` — flat graphs behave as SEPARATE_CHILDREN; nested C4 gets cross-level edges routed in the container frame; no cross-level layering | 14, 15 |
| `elk.edgeRouting` | defined, not emitted | `:honoured` | 16 |
| `elk.padding` (String) | emits on C4 boundaries | `:honoured` via `ElkPadding` | 09 |
| `elk.box.packingMode` | emits GROUP_MIXED on C4 boundaries | `:accepted` — SIMPLE is implemented, GROUP_* fall back to it | 22 |
| `elk.algorithm: box` on a boundary node | emits on C4 boundaries | `:honoured` — a nested pin dispatches that algorithm for that compound (decision 12) | 14 |

Verified in the sirena tree at `942499a`:
`elk.hierarchyHandling: "INCLUDE_CHILDREN"` is emitted by `c4.rb:271`,
`class_diagram.rb:276`, `er_diagram.rb:199` and `user_journey.rb:202`;
`elk.layered.considerModelOrder.strategy` comes from the shared default
at `base.rb:163`; the C4 boundary block
(`c4.rb:276-285`) is `elk.algorithm: "box"`,
`elk.box.packingMode: "GROUP_MIXED"`, `elk.padding: "[top=…]"`,
`elk.spacing.nodeNode: "60"` (a String).

Item 08 (S4) put every one of these keys in the registry as an explicit
row with the status above, so the later slices only ever flip a status on
their own line. Item 09 (S5) added `Resolver#report_unhonoured(graph)`,
which runs once per `Elkrb.layout` and logs exactly one warning per
canonical key whose status is not `:honoured` — `"elkrb: option <id> is
accepted but not honoured in this version"` for `:accepted` and
`:unsupported`, `"elkrb: option <id> is partially honoured: <note>"` for
`:partial`. Keys the registry does not know go to DEBUG, never WARN.

If the registry disagrees with the table above when you run, that is a
finding, not something to paper over. The table is the authority — say
which slice set the other value and raise it.

## Do

Everything below is settled — do not re-decide.

1. `spec/elkrb/consumers/sirena_contract_spec.rb` holds the table as
   DATA — `KEY => { status:, slice: }` — copied from the table above.
   Never re-derive it from the registry at run time; the whole point is
   that the two are compared.
2. For every key: `Elkrb::Options::Registry.status(key)` equals the
   table's status. One example per row, so a failure names the key.
3. `:honoured` keys: varying the value CHANGES the output, and the change
   is the specific one the key promises — not merely "differs":
   - `elk.direction`: the layer axis flips (RIGHT ↔ DOWN);
   - `elk.spacing.nodeNode` / `elk.layered.spacing.nodeNodeBetweenLayers`:
     a named coordinate moves by the named delta;
   - `algorithm`: the output carries the other algorithm's signature
     positions;
   - `elk.padding` as the C4 String: children sit at the padded origin;
   - `elk.edgeRouting`: ORTHOGONAL yields bend points where POLYLINE
     yields none;
   - `elk.algorithm: "box"` on a boundary node: that compound's children
     take box row positions while the root stays layered;
   - `elk.layered.considerModelOrder.strategy` and
     `…crossingMinimization.strategy`: a crossing count changes.
4. `:accepted` keys: exactly ONE `Elkrb.logger` warning naming the key,
   and output byte-identical with and without it. Both halves — a warning
   without byte-identity is a lie in the other direction.
5. `:partial` keys — only `elk.hierarchyHandling` — assert exactly one
   warning AND the bounded effect the registry note names: on the C4
   fixture, every root relationship gains sections while node coordinates
   stay identical to the run without the key.
6. `Elkrb::Layout::AlgorithmRegistry.get("sporeOverlap")` returns
   `Elkrb::Layout::Algorithms::SporeOverlap` — the camelCase spelling
   sirena's constant uses.
7. C4 fixture (`spec/fixtures/consumers/sirena/c4_nested.json`, committed
   by 34): every root relationship has exactly one section whose start
   and end lie on the absolute borders of the two members, expressed in
   the root frame. That is item 15's promise, asserted from the consumer's
   own data.
8. Capture warnings by setting `Elkrb.logger` to a `Logger` over a
   `StringIO` for the example and restoring it after — item 09 made the
   accessor settable for exactly this.

Do not touch: `lib/`, `exe/`, the registry table, the resolver. If an
assertion here fails, the fix belongs in the owning item's slice, not in
this spec.

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- `bundle exec rspec spec/elkrb/consumers/sirena_contract_spec.rb` is
  green with **zero pending**. A pending example here means the contract
  is not met, and this item cannot close on one.
- Every key in the table has a status example, an effect example (or a
  warning-plus-byte-identity example), and a named slice.
- `bundle exec rspec spec/elkrb/consumers/` — both this spec and 34's
  capture spec — is green.
- `git diff --stat` shows no change under `lib/` or `exe/`.

Mandatory gates, in order: `thermo-nuclear-review` → Codex (max
reasoning, read-only, verify-before-critique) → `copilot-review` last.

No dependency-contract-check and no execution-diff. Say so explicitly in
the report rather than skipping silently: this slice adds no runtime code
(prove it with `git diff --stat`), and the consumer boundary was already
captured from the real transforms by item 34.

The report carries no `## Breaking` section. Record instead, one line per
key: the status asserted, the effect asserted, and whether the registry
agreed with the table. Any disagreement is named with the slice that
introduced it.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
