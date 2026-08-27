# 02 — Corpus and CLI harness
Slice S0b · branch `fix/s0b-corpus-cli-harness`

Status: built, **not gated, not merged**. Branch `fix/s0b-corpus-cli-harness`
@ 37bb0ce, 5 commits ahead of `origin/v2`.

**One Blocker is open.** `prune_stale_dumps` in
`spec/cross_validation/corpus_runner.rb` can delete JSON out of directories
the caller never named.

The guard added at 37bb0ce ("harden dump guard") narrows it but does not
close it:

```ruby
return unless File.file?(File.join(outdir, "summary.json"))

keep = corpus.map { |kase| "#{kase.id}.json" } + ["summary.json"]
Dir[File.join(outdir, "*.json")].each do |path|
  File.delete(path) if File.file?(path) && !keep.include?(File.basename(path))
end
```

`summary.json` is in `keep`, which is why it survives in the transcript
below while the sibling directories do not.

`File.file?` treats the path literally. `Dir[]` does not. So a destination
that is a real directory whose *name contains* `*` passes the guard on the
second run, and the `Dir[]` then expands across its siblings.

Measured 2026-08-27:

```
  dump*/      summary.json + live_case.json     (a real directory)
  dumpster/   precious_fixture.json
  dumpyard/   also_precious.json

  prune_stale_dumps("dump*", ["live_case"])

  dump*/      survived
  dumpster/   EMPTY   <- deleted
  dumpyard/   EMPTY   <- deleted
```

An earlier retraction of this Blocker was wrong. It rested on a probe that
used a metacharacter in a path with no matching literal directory, so the
guard returned early and nothing was deleted. One input shape, generalised.

The fix has to compare against a resolved real path, or escape the
destination before it reaches `Dir[]` — `File.file?` and `Dir[]` must not
disagree about what `outdir` means.

Can start: now — this item depends on nothing. It was **planned** as the
first thing to land after 01 (S1); that is no longer what happened. 04, 06,
08 and 11 all merged first while this branch sat ungated, so it now lands
into a `v2` that has moved well past the seed. Three of those four — 06, 08
and 11 — are the ones that gated against this branch's driver uncommitted;
04 needed no execution-diff gate at all.

It was branched from `main` before `v2` existed, then
rebased onto `v2` and force-pushed; that predates the no-rebase rule and is
grandfathered, recorded here, and is the one exception. Blocks the START of 05
(S2, which un-pends this item's `cli_spec` examples and uses its
`cli_runner`/`fake_dot`). Blocks the CLOSE of 03 (S0a, which merges after this
item and rewrites its `corpus_spec` invariant set) — that branch is rooted
on `v2` and built in parallel; only their merges are ordered (`git merge-base
v2 fix/s0a-golden-harness` is a008889). Gates the CLOSE of every
execution-diff-gated item from 05 onward: `rake corpus:dump` is the sole XD
driver.

**That claim used to say no XD gate runs before this item is in the base.
That is not what happened.** 06, 08 and 11 all ran their execution-diff gates
with the driver materialised uncommitted from this branch, and all three
merged first. So the rule as practised is weaker: a gate may run against a
materialised driver, and what 02 actually gates is the point at which that
stops being a manual step. Items from 05 on should not repeat the
workaround — but three already did, and pretending otherwise would make the
next person distrust the rest of this file. Medium (~860
lines, spec-only). Not BREAKING: no `lib/` change, one guard in a spec-side
importer.

## Facts

Measured on `v2` (a008889) unless stated.

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
- `bundle exec rspec` on 22231fd → **729 examples, 0 failures, 16 pending**
  (measured 2026-08-21). Base was 625/0.

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
   chains on the rake exit code. Settled, because `duplicate_ids` and
   `hyperedge` are permanent expected errors until items 11 (S7) and 12 (S8).
   Mark such cases `"expect": "error"` in the wrapper so the exit status
   reflects unexpected regressions, not tracked ones.
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

Done. What was verified:

- `bundle exec rake "corpus:dump[/tmp/corpus_base]"` (quote the brackets — zsh
  globs them) writes one file per case plus `summary.json`. Non-zero exit is
  expected while any case errors; it is not a failure signal.
- `bundle exec rspec spec/cross_validation spec/elkrb/cli_spec.rb` → 0
  failures.
- `bundle exec rspec` on 22231fd → **729 examples, 0 failures, 16 pending**.
- `bundle exec rake validate:import_elkjs` with no `ELKJS_DIR` exits 1 with
  the refusal message (rake aborts when the importer refuses) and leaves
  `spec/cross_validation/fixtures/elkjs/imported_tests.json` byte-identical.

**Everything below this line was recorded at `22231fd`.** The branch has
since moved to `37bb0ce` ("preserve import expectations and harden dump
guard"), so the counts and the importer behaviour recorded below are from
the older SHA and have not been re-measured. Re-run them before the gate.

Gates that were mandatory and what they found:

- **thermo-nuclear** — run on plan and diff.
- **dependency-contract-check** — mandatory, because the whole slice is a
  subprocess boundary. Constructed the real thing: exit-status propagation
  through `Open3.capture3`, `PATH` lookup actually finding the fake `dot`,
  and argv logging surviving shell metacharacters.
- **execution-diff** — not applicable and skipped; nothing under `lib/` or
  `exe/` changes, so there is no runtime behaviour to diff. Said so
  explicitly.
- **Codex** — APPROVE.
- **copilot-review** — run last.
- **Gate A** (orchestrator multi-agent) found 4 Medium findings; all fixed at
  aaf4efb.
- **Gate B** (Codex `ultra` on the exact SHA) round 1 found 2 Medium
  mutation-vacuity findings — the specs passed with the code neutered. Fixed
  with mutation-kill proof. Round 2 on 22231fd: APPROVE, mutations verified
  fatal.

Carried forward, not fixed here: `java_elk_test_importer.rb` does not re-emit
`"expect": "error"` when it regenerates `fixtures/java_elk/imported_tests.json`
(the two rows exist in the committed file today). Whoever next regenerates that
fixture must re-add them or the corpus exit status starts lying.
