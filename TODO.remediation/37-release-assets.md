# 37 — CHANGELOG, generated docs, packaging
Slice S30 · branch `fix/s30-release-assets`

The FINAL slice. Can start only after 25 (S19, the last constraint
behaviour), 28 (S22, the ELKT and DOT text this item documents), 29 (S23,
the data model this item documents), 30 (S24 rewrote the README this item
refreshes and points at `docs/OPTIONS.adoc`), 32 (S25b, the last layered
behaviour), 33 (S26, the last performance work), 35 (S27b, the adoption
gate) and 36 (S29, the last command). Every behaviour and every command
has to be final, because this item generates docs FROM the code
and assembles the CHANGELOG FROM the merged PR bodies — both drift the
moment anything else lands. Blocks nothing; the `v2 → main` PR and the
2.0.0 release follow it. Medium (~300 lines). Not BREAKING in itself; it
is the file that describes everything that was.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree.

There is no LICENSE and no CHANGELOG (docs-packaging-18):

```sh
git ls-files | grep -i 'license\|changelog'
# (no output)
```

`elkrb.gemspec:18` declares `BSD-2-Clause` and `README.adoc:1025-1028`
repeats it, so the licence text is missing from every redistribution.
`spec.metadata["changelog_uri"]` (`:23`) points at the bare repository
URL.

The gem ships 27 non-`lib/` files (docs-packaging-22). `spec.files`
(`:26-32`) is `git ls-files` minus `bin|test|spec|features` and the
`.git*`, `.travis*`, `.circleci*` and `appveyor*` prefixes — every other
dotfile ships:

```sh
bundle exec ruby -e 'f=Gem::Specification.load("elkrb.gemspec").files; puts f.size; puts f.reject{|x|x.start_with?("lib/")}'
# 86
# .rspec  .rubocop.yml  Gemfile  README.adoc  Rakefile
# benchmarks/…(8 files)  examples/…(7 files)  exe/elkrb  sig/…(6 files)
```

`rbs` is a runtime dependency (`elkrb.gemspec:37`) although nothing under
`lib/` or `exe/` requires it; it carries a C extension, so every
installer builds it.

`sig/` does not load (gap2-1; data-model-19):

```sh
bundle exec rbs -I sig validate
# ERROR sig/elkrb/constraints.rbs:6: Could not find super class: Lutaml::Model::Serializable
# ERROR sig/elkrb/constraints.rbs:14: Could not find super class: Lutaml::Model::Serializable
```

lutaml-model 0.8.19 ships only a VERSION stub in its own `sig/`, so
`-r lutaml-model` does not help. Nothing in the repo exercises `sig/`:
no Steepfile, no rbs task, no CI step. Decision 4 (maintainer-ruled):
delete `sig/` here and drop the `rbs` dependency with it.

`required_ruby_version` is `>= 3.0.0` (`elkrb.gemspec:19`) and the gem
cannot load there (docs-packaging-8):
`lib/elkrb/options/k_vector_chain.rb:103` is `def each(&)`, which is
Ruby 3.1+, and lutaml-model 0.8.19's `runtime_compatibility.rb` uses
`(*, &)`, which is 3.2+. Decision 13 (maintainer-ruled): the floor is
`>= 3.2`, stated here and in the 2.0 migration block.

There is no `docs/` directory in the repository. `README.adoc:830` links
`docs/MIGRATION_FROM_ELKJS.adoc`, which item 30 either fixed or left
pointing at its placeholder with a TODO naming this item.

The CHANGELOG inventory is the merged slice PR bodies' `## Breaking`
sections, and nothing else. No slice edits `CHANGELOG.md` and no
hand-maintained list exists anywhere. The ground rules require a
`## Breaking` section — possibly saying "none" — from items 06 (S3),
07 (S3b), 09 (S5), 11 (S7), 12 (S8), 13 (S9), 14 (S10), 15 (S10b),
16 (S11), 17 (S12), 18 (S13), 19 (S13b), 22 (S16), 23 (S17) and
25 (S19). Later slices added their own — 28 (S22), 31 (S25a), 32 (S25b)
each carry one too. Read every merged PR body; do not work from this
list.

Item 08 (S4) made `lib/elkrb/options/registry.rb` the single source of
option metadata, with `status:` and `note:` per row. Item 03 (S0a)
committed the elkjs 0.11.0 goldens and their tiers. Those two are what
`docs/OPTIONS.adoc` and `docs/COMPATIBILITY.adoc` are generated from —
neither file is written by hand.

The release is 2.0.0 (decision 2), cut by the maintainer through the
cimas `release.yml` workflow. **No version bump in this branch** —
`lib/elkrb/version.rb` and the gemspec version are not touched here.

## Do

Everything below is settled — do not re-decide.

1. `CHANGELOG.md`, Keep-a-Changelog format. Assemble the 2.0.0 block from
   the merged slice PRs' `## Breaking` sections — sections that say
   "none" contribute nothing. One entry per section, each with before /
   after JSON and a migration line. State the Ruby floor 3.2 and the bare
   `direction` alias (decision 9). Record in the PR body which PR numbers
   you read, so the inventory is auditable.
2. `rake docs:options` generates `docs/OPTIONS.adoc` from
   `Elkrb::Options::Registry` — id, type, default, status, note, aliases,
   algorithms. Commit the generated file. Add `spec/docs_spec.rb` that
   regenerates into a tmp dir and fails on any difference, so the docs
   cannot drift from the registry the code reads.
3. `docs/COMPATIBILITY.adoc` generated from the golden results: per
   algorithm and per case, the tier it passes at and whether it is
   pending. Same drift spec.
4. `docs/MIGRATION_FROM_ELKJS.adoc` — the README has linked it since the
   first commit and it has never existed. Write it against the goldens
   and the contract, not from memory.
5. `LICENSE` with the BSD-2-Clause text, Ribose Inc.
6. Delete `sig/` and remove `spec.add_dependency "rbs", "~> 3.0"`
   (`elkrb.gemspec:37`). Decision 4: restoring signatures later needs an
   owned source of truth plus CI validation, and neither exists.
7. `elkrb.gemspec`: `required_ruby_version = ">= 3.2"` (`:19`);
   `metadata["changelog_uri"]` points at the CHANGELOG (`:23`);
   `spec.files` becomes an explicit whitelist — `lib/**/*.rb`, `exe/*`,
   `README.adoc`, `LICENSE`, `CHANGELOG.md`, `docs/**` — replacing the
   `git ls-files` block at `:26-32`. Do NOT touch the version.
8. Refresh the README against the final state: the command list including
   `options` (item 36), the include of `docs/OPTIONS.adoc` resolved to
   the generated file with item 30's placeholder TODO removed, and the
   `docs/MIGRATION_FROM_ELKJS.adoc` link now resolving.
9. `spec/readme_spec.rb`: extract the README quickstart and run it,
   asserting the printed values. Item 30 made the snippets correct; this
   is what keeps them correct.

Do not touch: `lib/elkrb/version.rb`, the gemspec version, or anything
under `lib/elkrb/layout/`. If a doc-generation run shows the code is
wrong, that is a finding for the owning slice, not a fix here.

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- `bundle exec rake docs:options` twice in a row leaves `docs/OPTIONS.adoc`
  byte-identical, and `bundle exec rspec spec/docs_spec.rb` is green.
- `bundle exec rspec spec/readme_spec.rb` is green.
- `gem build elkrb.gemspec` succeeds and the payload holds only
  `lib/`, `exe/`, `README.adoc`, `LICENSE`, `CHANGELOG.md` and `docs/`:
  `bundle exec ruby -e 'puts Gem::Specification.load("elkrb.gemspec").files.reject{|f| f =~ %r{\A(lib/|exe/|docs/)} || %w[README.adoc LICENSE CHANGELOG.md].include?(f)}'`
  prints nothing.
- `git ls-files sig` returns nothing and
  `grep -n rbs elkrb.gemspec` returns nothing.
- `bundle exec ruby -e 'p Gem::Specification.load("elkrb.gemspec").required_ruby_version.to_s'`
  prints `>= 3.2`.
- `grep -rn 'link:docs/' README.adoc` — every target is a committed file.
- `git diff lib/elkrb/version.rb elkrb.gemspec | grep -i version` shows
  no version change.
- `CHANGELOG.md`'s 2.0.0 block has one entry per merged `## Breaking`
  section, each with before / after JSON and a migration line.

Mandatory gates, in order: `thermo-nuclear-review` →
`dependency-contract-check` → Codex (max reasoning, read-only,
verify-before-critique) → `copilot-review` last. `copilot-review` earns
its keep here: it reads the CHANGELOG prose blind and catches the entry
that says the opposite of what the diff did.

dependency-contract-check is mandatory and its subject is RubyGems.
Build the real gem and read what came out — do not reason about
`spec.files` from the gemspec source: `gem build elkrb.gemspec`, then
`gem contents` (or `tar tf` the `.gem`'s `data.tar.gz`) and compare
against the whitelist; confirm `required_ruby_version` and
`changelog_uri` are what the built gemspec reports; confirm the gem
installs and `require "elkrb"` works with `rbs` absent from the bundle.
Also prove `rake docs:options` is idempotent by running it twice and
diffing.

No execution-diff gate: this item changes no runtime code. Say so
explicitly in the report rather than skipping silently, and prove it —
`git diff --stat` shows no change under `lib/elkrb/layout/`,
`lib/elkrb/graph/` or `lib/elkrb/options/`, and
`bundle exec rake "corpus:dump[<dir>]"` (quote the brackets) on the base
ref and on the branch gives an empty `diff -r`.

The report carries no `## Breaking` section of its own — this slice IS
the inventory. State instead which merged PR numbers were read, which of
them said "none", and that no version was bumped.

After this merges, the remaining work is the maintainer's: the
`v2 → main` PR, `golden.yml` as a required check (needs repo admin), and
the 2.0.0 release dispatched through the cimas `release.yml` workflow.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
