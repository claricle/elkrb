# 30 — README and examples
Slice S24 · branch `fix/s24-readme-examples`

Can start only after items 06 through 23 are merged — that is S3 through S17,
with 07 (S3b) and 15 (S10b) inside the range. The README describes the API,
the coordinates and the option semantics those slices settle, so writing it
earlier means rewriting it. 07 in particular must be in first: it rewrites the
`LayoutOptions.new` sites in `examples/*.rb`, which this item then edits for
content. The direct blockers are 15 (S10b), 17 (S12), 19 (S13b), 21 (S15), 22
(S16) and 23 (S17) — each names this item; the rest of the range reaches it
through them. Blocks the START of 37 (S30) — S30 refreshes the README after
the last command and the last behaviour land, and it cannot refresh a README
that has not been written. Medium (~250 lines). Not BREAKING — docs and
examples only.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree. `README.adoc`
is 1028 lines.

Every Ruby usage example names a constant that does not exist
(elk-compat-21; pipeline-16; gap3-13). `Elkrb::LayoutEngine.new` appears
at `README.adoc:217`, `:264`, `:342`, `:386` and `:401`, with prose at
`:193`. The class is `Elkrb::Layout::LayoutEngine`, it has class methods
only, and the public entry point is `Elkrb.layout`, which returns an
`Elkrb::Graph::Graph`. `:221-223` and `:649-652` then index the result as
a Hash (`result[:children][0][:x]`). A reader copying the first example
cannot get past line one.

3 of 7 examples fail on `v2` (docs-packaging-11). Measured by running
each with `bundle exec ruby -Ilib examples/<f>.rb`:

| example | exit | first error |
|---|---|---|
| `dot_export_demo.rb` | 0 | — |
| `hierarchical_graph.rb` | 1 | SyntaxError — truncated mid-array at `:19` |
| `layout_constraints_demo.rb` | 0 | — |
| `port_constraints_demo.rb` | 1 | `:53` `undefined method 'layout'` (it is a class method) |
| `self_loop_demo.rb` | 0 | — |
| `simple_graph.rb` | 1 | `:11` `undefined method 'new' for module Elkrb::Graph` |
| `spline_routing_demo.rb` | 0 | — |

The audit recorded 5 of 7 failing at 6ac367c; slice 1's crash guards
fixed `dot_export_demo` and `self_loop_demo`. Re-measure before writing —
items 06 through 23 will have moved this table again.

`examples/dot_export_demo.rb:123-124` writes `output_graph.dot` into the
current working directory, so running it from a checkout drops an
untracked file in the repo root.

`examples/hierarchical_graph.rb` has never parsed —
`ruby -c examples/hierarchical_graph.rb` fails on the initial commit — and
item 04 (S28) excluded it in `.rubocop_todo.yml` to get a green lint bar.
Fixing the file means deleting that exclusion in the same PR.

Nothing runs the examples: no README, Rakefile, CI job or spec
references `examples/`. They ship in the gem.

Compatibility claims are unbacked (docs-packaging-15). `README.adoc:96`
says "Full elkjs v0.11.0 compatibility" and
`spec/cross_validation/README.md:132` says "elkjs Compatibility: 100% ✅".
Before item 03 (S0a) landed there was no coordinate comparison anywhere;
after it, parity is exactly what the golden tiers say it is.

Links point at files that do not exist (docs-packaging-14).
`README.adoc:811` links `docs/PERFORMANCE.adoc` and `:830` links
`docs/MIGRATION_FROM_ELKJS.adoc`; the repository has no `docs/`
directory at all — `git ls-tree -d --name-only a008889 docs` prints
nothing.
Four more guides are referenced in AsciiDoc comments at `:757`, `:772`,
`:787` and `:804` and none exist either.

`rake benchmark:report` crashes (docs-packaging-12).
`benchmarks/generate_report.rb:15` writes `docs/PERFORMANCE.adoc` with no
`FileUtils.mkdir_p("docs")` first, and `README.adoc:975`/`:987` tell the
reader to run it.

The performance section is contradicted by the gem's own benchmark
(docs-packaging-16). `README.adoc:816-818` classes force at 50-500 ms;
the committed `benchmarks/results/elkrb_summary.json` — generated from
elkrb 0.4.3 on 2025-10-28 — records force at 4.54 s on 100 nodes and
timeouts at 200.

The CLI section documents 2 of 8 commands (cli-security-14;
docs-packaging-20). `README.adoc:908` onwards covers `layout` and
`algorithms` only:

```sh
grep -c 'elkrb diagram\|elkrb convert\|elkrb render\|elkrb validate\|elkrb batch' README.adoc
# 0
```

The CLI registers 8 commands at `v2` — `layout`, `algorithms`, `diagram`,
`convert`, `render`, `validate`, `batch`, `version` (`lib/elkrb/cli.rb`
`desc` lines at `:16`, `:59`, `:76`, `:99`, `:112`, `:127`, `:138`,
`:153`). The `elkrb algorithms` sample at `:926-961` lists 6 algorithms;
`AlgorithmRegistry.available_algorithms.size` is 15.

`lib/elkrb.rb:60` says "It implements 12 layout algorithms".

`README.adoc:915` shows `elkrb layout input.yml --output result.yml`,
which writes JSON today. That inference is item 36's (S29) — this item
documents whichever behaviour is merged when it lands.

Badges are wrong (docs-packaging-19). `README.adoc:4` uses
`github/license/metanorma/elkrb` and `:5` uses
`metanorma/elkrb/actions/workflows/test.yml`; the repository is
`claricle/elkrb` and the workflows are `rake.yml`, `release.yml` and
item 03's `golden.yml`.

## Do

Everything below is settled — do not re-decide.

1. Re-measure the examples table and the CLI command list before writing
   a word. Items 06 through 23 moved both; the numbers in Facts are the
   `v2` baseline, not the state at merge time.
2. Rewrite every Ruby usage example around `Elkrb.layout(hash_or_graph,
   **globals)` returning a `Graph`, read with attribute readers
   (`result.children[0].x`). Show graph-carried `layoutOptions` as the
   primary pattern — that is what item 09's precedence makes canonical —
   and call-level options as globals. Delete the `Elkrb::LayoutEngine.new`
   form and the Hash-indexed result at `:221-223` and `:649-652`.
3. Print the values the code actually produces. Run each snippet and
   paste its real output; the current expected values at `:221-223`
   (0.0, 0.0, 150.0) were never true.
4. Include the options table from `docs/OPTIONS.adoc` by reference. Item
   37 (S30) generates that file from the registry. Until 37 lands, point
   the include at a placeholder committed in this PR with a one-line TODO
   that 37 removes. Do not hand-write an options table — a hand list is
   exactly what drifts.
5. Document every CLI command that exists at merge time, with its flags.
   `options` arrives in item 36 (S29); if 36 has not merged, do not
   document it and let 37 refresh the section.
6. State the compatibility boundary honestly: "format-compatible with
   elkjs 0.11.0; coordinate parity per the tiers in
   `spec/elkrb/golden_spec.rb`." Delete "Full elkjs v0.11.0
   compatibility" at `:96` and "elkjs Compatibility: 100%" at
   `spec/cross_validation/README.md:132`. Name the layout-quality
   boundary too: layered fan-out stays structural because Brandes-Köpf is
   deferred (decision 7).
7. Fix the badges at `:4-5` to `claricle/elkrb` and to a workflow that
   exists.
8. Replace the performance section with the measured table, or delete it.
   Do not leave numbers the repo's own benchmark contradicts.
9. Fix `benchmarks/generate_report.rb:15`: `require "fileutils"` and
   `FileUtils.mkdir_p("docs")` before the write — the sibling
   `generate_validation_report.rb` already does this.
10. Remove the dead links at `:757`, `:772`, `:787`, `:804` and `:811`.
    Keep `:830`'s `docs/MIGRATION_FROM_ELKJS.adoc` link only because item
    37 creates that file; if 37 has not merged, this item's placeholder
    covers it the same way as step 4.
11. Set the algorithm count from
    `AlgorithmRegistry.available_algorithms.size`, not a literal, and fix
    `lib/elkrb.rb:60`.
12. Make every `examples/*.rb` run. Restore
    `examples/hierarchical_graph.rb` (it also calls the nonexistent
    `Elkrb::Graph.new`, so restoring the truncated array is not enough)
    and delete item 04's `.rubocop_todo.yml` exclusion for it in the same
    PR. Make `examples/dot_export_demo.rb:123-124` write to a tmp path so
    nothing lands in the repo root.
13. Add `spec/examples_spec.rb`: run each example via `Open3` with
    `chdir: Dir.mktmpdir` and assert exit 0. That is what stops them
    rotting again.
14. Fix the `spec/cross_validation/` and `benchmarks/` READMEs where they
    state something the code no longer does.

Do not touch: `LICENSE`, `CHANGELOG.md`, `docs/OPTIONS.adoc`,
`docs/COMPATIBILITY.adoc`, `docs/MIGRATION_FROM_ELKJS.adoc`, `sig/`, or
the gemspec — every one of those is item 37 (S30).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- `bundle exec rspec spec/examples_spec.rb` is green: all 7 examples exit
  0, run from a tmp cwd.
- `git status` is clean after the examples run — no `output_graph.dot`.
- `ruby -c examples/hierarchical_graph.rb` prints `Syntax OK`, and
  `grep -n hierarchical_graph .rubocop_todo.yml` returns nothing.
- Every Ruby snippet in `README.adoc` runs as written and prints the
  values the README claims. Prove it by extracting and running them; item
  37 turns that into `spec/readme_spec.rb`.
- `grep -n 'Elkrb::LayoutEngine' README.adoc` returns nothing.
- `grep -c 'elkrb diagram\|elkrb convert\|elkrb render\|elkrb validate\|elkrb batch' README.adoc`
  is non-zero, and every command the CLI registers has a section.
- `grep -n '100%\|Full elkjs' README.adoc spec/cross_validation/README.md`
  returns nothing.
- Every `link:docs/…` in `README.adoc` resolves to a committed file (or
  to this item's placeholder, with the TODO naming item 37).
- `bundle exec rake benchmark:report` completes on a checkout with no
  `docs/` directory.
- `grep -rn '12 layout algorithms\|12 algorithms' README.adoc lib/`
  returns nothing.

Mandatory gates, in order: `thermo-nuclear-review` → Codex (max
reasoning, read-only, verify-before-critique) → `copilot-review` last.
`copilot-review` matters most here: it is the pass that reads prose
blind and catches the stale sentence nobody re-read.

No dependency-contract-check and no execution-diff — this item changes
no library code beyond `lib/elkrb.rb:60`'s docstring and
`benchmarks/generate_report.rb`. Say so explicitly in the report rather
than skipping silently, and confirm it: `git diff --stat` shows no change
under `lib/elkrb/`.

The report carries no `## Breaking` section. List instead every claim you
removed and what replaced it, so item 37 can carry the survivors into the
generated docs.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
