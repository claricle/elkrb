# 04 — Lint and CI hygiene
Slice S28 · branch `fix/s28-lint-ci`

Status: **merged into `v2`** via PR #6, at 11140a6. Closed.

Can start: now — this branch is one commit on `v2` and needs nothing from the
other two. It cannot CLOSE until 02 (S0b) and 03 (S0a) land: 02 appends to
`.gitignore` at EOF while this item inserts `.claude/` mid-file, so landing
second avoids a conflict, and 03 owns `golden.yml`, which must not be
duplicated here. Blocks nothing structurally, but it moves the bar: from this
item on, "green" means `bundle exec rake` (spec **and** rubocop), not `bundle
exec rspec`. Every item from 05 (S2) onward reports against that bar, which is
why this lands right after the two harness items. Small (4 files, ~350 lines,
337 of them generated). Not BREAKING: no `lib/` change.

## Facts

Measured on `v2` (a008889).

- **RuboCop cannot run at all.** `.rubocop.yml:5` lists `.rubocop_todo.yml` in
  `inherit_from`, and that file does not exist:
  ```sh
  bundle exec rubocop            # Configuration file not found: .../.rubocop_todo.yml
  git cat-file -e v2:.rubocop_todo.yml   # fatal: path does not exist in 'v2'
  ```
  So the lint state of this repo has never been measured, let alone gated.
- **The default rake task is spec-only.** `git show v2:Rakefile` line 8:
  `task default: :spec`.
- **CI runs `bundle exec rake` through an inherited workflow.**
  `.github/workflows/rake.yml` is 15 lines holding one job, which delegates
  to `metanorma/ci/.github/workflows/generic-rake.yml@main`. That means
  changing the default task is the whole CI change — no new workflow file is
  needed, and adding a second rubocop invocation next to the inherited one
  would be wrong.
- **`.rubocop.yml` is cimas-generated and must never be edited.** Its header
  says so, and it already inherits the todo file, which is the intended
  mechanism.
- **`examples/hierarchical_graph.rb` does not parse.** It has been truncated
  mid-literal since the initial commit ace9eea and ships in the gem
  (docs-packaging-11). `Lint/Syntax` has no per-cop `Exclude`, so the only way
  to silence it is `AllCops: Exclude`.
- **The remote inherit is a network fetch.** `.rubocop.yml:4` pulls
  `https://raw.githubusercontent.com/riboseinc/oss-guides/main/ci/rubocop.yml`
  at run time with a 24 h cache. That is the cimas/metanorma convention for
  every gem in the ecosystem and is accepted as-is — CI needs network for
  `bundle install` anyway.
- On this branch, `bundle exec rake` → **625 examples, 0 failures** and
  **111 files inspected, no offenses detected** (measured 2026-08-21).

## Do

1. `Rakefile`: `require "rubocop/rake_task"`, `RuboCop::RakeTask.new`, and
   `task default: %i[spec rubocop]`. That single line is what puts rubocop in
   CI, through the inherited `generic-rake` workflow.
2. Pass `--ignore-parent-exclusion` to the rake task. A worktree checked out
   under a directory that itself has a `.rubocop.yml` — which is exactly how
   this effort's worktrees are laid out — would otherwise inherit that
   parent's `AllCops: Exclude` and its own `inherit_from` chain. The flag
   keeps every checkout self-contained.
3. Generate `.rubocop_todo.yml` with `bundle exec rubocop --auto-gen-config
   --no-exclude-limit` and commit it. `--no-exclude-limit` is settled and
   load-bearing: without it RuboCop stops listing files past a threshold and
   writes a repo-wide `Max:` bump or a blanket disable instead, which
   suppresses future offences in files that are clean today. Per-file
   `Exclude:` lists only.
4. Never edit `.rubocop.yml`. It is cimas-generated and already inherits the
   todo.
5. Re-add the `AllCops: Exclude` block for `examples/hierarchical_graph.rb`
   after any future `--auto-gen-config` run, with `inherit_mode: merge:
   Exclude` so it stacks on the remote base config's own excludes rather than
   replacing them. Regeneration overwrites the whole file and would silently
   drop it. Say that in a comment at the top of the block — item 30 (S24)
   fixes the file itself.
6. Pin rubocop in the `Gemfile`: `gem "rubocop", "~> 1.89"`. The todo was
   generated under 1.89.0; a later release can add or change cops and
   invalidate it, so the ratchet is not reproducible unpinned.
7. `.gitignore` gains `.claude/` **next to `.idea/`/`.vscode/`** (`v2`'s
   `.gitignore:58-60`), not at EOF — 02 appends
   `/spec/cross_validation/validation_report.json` there and the two would
   collide.
8. Do **not** add `golden.yml` here. Item 03 owns it.

## Done when

Done. What was verified:

- `bundle exec rake rubocop` → 111 files inspected, no offenses detected.
- `bundle exec rake` → 625 examples, 0 failures, then 0 offences.
- `.rubocop_todo.yml` parks **542 offences across 17 cops**, all as per-file
  `Exclude:` lists — no `Max:` bump, no blanket disable:
  ```sh
  git show fix/s28-lint-ci:.rubocop_todo.yml | awk '/^# Offense count:/{c=$4} /^[A-Za-z]+\/[A-Za-z]+.*:$/{print c, $0}'
  ```
  The three largest are `Metrics/MethodLength` 161, `Metrics/AbcSize` 109,
  `Layout/LineLength` 83.
- The remote `inherit_from` fetch works, and works from cache on a second run.

Gates that were mandatory and what they found:

- **thermo-nuclear** — run on plan and diff.
- **dependency-contract-check** — not needed and skipped: no external object,
  no branch on external state. Said so explicitly.
- **execution-diff** — not needed and skipped: no `lib/` or `exe/` change, so
  there is no observable behaviour to diff. Said so explicitly.
- **Codex** — APPROVE.
- **copilot-review** — run last.
- **Gate A** raised 1 Medium — the first cut used repo-wide cop disables.
  Fixed: regenerated with `--no-exclude-limit` for per-file excludes, rubocop
  pinned `~> 1.89`, and the gate proven to bite by feeding it a 256-character
  line, which made `bundle exec rake` exit 1.
- **Gate B** — APPROVE, zero findings. Config resolution confirmed, and the
  `--ignore-parent-exclusion` flag verified to be a no-op at the repo root.

The lint-debt figure — 542 parked offences at 11140a6 — is the baseline. Item
30 (S24) and item 37 (S30) are the ones that shrink it; nobody re-derives the
number from memory.
