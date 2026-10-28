# 08 — Options registry
Slice S4 · branch `fix/s4-options-registry`

Status: **merged into `v2`** via PR #7, at 1c0abca. Closed. Gate B (Codex
`ultra`) approved that SHA after six rounds; the approval artifact is
`.claude/codex-approvals/s4-options-registry@1c0abca.txt`.

Can start: closed. When it was open: 01 (S1) was the `v2` seed and this item
edits `lib/elkrb.rb`
next to slice 1's change to the same file. The XD gate needs 02 (S0b's
`corpus:dump` driver); the build may start before that by materialising the
driver from `fix/s0b-corpus-cli-harness` uncommitted. Blocks the start of 09
(S5 — the resolver reads `Registry.canonical`/`coerce`/`default`, and
`report_unhonoured` reads `Registry.status`/`note`) and 36 (S29 — `elkrb
options` prints the status field). Parallel with 05 (S2), 06 (S3) and 11 (S7).
Medium (~250 lines). Not breaking — no layout behaviour changes.

## Facts

Measured against `v2` (a008889) in a worktree at `/private/tmp/elkrb-v2`.

`Elkrb.known_layout_options` is a hand-written 6-entry Hash
(`lib/elkrb.rb:403-441` — the audit's `:411-449` is 6ac367c; slice 1 moved it
up 8 lines). It is inconsistently prefixed and misses everything a user
actually passes (elk-compat-26; pipeline-15):

```sh
bundle exec ruby -relkrb -e 'p Elkrb.known_layout_options.keys'
# ["algorithm", "elk.direction", "elk.spacing.nodeNode", "elk.padding", "position", "bendPoints"]
bundle exec ruby -relkrb -e 'p Elkrb::Layout::LayoutEngine.known_layout_options'
# []   <- TODO stub at layout_engine.rb:157-160
```

Two same-named public APIs with different shapes, and one of them returns
nothing.

`AlgorithmRegistry.register` stores `name.to_s` verbatim while `get`
normalises, and `normalize_name` only strips the dotted prefix and downcases —
it does no camelCase folding (`algorithm_registry.rb:10-14`, `:16-19`,
`:46-52`). So ELK's own camelCase ids do not resolve (pipeline-14;
spore-libavoid-vertiflex-11):

```sh
bundle exec ruby -relkrb -e 'p Elkrb::Layout::AlgorithmRegistry.get("sporeOverlap"), Elkrb::Layout::AlgorithmRegistry.get("spore_overlap")'
# nil
# Elkrb::Layout::Algorithms::SporeOverlap
```

`algorithm_info` has no `supported_options` field at all.

`ElkPadding`, `KVector` and `KVectorChain` are referenced only as metadata
strings in `known_layout_options`; nothing in the layout path calls them
(data-model-20; elk-compat-6). `KVectorChain.from_string`
(`k_vector_chain.rb:42-65`) only accepts the brace form and raises on ELK's
own canonical output (gap2-8):

```sh
bundle exec ruby -relkrb -e 'Elkrb::Options::KVectorChain.parse("(1.0,2.0; 3.0,4.0)")'
# ArgumentError "Invalid coordinate pair" from k_vector_chain.rb:57
```

The literal defaults this item must copy **verbatim** live at:
`base_algorithm.rb:100` (`spacing_node_node` 20.0), `:107` (padding
`{top: 12, bottom: 12, left: 12, right: 12}`);
`layered/node_placer.rb:16-17` (`layer_spacing` 60.0, `spacing_node_node`
20.0); `box.rb:18` and `random.rb:17` (`aspect_ratio` 1.6);
`force.rb:20-22` (300 / 5.0 / 0.001); `stress.rb:20-21` (500 / 0.0001);
`libavoid.rb:95,158,159` (10 / 1.0 / 2.0); `spore_overlap.rb:15-16` (50 /
10.0); `spore_compaction.rb:15-16` (`"both"` / 10.0); `disco.rb:20,26,110`
(`"layered"` / 20.0 / `"row"`); `vertiflex.rb:44-67` (3 / 50.0 / 30.0 /
`true`); `topdown_packing.rb:103,109` (1.0 / nil);
`label_placer.rb:337,344` (`label.padding` 5.0, `label.margin` 5.0).

Corpus is 47 cases (02/S0b). Two of them —
`java_elk_sporeOverlap` and `java_elk_sporeCompaction` — carry camelCase
algorithm names and sit in S0b's `KNOWN_FAILURES` with `no_crash` and
`invariants` rows tagged RC14.

Consumer contract: sirena emits bare `algorithm: "layered"` today and has
`stress`/`force`/`mrtree`/`sporeOverlap` as defined constants
(`base.rb:44-48`). The camelCase one only resolves once this item folds names.

## Facts about what shipped

- `lib/elkrb/options/registry.rb` (new, 263 lines) holds **58 rows**, one per
  line, sorted by id, `private_constant :OPTIONS`, deep-frozen. Public API:
  `canonical(key)`, `coerce(id, value)`, `default(id)`, `status(id)`,
  `note(id)`, `for_algorithm(name, include_all: true)`, `all`,
  `render_known_options(algorithm_values:)`.
- Every id of the consumer-contract table is an explicit row with its status:
  `elk.hierarchyHandling` `:partial` with note
  `"cross-level edges are routed; no cross-level layering"`;
  `elk.spacing.edgeNode`, `elk.spacing.edgeEdge`,
  `elk.layered.nodePlacement.strategy`,
  `elk.layered.considerModelOrder.strategy`,
  `elk.layered.crossingMinimization.strategy`,
  `elk.layered.compaction.postCompaction.strategy`, `elk.box.packingMode`,
  `elk.layered.layering.layerConstraint` all `:accepted`; plus pre-seeded
  `elk.radial.centerOnRoot` and `elk.disco.componentCompaction.strategy` as
  `:accepted` for items 23 (S17) and 24 (S18).
- `AlgorithmRegistry` gained `resolve_key` on top of `normalize_name`:
  `normalize_name` now folds camelCase to snake_case, and `resolve_key` falls
  back to a legacy plain-downcase form for the run-together registrations
  (`mrtree`, `libavoid`, …) that predate word-boundary folding. Two rules,
  not one: a single folding rule breaks `mrtree`. Keep both.
- `algorithm_info` gained `supported_options:`. A custom registration that
  does not inherit `BaseAlgorithm` (the documented escape hatch on
  `register_algorithm`) advertises only its own algorithm-specific ids, since
  it does not get the shared mixins that make the `algorithms: :all` rows
  apply. Checked with `defined?`, not a require — `algorithm_registry.rb` must
  stay loadable on its own.
- `KVectorChain.from_string` now mirrors ELK: split on
  `/[,;()\[\]{}\s]+/`, raise on an odd token count, pair the rest. The
  accessor is `vectors` (and `to_a`), **not** `points`. There is no
  `points` method on this class; assert against `vectors`.

## Do

Design decision D2, ruled: one data table is the source of truth for option
metadata. No layout behaviour changes in this slice.

1. New `lib/elkrb/options/registry.rb`. Each row carries `type`, `default`,
   `description`, `status:` (`:honoured` / `:partial` / `:accepted` /
   `:unsupported`) and, where relevant, `values`, `aliases`, `algorithms`,
   `namespace: :elkrb`, and `note:` (String, **required** for `:partial`).
   One row per line, sorted by id. Later items insert in sorted position,
   never at the end.
2. Canonical ids are ELK's. elkrb-private keys (`spore.*`, `libavoid.*`,
   `vertiflex.*`, `topdownpacking.*`, `disco.component*`, `label.padding`,
   `label.margin`, `label.placement.disabled`, `elk.selfLoop*`,
   `elk.spline.curvature`) are registered verbatim under `namespace: :elkrb`.
   `hierarchical` stays an elkrb-private boolean — do **not** map it to
   `elk.hierarchyHandling`; elkrb's flag means per-level recursion,
   INCLUDE_CHILDREN means something else.
3. Bare `direction` IS a registered alias of `elk.direction` (decision 9,
   maintainer ruling). It is honoured wherever `elk.direction` is, and item 30
   documents it as an elkrb convenience that elkjs ignores.
4. `Registry.canonical(key)` resolves, in order: the exact id; `org.eclipse.elk.`
   stripped to `elk.`; the alias table; a bare suffix match when exactly one
   id ends with `.<suffix>` (so `spacing.nodeNode` → `elk.spacing.nodeNode`,
   while `direction` resolves through its explicit alias, not the suffix
   rule). Returns nil for an unknown key.
5. `Registry.coerce(id, value)` by `type`: `:float` (`"40"` → 40.0),
   `:integer`, `:boolean` (`"true"` → true), `:padding` (String via
   `Options::ElkPadding.parse`, Hash with String or Symbol keys, Numeric →
   uniform), `:kvector` (`KVector.parse`), `:kvector_chain`
   (`KVectorChain.parse`), `:enum` (upcased String).
6. Fill every default from the current code's literal, **verbatim**. Do not
   "fix" one here. Record any literal that two call sites disagree on; do not
   reconcile it. `elk.layered.spacing.nodeNodeBetweenLayers` stays 60.0 with
   a comment that item 13 (S9) changes it to ELK's 20.0.
7. Per-algorithm defaults (force spacing 80, box spacing/padding 15, mrtree
   padding 20) are **not** registry data. The algorithm passes its own
   default as the `default:` keyword of `option(key, default: literal)` —
   item 09 (S5) introduces that keyword form. The registry holds the ELK core
   default that `known_layout_options` reports.
8. `lib/elkrb.rb`'s `known_layout_options` and
   `layout_engine.rb:157-160` both render from `Registry`. Same shape, same
   content, keyed by canonical id — the two APIs stop disagreeing.
9. `algorithm_registry.rb`: `register` normalises the name the same way `get`
   does, so `get("sporeOverlap")`, `get("spore_overlap")` and
   `get("org.eclipse.elk.sporeOverlap")` all reach the class registered as
   `"spore_overlap"`. Check the names actually registered in
   `lib/elkrb/layout/algorithms/*.rb` and keep them working — the
   run-together ones (`mrtree`, `libavoid`, `rectpacking`, `topdownpacking`)
   need the legacy fallback. `algorithm_info` gains
   `supported_options: Registry.for_algorithm(id)`.
10. `k_vector_chain.rb`: `parse` accepts `"(1,2; 3,4)"` and `"(1,2),(3,4)"`
    as well as the brace form. Keep `def each(&block)` or `def each(&)` —
    lutaml-model 0.8.19's `runtime_compatibility.rb` already uses `(*, &)`,
    so the effective Ruby floor is 3.2 and either is fine. The gemspec
    `required_ruby_version` change is item 37's (S30), not this one's.
11. Specs first. `spec/elkrb/options/registry_spec.rb`: every id has a type
    and a default; every alias maps to an existing id;
    `canonical("spacing_node_node") == "elk.spacing.nodeNode"`;
    `canonical("org.eclipse.elk.direction") == "elk.direction"`;
    `canonical("spacing.nodeNode")`; `canonical("nope")` nil;
    `coerce("elk.spacing.nodeNode", "40") == 40.0`;
    `coerce("elk.padding", "[top=1,left=2,bottom=3,right=4]")` → an
    `ElkPadding` with those values; `coerce("elk.padding", {top: 5})` fills
    the rest with 12; `coerce("elk.padding", 7)` uniform;
    `KVectorChain.parse("(1,2; 3,4)").to_a.size == 2`. Contract rows:
    `Registry.status("elk.spacing.edgeNode") == :accepted`;
    `Registry.status("elk.hierarchyHandling") == :partial` and
    `Registry.note("elk.hierarchyHandling")` non-empty.
    `spec/elkrb/layout/algorithm_registry_spec.rb` (new): the three
    `sporeOverlap` spellings return the same class;
    `algorithm_info("layered")[:supported_options]` includes
    `"elk.direction"`. `spec/elkrb_spec.rb`:
    `known_layout_options["elk.direction"][:values]` includes `"RIGHT"`;
    `known_layout_options.key?("elk.spacing.nodeNode")`.

Do not touch: any algorithm's option reads (items 09 and 10); `BaseAlgorithm`;
the CLI; `CHANGELOG.md` (item 37).

## Done when

Verified on the branch at `6b9f180`:

- `bundle exec rspec` → **679 examples, 0 failures** (v2 baseline 625).
- `bundle exec ruby -relkrb -e 'p Elkrb.known_layout_options.keys.size'` → 58,
  and `Elkrb::Layout::LayoutEngine.known_layout_options` returns the same
  58-key Hash instead of `[]`.
- All three spellings resolve:
  `bundle exec ruby -relkrb -e 'R=Elkrb::Layout::AlgorithmRegistry; p [R.get("sporeOverlap"), R.get("spore_overlap"), R.get("org.eclipse.elk.sporeOverlap")].uniq'`
  → one class.
- `algorithm_info("layered")[:supported_options]` includes `"elk.direction"`.
- `Elkrb::Options::KVectorChain.parse("(1,2; 3,4)").to_a.size` → 2, and
  `parse("(1,2),(3,4)")` → 2.
- `Registry.status("elk.spacing.edgeNode")` → `:accepted`;
  `Registry.status("elk.hierarchyHandling")` → `:partial` with a non-empty
  note.

Gates, in this order: `thermo-nuclear-review` → `execution-diff`
(**mandatory**) → Codex (max reasoning, read-only, verify-before-critique) →
`copilot-review` last. **No dependency-contract-check** — this slice crosses
no boundary we do not own. Say that in the report rather than skipping it
silently.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's merge-base with `v2`, then on the branch, then
`diff -r` the two dump dirs. The rake exit status is informational; never
chain on it.

INTENDED execution-diff differences, and nothing else:

- `java_elk_sporeOverlap` — the error text changes. The camelCase name now
  resolves, so the case stops failing with
  `Unknown layout algorithm: sporeOverlap` and instead reaches the
  algorithm's own crash.
- `java_elk_sporeCompaction` — same.
- Every other case byte-identical.

Both cases still crash, so their `KNOWN_FAILURES` `no_crash` rows stay. Do not
edit the ledger for them.

The report carries: the full id list with its defaults; the alias table; and
any literal default found inconsistent between two call sites — recorded, not
fixed.

Gate B (Codex `ultra`) ran after this record was written and took six rounds,
approving the branch at `1c0abca`. That is the SHA merged into `v2` by PR #7.
The approval artifact is
`.claude/codex-approvals/s4-options-registry@1c0abca.txt`.

## Files

`lib/elkrb/options/registry.rb` (new), `lib/elkrb.rb`,
`lib/elkrb/layout/layout_engine.rb`, `lib/elkrb/layout/algorithm_registry.rb`,
`lib/elkrb/options/k_vector_chain.rb`,
`spec/elkrb/options/registry_spec.rb` (new),
`spec/elkrb/layout/algorithm_registry_spec.rb` (new), `spec/elkrb_spec.rb`.
