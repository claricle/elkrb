# 02 — Corpus and CLI harness
Slice S0b · branch `fix/s0b-corpus-cli-harness`

Status: built, lint-clean, **not gated, not merged**. Branch
`fix/s0b-corpus-cli-harness` @ `23ed0de`, 11 commits ahead of `origin/v2`
(`f6ba3e0`). `origin/v2` was merged in at `bc19cb8`, so it is an ancestor of
the tip. Everything below was measured at `23ed0de` unless it says otherwise.

**The Blocker is fixed, both sides.** The destination side at `1716de0`,
"Scope dump pruning to the directory it was given"; the source side at
`23ed0de`, "glob corpus source dirs literally with base".

## The Blocker, and how it was closed

`prune_stale_dumps` deleted JSON out of directories the caller never named.
The guard at `37bb0ce` narrowed it but did not close it:

```ruby
return unless File.file?(File.join(outdir, "summary.json"))

keep = corpus.map { |kase| "#{kase.id}.json" } + ["summary.json"]
Dir[File.join(outdir, "*.json")].each do |path|
  File.delete(path) if File.file?(path) && !keep.include?(File.basename(path))
end
```

`File.file?` reads a path literally. `Dir[]` globs it. So the two disagreed
about which directory `outdir` meant. Measured 2026-08-27:

```
  dump*/      summary.json + live_case.json     (a real directory)
  dumpster/   precious_fixture.json
  dumpyard/   also_precious.json

  prune_stale_dumps("dump*", ["live_case"])

  dump*/      survived
  dumpster/   its precious_fixture.json was DELETED
  dumpyard/   its also_precious.json was DELETED
```

The fix scopes the glob to the directory itself instead of joining the path
into the pattern:

```ruby
Dir.glob("*.json", base: outdir).each do |name|
  next if keep.include?(name)

  path = File.join(outdir, name)
  File.delete(path) if File.file?(path)
end
```

`base:` takes the directory as a value, not as pattern text, so no byte of
`outdir` can reach the matcher. `File.file?` and `Dir` now agree.

Evidence, at `5c05156`:

- `spec/cross_validation/corpus_runner_prune_spec.rb` pins it. 5 examples,
  each building its own `Dir.mktmpdir` parent so the patterns cannot match
  each other's directories and manufacture a finding.
- Mutation-checked. Put the old `Dir[File.join(outdir, "*.json")]` form back
  and 3 of the 5 go red. Restore it and all 5 pass.

An earlier retraction of this Blocker was wrong. It rested on a probe that put
a metacharacter in a path with no matching literal directory, so the guard
returned early and nothing was deleted. One input shape, generalised.

## The metacharacter rule has two families, not one

Split on whether the pattern still matches the directory it was built from.
The card used to tell only the `*` story. Both halves belong here.

**`*` and `?` DO match their own directory.** They act as a superset. The
intended directory is listed, so its own stale files are pruned correctly, and
siblings' files are quietly added to the delete set on top. That is the
`dump*` transcript above.

**`[...]`, `{...}` and an unclosed bracket do NOT match their own directory.**
The real directory is never listed at all, so the delete set is entirely
foreign. What that costs depends on what sits beside it:

- With a matching sibling present, the glob returns only that sibling's JSON.
  The intended directory keeps its stale dumps and the neighbour loses files
  it never offered.
- With no matching sibling, the glob returns nothing. Nothing is deleted, and
  the intended directory silently keeps every stale dump forever.

Do not write "any metacharacter empties the corpus", and do not write "`*` or
`?` raises duplicate ids". Both are single shapes generalised.

## The class is NOT closed. Six sites, four fixed

Six sites in this branch carry the literal-vs-pattern shape. **Four are
fixed.** The plan claimed four and also called the three `ROOT` globs
deferred, so it contradicted itself. Four are fixed now, and what stayed
deferred is sites 5 and 6, the two importers.

| # | Site | State |
|---|---|---|
| 1 | `corpus_runner.rb` `prune_stale_dumps` | **fixed** at `1716de0` |
| 2 | `corpus_runner.rb` `top_level_fixture_cases` | **fixed** at `23ed0de` |
| 3 | `corpus_runner.rb` `corpus_fixture_cases` | **fixed** at `23ed0de` |
| 4 | `corpus_runner.rb` `imported_cases` | **fixed** at `23ed0de` |
| 5 | `elkjs_test_importer.rb:61` | deferred, reason measured |
| 6 | `java_elk_test_importer.rb:60` | deferred, reason measured |

Sites 2-4 built their pattern from `ROOT`, which is
`File.expand_path("../..", __dir__)` — the checkout path. They only read, and
that was argued as a reason to leave them. It was not one: they feed the site
that deletes. `cases` builds `run`'s corpus, which builds
`prune_stale_dumps`' `keep`.

**That chain was live.** Measured at `5c05156` by extracting the tip into
`/private/tmp/elk[x]root` with a sibling `/private/tmp/elkxroot` holding one
`spec/fixtures/foreign_case.json`:

```
  ROOT = /private/tmp/elk[x]root
  CorpusRunner.cases      => 1 case, and it is "foreign_case"
                             (the real 47 never listed)

  CorpusRunner.run("/tmp/probe_dump") on a directory already holding
  cycle3.json, self_loop.json, simple_graph.json, summary.json

  BEFORE: cycle3.json self_loop.json simple_graph.json summary.json
  AFTER:  foreign_case.json summary.json
```

Every real dump was deleted. That is why sites 2-4 were fixed rather than
carried. `1716de0` closed the destination side of the Blocker; `23ed0de`
closes the source side, routing all three globs through one private
`fixture_paths(dir, pattern)` that passes the directory as `base:`.

Enumeration had to come through unchanged, because the case list is the fixed
list every later slice diffs against. Three measurements say it did:

- `CorpusRunner.cases.map(&:id)` is byte-identical across the fix. 47 ids,
  and the same SHA-1 (`daf0ea1`) before and after.
- A `4f7980f` dump and a `23ed0de` dump compared with `diff -r` agree on all
  48 files.
- The sort-by-whole-path order in `imported_cases` survives. `fixture_paths`
  joins the directory back on before that sort, so it still sorts absolute
  paths. Demonstrated with a temporary real
  `spec/cross_validation/fixtures/elkjs-2/`: glob returns elkjs, elkjs-2,
  java_elk under both the old and the new form, and the shipped sort turns
  both into elkjs-2, elkjs, java_elk.

`spec/cross_validation/corpus_runner_fixture_paths_spec.rb` pins it. 8
examples, each building its own `Dir.mktmpdir` parent, covering both
metacharacter families and the `*/imported_tests.json` directory-component
shape. Mutation-checked: put the old `Dir[File.join(dir, pattern)]` form back
and 6 of the 8 go red. The two that stay green are the plain-name baselines,
where the old form behaves identically. Restore it and all 8 pass.

The two importer sites are deferred with the reason recorded in the plan: all
three external checkouts are absent here, so a fix cannot be
integration-checked against the real corpora, and the java_elk one writes over
a tracked 17-case fixture. It belongs in its own change, run where those
checkouts exist.

## Can start

Now — this item depends on nothing. It was **planned** as the first thing to
land after 01 (S1); that is not what happened. 04, 06, 08 and 11 all merged
first while this branch sat ungated, so it now lands into a `v2` that has
moved well past the seed. Three of those four — 06, 08 and 11 — gated against
this branch's driver uncommitted; 04 needed no execution-diff gate at all.

It was branched from `main` before `v2` existed, then rebased onto `v2` and
force-pushed. That predates the no-rebase rule, is grandfathered, and is the
one exception.

Blocks the START of 05 (S2, which un-pends this item's `cli_spec` examples and
uses its `cli_runner`/`fake_dot`). Blocks the CLOSE of 03 (S0a, which merges
after this item and rewrites its `corpus_spec` invariant set) — that branch is
rooted on `v2` and built in parallel; only their merges are ordered
(`git merge-base v2 fix/s0a-golden-harness` is `a008889`). Gates the CLOSE of
every execution-diff-gated item from 05 onward: `rake corpus:dump` is the sole
XD driver.

**That claim used to say no XD gate runs before this item is in the base. That
is not what happened.** 06, 08 and 11 all ran their execution-diff gates with
the driver materialised uncommitted from this branch, and all three merged
first. So the rule as practised is weaker: a gate may run against a
materialised driver, and what 02 actually gates is the point at which that
stops being a manual step. Items from 05 on should not repeat the workaround —
but three already did, and pretending otherwise would make the next person
distrust the rest of this file.

Medium (~860 lines, spec-only). Not BREAKING: no `lib/` change, one guard in a
spec-side importer.

## Facts

Measured on `v2` (`a008889`) unless stated.

- **No CLI spec exists.** `git cat-file -e v2:spec/elkrb/cli_spec.rb` → *does
  not exist in 'v2'*. `Elkrb::Cli` has never been exercised through a
  subprocess, which is why the RC10 exit-code and stream defects in item 05
  (S2) were invisible (tests-3).
- **`GraphvizWrapper` specs stub the method under test.** Every `#render`
  example that reaches the command stubs `system` —
  `spec/elkrb/graphviz_wrapper_spec.rb:34`, `:40`, `:46`, `:52`, `:60` and
  `:97`. The other four raise on validation before they get that far. Either
  way the shell-injection path is never executed (tests-3).
- **The committed validation report is a foreign artifact.**
  `git show v2:spec/cross_validation/validation_report.json | grep -c mulgogi`
  → **9**. It was generated on another machine under Ruby 3.3.2 and
  lutaml-model 0.7.7, is tracked, is not gitignored, and the runner rewrites
  it on every run (tests-15).
- **The elkjs importer destroys tracked data.** `v2`'s
  `spec/cross_validation/elkjs_test_importer.rb` hardcodes
  `File.expand_path("~/src/external/elkjs")`; each `import_*` returns early
  when the path is missing and `save_test_cases` then writes the empty array
  over the 16 committed cases. `rake validate:import_elkjs` on any other
  machine wipes the fixture (docs-packaging-13).
- **There is no corpus driver.** `v2` ships `validation_runner.rb` +
  `generate_validation_report.rb`, both of which write the report above.
  Nothing enumerates every fixture and dumps canonical layout output, so there
  is nothing for a later slice to diff against (RC15).
- **The corpus is 47 cases**: 3 × `spec/fixtures/*.json`, 11 ×
  `spec/fixtures/corpus/*.json`, 16 × `fixtures/elkjs/imported_tests.json`,
  17 × `fixtures/java_elk/imported_tests.json`. From a checkout of this
  branch:
  ```sh
  bundle exec ruby -e 'require "./spec/cross_validation/corpus_runner"; p CorpusRunner.cases.size'   # => 47
  ```

### The expected-error set at this tip

Three cases error, and all three declare `"expect": "error"`. That is why the
dump exits 0.

- `duplicate_ids` → `Elkrb::ValidationError: duplicate id: a`. Declared in
  `spec/fixtures/corpus/duplicate_ids.json`. **This is not a bug.** Item 11
  (S7) is merged and this raise is the behaviour it shipped on purpose. The
  card used to call it an expected error "until item 11"; item 11 has landed
  and the raise is now permanent and correct.
- `java_elk_sporeOverlap` and `java_elk_sporeCompaction` →
  `NoMethodError: undefined method '-' for nil`, both from
  `lib/elkrb/layout/algorithms/spore_overlap.rb:49` in `overlapping?`.
  Declared in `spec/cross_validation/fixtures/java_elk/imported_tests.json`.

**`hyperedge` does not error.** Its dump status is `ok` and its fixture
carries no `expect` key. The card used to list it as a permanent expected
error "until item 12 (S8)". That has the direction backwards: item 12 is the
thing that will make it raise. Its own step 8 says to add `"expect": "error"`
to `spec/fixtures/corpus/hyperedge.json` once layered raises
`Elkrb::UnsupportedConfigurationException` on `a→[b,c]`. Until then the case
lays out fine.

**The RC14 attribution on the spore cases is wrong at this tip.** The claim is
that `AlgorithmRegistry.normalize_name` does not convert camelCase, so
`sporeOverlap` resolves to nil and `LayoutEngine.layout` raises "Unknown
layout algorithm". Measured:

```sh
Elkrb::Layout::AlgorithmRegistry.get("sporeOverlap")
# => Elkrb::Layout::Algorithms::SporeOverlap
```

It resolves. An empty graph on `sporeOverlap` lays out without raising. The
real failure is arithmetic on a nil coordinate inside the algorithm on the
4-node fixture. `corpus_spec.rb`'s `KNOWN_FAILURES` still files both spore
rows under RC14, and `CLAUDE.md` still repeats the registry story. Neither is
corrected here — item 03 (S0a) rewrites that ledger wholesale.

## Do

1. `spec/support/cli_runner.rb` — `run_elkrb(*args, stdin:, env:)` wrapping
   `Open3.capture3(env, RbConfig.ruby, "-I#{LIB}", "exe/elkrb", *args)` and
   returning `[stdout, stderr, status]`. Subprocess only: never call `Cli`
   methods directly, because the thing under test is the process boundary.
2. `spec/support/fake_dot.rb` — `with_fake_dot { |log_path| … }` writes an
   executable `dot` script into a tmpdir, puts it first on `PATH`, logs argv
   NUL-separated one invocation per line, and touches whatever `-o` names.
   Handle **both** forms elkrb has used: the `-o path` token pair and the
   `-opath` suffix (`v2`'s `graphviz_wrapper.rb:81` emits the suffix form;
   item 05 switches to the pair). Restore `PATH` and `FAKE_DOT_LOG` in an
   `ensure`.
3. `spec/cross_validation/corpus_runner.rb`, replacing `validation_runner.rb`
   and `generate_validation_report.rb`, with `validate:run` in the `Rakefile`
   pointed at it. Enumerate the 47 cases, run each through `Elkrb.layout`
   under a 30 s timeout, write canonical JSON (`JSON.pretty_generate` of a
   deep-sorted Hash, floats rounded to 6 decimals) to `<outdir>/<case>.json`,
   or `{"error": class + message}`. Write `summary.json`. Reseed a fixed
   `srand` before **each** case — force and random call unseeded `Kernel#rand`
   today, so two dumps of identical code would otherwise disagree and every
   later XD gate would be noise.
4. `corpus:dump` **always writes every file**, and its exit status is
   informational only. XD compares dump directories with `diff -r` and never
   chains on the rake exit code. Mark a permanently-failing case
   `"expect": "error"` in its wrapper so the exit status reflects unexpected
   regressions, not tracked ones. Three cases carry that marker today; see
   "The expected-error set at this tip".
5. `spec/fixtures/corpus/` inputs, each a wrapper `{"algorithm":, "graph":}`:
   `self_loop`, `sizeless_node`, `no_children_key`, `duplicate_ids` (two
   children `a`), `hyperedge`, `cycle3`, `port_id_edges`,
   `labelled_only_text`, `compound_unsized`, `compound_declared_size`,
   `stale_sections` (edge with a pre-filled `sections` array); plus
   `bom.elkt` and `garbage.txt` for the CLI specs only, and
   `spec/fixtures/x.dot` for the `render` spec.
6. `spec/cross_validation/corpus_spec.rb` — for every case × its algorithm, a
   "does not raise" example and a minimal **inline** invariant set (finite
   coordinates, ids preserved). Inline, not shared: item 03 (S0a) is not built
   yet and replaces this set with its `INVARIANTS` list when it merges.
   `KNOWN_FAILURES = { [case, check] => "RCn" }` authored against `v2`, plus a
   guard example that iterates the ledger and fails when a listed check starts
   passing — so a slice that fixes something must edit the ledger.
7. Ledger contents, settled by decision 5 and by 01 (S1) already being in
   `v2`: **no** `no_crash` rows for `self_loop`, `sizeless_node`,
   `no_children_key`. Their `invariants` rows stay under `D5`
   (`["sizeless_node", "invariants"] => "D5"`,
   `["no_children_key", "invariants"] => "D5"`) until item 03's
   `omit_size_for_unsized_input` matcher lands, because slice 1 is a read-site
   guard and the element itself still carries nil width/height.
8. `spec/elkrb/cli_spec.rb` — `version` exits 0 and prints `Elkrb::VERSION`;
   `algorithms` exits 0; `layout spec/fixtures/simple_graph.json` exits 0 with
   JSON on stdout; then four `pending "RC10"` examples for item 05 to un-pend:
   `--verbose` stdout still parses, no-FILE exits non-zero, `layout
   missing.json` gives empty stdout + non-empty stderr + exit 1, and the
   `render … -o "a;touch PWNED;.svg"` case under `with_fake_dot` run with
   `chdir: tmpdir` sees the literal path as one argv element and leaves no
   `PWNED`. Use an absolute `-o` under the tmpdir — a relative one would let
   the pre-item-05 injection touch the repo worktree.
9. Later slices add their CLI examples in their own `describe "<slice>"`
   section or a new `spec/elkrb/cli/<topic>_spec.rb`. Never edit an existing
   example block, so parallel slices touch disjoint hunks.
10. `Rakefile` gains `corpus:dump[dir]`. `elkjs_test_importer.rb` refuses to
    write when the checkout is missing or 0 cases were found: print why, exit
    1, honour `ENV["ELKJS_DIR"]` with `~/src/external/elkjs` as the default.
    Delete `spec/cross_validation/validation_report.json` and add
    `/spec/cross_validation/validation_report.json` to `.gitignore` (append at
    EOF — item 04 puts `.claude/` next to `.idea/`/`.vscode/` instead, so the
    two do not collide).
11. Specs first. This slice *is* specs: write `cli_spec` and `corpus_spec`,
    watch them fail for the right reason (`NameError`, no helper), then build
    the helpers.

## Done when

Re-measured at `23ed0de`. Each command and its exact output:

1. `bundle exec rake "corpus:dump[/tmp/corpus_base]"` (quote the brackets —
   zsh globs them) →
   ```
   corpus: 44 ok, 3 error, 0 timeout (47 total)
   exit status 0
   48 files written (47 cases + summary.json)
   ```
   **Exit 0 is the healthy signal.** All three errors declare `"expect"`, so
   none counts as unexpected. A non-zero exit means a failure that was *not*
   declared — a real regression. The card used to predict a non-zero exit here
   and call it expected; that would make the next reader think the harness had
   broken.

   `corpus_runner.rb` is what makes that true: `unexpected_failure?` counts
   only an undeclared failure, `run` writes it to
   `summary["unexpected_failures"]`, `exit_code` maps it, and the CLI
   entrypoint exits on it.

2. `bundle exec rspec spec/cross_validation spec/elkrb/cli_spec.rb` →
   **128 examples, 0 failures, 17 pending**.

3. `bundle exec rspec` → **895 examples, 0 failures, 17 pending**.
   (`5c05156` was 887/0/17; `22231fd` was 729/0/16; the base before this
   branch was 625/0. `23ed0de` adds the 8 `fixture_paths` examples.)

4. `bundle exec rake validate:import_elkjs` with no `ELKJS_DIR` → exit 1 with
   the refusal message ("elkjs checkout not found at … - refusing to overwrite
   …"), rake aborting on it, and the fixture untouched:
   ```
   before  212dbc9f9573067ecc5b07492a44c01b00867d31eae984ed53f9b12c9258e872
   after   212dbc9f9573067ecc5b07492a44c01b00867d31eae984ed53f9b12c9258e872
           spec/cross_validation/fixtures/elkjs/imported_tests.json
   ```

5. `bundle exec rubocop --ignore-parent-exclusion` → **127 files inspected, no
   offenses detected**. Cleared in code at `1df5bef` and `5c05156`: no new
   `.rubocop_todo.yml` entries, no `rubocop:disable` comments, no widening of
   `.rubocop.yml`. In this nested worktree `--ignore-parent-exclusion` is
   required, because the worktree sits under a checkout whose `main` lacks
   `.rubocop_todo.yml`.

6. Neither the lint work nor the source-side glob fix changed any output. A
   pristine `1716de0` dump and a `5c05156` dump compared with `diff -r` are
   byte-identical across all 48 files, and so are a `4f7980f` dump and a
   `23ed0de` dump.

## Gates

**The old gate record is history. None of it is a live approval.** Gate A ran
before the fixes committed at `aaf4efb`. Gate B round 1 ran before the fixes
at `22231fd`. Only Gate B round 2 ran on `22231fd` itself. The tip is now
`23ed0de`, six commits past that, so every one of them is invalidated by
arithmetic.

What they found, for the record:

- **thermo-nuclear** — run on plan and diff.
- **dependency-contract-check** — mandatory, because the whole slice is a
  subprocess boundary. Constructed the real thing: exit-status propagation
  through `Open3.capture3`, `PATH` lookup actually finding the fake `dot`, and
  argv logging surviving shell metacharacters.
- **execution-diff** — skipped at the time, on the ground that nothing under
  `lib/` or `exe/` changed. Said so explicitly.
- **Codex** — APPROVE, on `22231fd`.
- **copilot-review** — run last.
- **Gate A** (orchestrator multi-agent) — 4 Medium findings, all fixed at
  `aaf4efb`.
- **Gate B** (Codex `ultra` on the exact SHA) — round 1 found 2 Medium
  mutation-vacuity findings: the specs passed with the code neutered. Fixed
  with mutation-kill proof. Round 2 on `22231fd`: APPROVE, mutations verified
  fatal.

### This run's gates — TO BE FILLED

<!-- Placeholder. Fill from the gate artifacts under
     .claude/gate-runs/<branch-leaf>@<sha>.md and
     .claude/codex-approvals/<branch>@<sha>.txt once they exist for the tip.
     A gate with no artifact did not run. -->

| Gate | SHA | Verdict | Findings |
|---|---|---|---|
| thermo-nuclear | — | NOT RUN | — |
| dependency-contract-check | — | NOT RUN | — |
| execution-diff | — | NOT RUN | — |
| Codex | — | NOT RUN | — |
| copilot-review | — | NOT RUN | — |

## Carried forward, not fixed here

- `java_elk_test_importer.rb` does not re-emit `"expect": "error"` when it
  regenerates `fixtures/java_elk/imported_tests.json`. The two rows exist in
  the committed file today. Whoever next regenerates that fixture must re-add
  them or the corpus exit status starts lying.
- Sites 5 and 6 above, the two importers: their checkout path still reaches a
  glob pattern unescaped. Deferred for the measured reason above — neither
  external checkout exists here, so a fix cannot be integration-checked
  against the real corpora.
- `corpus_spec.rb` files both spore rows under RC14, and `CLAUDE.md` repeats
  the registry-resolution story. The measurement says otherwise. Item 03 (S0a)
  rewrites that ledger.
