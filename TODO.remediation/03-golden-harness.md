# 03 — elkjs golden harness
Slice S0a · branch `fix/s0a-golden-harness`

Status: built, **not gated, not merged**. Branch `fix/s0a-golden-harness` @
e8c7e69, 11 commits ahead of `origin/v2`. One step is deliberately
outstanding: the `corpus_spec` reconciliation in step 7 below cannot be
written on this branch, because the file it edits arrives with 02. It happens
at merge.

Can start: now — the build ran in parallel with 02 (S0b), off `v2`. It cannot
CLOSE until 02 lands: step 7 rewrites `spec/cross_validation/corpus_spec.rb`,
which 02 creates, and flips its `D5` ledger rows. It no longer blocks 04 —
04 merged ahead of both harness items (PR #6), so that close order is spent.
Blocks the START of every item that claims elkjs parity by un-pending a
golden: 12 (S8), 13 (S9), 14 (S10), 16 (S11), 17 (S12), 18 (S13), 19 (S13b),
20 (S14), 21 (S15), 22 (S16), 23 (S17), 31 (S25a). Also blocks the CLOSE of 24
(S18): this item authors the `spore_overlap4` golden and 24 is where its fate
is settled. Large (~6,300 lines, mostly generated JSON; spec-only). Not
BREAKING: nothing under `lib/` changes.

## Facts

- **The compatibility suite asserts nothing.**
  `spec/elkrb/elkjs_compatibility_spec.rb` checks node counts, that x/y are
  Numeric and `>= 0`, and edge wiring. A layout that piles every node at the
  origin passes all of it (tests-1). `README.adoc:28-29` claims "verifiable
  compatible in specs" on the strength of that file.
- **Real output diverges from elkjs 0.11.0 on the very fixtures it uses.**
  On `spec/fixtures/elkjs_basic.json`, elkjs 0.11.0 gives 104×104 with
  n1(12,17) n2(62,12) n3(62,62). elkrb on `v2` gives 104×144 with n1(12,12)
  n2(12,102) n3(62,102) — layered stacks top-down with a 60px gap and ignores
  `elk.direction` (tests-1, layered-5, elk-compat-4):
  ```sh
  bundle exec ruby -relkrb -rjson -e 'r=Elkrb::Layout::LayoutEngine.layout(JSON.parse(File.read("spec/fixtures/elkjs_basic.json")),{}); p [r.width, r.height]; p r.children.map{|c|[c.id,c.x,c.y]}'
  ```
- **The layered phase classes have no specs at all.**
  ```sh
  git grep -l 'CycleBreaker\|LayerAssigner\|NodePlacer' v2 -- spec/   # no hits
  ```
  (layered-17). Nor do force, stress, box, random or fixed (force-family-18).
- **No spec pushes an ELK-style key through the pipeline and asserts an
  effect**, and none compares a coordinate to an elkjs reference
  (pipeline-20).
- The environment can generate goldens: node v22.23.1, npm 10.9.8, elkjs
  0.11.0 runs locally. Node is needed to *generate*, never to *check*.
- On this branch, `bundle exec rspec` → **751 examples, 0 failures, 30
  pending** (measured 2026-08-21). Base was 625/0.
- All 30 golden cases are pending today: 12 × RC2, 14 × RC7, 2 × RC5, 2 × RC8.
  ```sh
  git show fix/s0a-golden-harness:spec/elkrb/golden_spec.rb | grep -c '    pending "'
  ```

## Do

1. `spec/support/elkjs_golden/` — `package.json` pinning `"elkjs": "0.11.0"`
   exactly, `package-lock.json`, `.gitignore` (`node_modules/`), and
   `generate.js`. For each `spec/fixtures/golden/inputs/<case>.json` (shape
   `{"options": {…call-level layoutOptions…}, "graph": {…ELK JSON…}}`) run
   `new ELK().layout(graph, {layoutOptions: options})` through
   `elkjs/lib/elk.bundled.js`, strip every `$H` key, round floats to 6
   decimals, and write `spec/fixtures/golden/expected/<case>.json`. On an
   elkjs exception write `{"error": "<message>"}`. Write
   `spec/fixtures/golden/MANIFEST.json` = `{elkjs, node, generated, cases}`.
   The pin is settled: 0.11.0 is the README's target, and a bump is a
   separately reviewed rebaseline.
2. `spec/support/golden_helper.rb` — `golden_input(name)` → `{graph:,
   options:}`, `golden_expected(name)`, and the matcher
   `match_elkjs_golden(name, tier:, fields: %i[nodes sections labels ports
   graph])`. Three tiers, settled:
   - `:exact` — every compared number within 1e-6. A numeric field missing on
     one side compares as 0.0 (elkjs writes `width:0`, elkrb omits it);
     record that rule in the helper.
   - `:structural` — graph width/height within 1px, every edge section
     start/end on the border of its source/target node rectangle or port
     within 1px, per-layer membership and order equal for layered cases
     (group by rounded x for RIGHT, y for DOWN).
   - `:smoke` — same node ids, finite coordinates.
   Compare recursively by id; report the first 10 differences as
   JSON-pointer-style paths.
3. Invariant matchers, **one per file** under `spec/support/invariants/`, each
   self-registering. `spec/support/invariants.rb` holds only
   `INVARIANTS = []`; each matcher file requires it, defines the matcher, and
   ends with `INVARIANTS << :<name>`. Later items add a file and never edit a
   central list, so parallel slices do not collide. Matchers:
   `have_finite_coordinates`, `preserve_ids_and_endpoints(input_hash)`,
   `have_no_overlapping_siblings` (axis-aligned, strict overlap only),
   `contain_children_within_bounds(padding = 0)`, `be_deterministic(&block)`,
   `omit_size_for_unsized_input(input_hash)`.
4. `omit_size_for_unsized_input` pins decision 5 and its exemption is
   settled, not an option: every **leaf** node or label with no width/height
   in the input has none in the output; a node **with children** is exempt,
   because a compound always gets a computed size — that is ELK's behaviour
   and item 14's (S10) job. 02's `compound_unsized.json` has exactly such a
   node and item 14 asserts 104×54 for it.
5. `spec/elkrb/golden_spec.rb` — **one `it` block per case**, never a
   one-line-per-case table, so later items edit disjoint hunks. Each block
   runs `Elkrb.layout(golden_input(name)[:graph], golden_input(name)[:options])`
   and matches. Call `pending` *after* the layout and the matcher have both
   run, so a crash in either is a real failure rather than a swallowed
   pending. Every failing example carries `pending: "RCn: <one line>"` — use
   `pending`, never `skip`, so a slice that fixes something without
   un-pending fails the suite.
6. `Rakefile` — `golden:generate` (checks `npm ci --prefix
   spec/support/elkjs_golden` ran; runs `generate.js` into a tmp dir; aborts
   with a clear message if `node` or elkjs is missing; never writes partial
   output into the committed tree) and `golden:check` (generate into a tmp
   dir, `diff -r` against the committed expected files, non-zero on drift).
   `MANIFEST.json` drift compares `elkjs` and `cases` only — `node` and
   `generated` are machine- and time-specific.
7. **Outstanding at merge.** In `spec/cross_validation/corpus_spec.rb` (02's
   file) replace the local inline `assert_layout_invariants` set with
   iteration over `INVARIANTS`, and flip the two `D5` ledger rows
   (`["sizeless_node", "invariants"]`, `["no_children_key", "invariants"]`)
   now that `omit_size_for_unsized_input` asserts the rule properly. This
   branch starts from `origin/v2` and does not contain that file, so the edit
   is not on 09a5186 — verify with `git diff --stat a008889..fix/s0a-golden-harness`
   (84 files, no `corpus_spec.rb`). Do it in the merge that puts 03 on top of
   02, and re-run 02's ledger guard example.
8. `.github/workflows/golden.yml` — ubuntu, plain `bundle install` (no
   `Gemfile.lock` is committed in this gem and `Gemfile.lock` is gitignored;
   do not add one), running rspec over the **committed** goldens. No Node, no
   npm, no network, no regeneration. Making it a required check needs repo
   admin and is a maintainer task.
9. `spec/spec_helper.rb` loads `support/**/*.rb`, excluding `*_spec.rb` so the
   matchers' own specs are not double-required.
10. Specs first: the harness self-test. Hand-write a synthetic expected file
    whose one node x differs by 0.5 from a synthetic result; assert
    `tier: :exact` fails and `tier: :structural` passes. Then the golden_spec
    examples.

**Cases (30).** Inputs are tiny, 30×30 nodes unless stated. Non-layered cases
pin `elk.algorithm` in the graph's own `layoutOptions`. Layered: `chain2`,
`chain3`, `fan_out`, `fan_in`, `diamond`, `cycle3`, `self_loop`, `long_edge`,
`ports_simple`, `labeled_node`, `labeled_node_placement`, `compound_chain`,
`compound_nested`, `direction_down`, `spacing_override`, `sizeless`,
`two_components`, `hyperedge` (records the elkjs error). Other algorithms:
`box3`, `box_mixed`, `box_aspect`, `fixed2`, `mrtree3`, `mrtree7`,
`radial_star5`, `rect6`, `force_tri`, `stress_path4`, `random3`,
`spore_overlap4`. Do **not** author `disco` or `topdownpacking` goldens —
elkjs 0.11.0 has no such algorithms and throws
`UnsupportedConfigurationException`.

**Where a case's option goes** — settled per case, recorded in the input file.
An option that must reach a child element (`labeled_node_placement`) goes on
the node itself or in call-level `options`; a root-level
`elk.nodeLabels.placement` leaves the label at (0,0) in elkjs. Root-only
options (`direction_down`, `spacing_override`, `box_aspect`, algorithm pins)
go in the root graph's `layoutOptions`.

## Done when

Done, except step 7. What was verified:

- `bundle exec rspec spec/elkrb/golden_spec.rb` → 0 failures, 30 pending.
- `bundle exec rspec` on 09a5186 → **751 examples, 0 failures, 30 pending**.
- `npm ci --prefix spec/support/elkjs_golden && bundle exec rake golden:check`
  → exit 0. Local only; `npm ci` needs network.
- `git status` shows no `node_modules`.
- 13 cases are registered at `tier: :exact`, 17 at `tier: :structural`:
  ```sh
  git show fix/s0a-golden-harness:spec/elkrb/golden_spec.rb | grep -o 'tier: :[a-z]*' | sort | uniq -c
  ```

Gates that were mandatory and what they found:

- **thermo-nuclear** — run on plan and diff.
- **dependency-contract-check** — mandatory, and it constructed the real
  subprocess: `node` missing gives a clear abort, an elkjs exception writes
  the `{"error"}` file, and elkjs's output field names map 1:1 onto the
  model's JSON mapping (`sections[].id`, `startPoint`/`endPoint`/`bendPoints`,
  `incomingShape`/`outgoingShape`). `container` and `$H` are stripped because
  the model has no attribute for them yet.
- **execution-diff** — not applicable and skipped; no runtime change. Said so
  explicitly.
- **Codex** — APPROVE.
- **copilot-review** — run last; hardened the generator's error handling.
- **Gate A** found 1 Blocker, 4 High and 3 Medium; all fixed — per-node
  geometry plus normalised position, proven by mutation.
- **Gate B** round 1 found 1 High (the `:exact` tier accepted rewired edges)
  and 2 Medium; fixed with neuter-and-restore proof. Round 2: APPROVE.

Findings this item raised for later items, recorded so nobody re-derives them:

- **Item 18 (S13) has a design conflict.** Real elkjs anchors port edges at
  the port **border**, not its centre — proven here against the committed
  `ports_simple` golden. The S13 card says centre. elkjs wins; reconcile when
  18 runs.
- **Three goldens have no owner.** `sizeless`, `two_components` and
  `spore_overlap4` are committed but no later item claims to promote them off
  `pending`. Assign them before 35 (S27b) closes, or they stay pending
  forever and the harness lies by omission.
- `golden.yml` runs `spec/elkrb/golden_spec.rb spec/support`, not
  `spec/cross_validation` as originally specified: on this branch
  `spec/cross_validation` has no specs (02 owns it) and every golden_spec
  example is pending, so neither could fail from a real comparator bug.
  `spec/support` holds the comparator's own specs, which are not pending and
  do fail on a regression. Add `spec/cross_validation` back to that command
  once 02 is merged.
