# 01 — Crash guards on ordinary ELK input
Slice S1 · branch `fix/crash-on-elk-input`

Status: done, branch `fix/crash-on-elk-input` @ a008889, merged as the `v2`
seed and awaiting PR review. PR #2 is a draft against `main` — the one slice
PR that does not target `v2`.

Can start: closed. This slice is frozen and is not re-planned. Blocks: it is
the base of everything — `v2` IS this commit, so every other item branches
from it and re-locates its `6ac367c` line numbers against it. Blocks the START
of 02 (S0b) and 03 (S0a) only in the sense that both author their ledgers
against `v2`. Medium (19 files, +605/-107). Not BREAKING: only crashes and
wrong output change.

## Facts

`v2` and `fix/crash-on-elk-input` are the same commit, one ahead of `main`:

```sh
git rev-parse --short v2 fix/crash-on-elk-input   # a008889 a008889
git log --oneline 6ac367c..v2                     # a008889 Fix crashes on ordinary ELK input
```

The suite on that commit is green: `bundle exec rspec` → **625 examples, 0
failures** (measured 2026-08-21 in the frozen worktree
`.claude/worktrees/agent-a4b7bb4b410acc429`).

What the commit actually fixed, verified against `git show a008889`:

- **RC1** — lutaml bypasses `LayoutOptions#initialize`, so `@properties` was
  nil after `from_json`/`from_yaml`/`from_hash` and any `layoutOptions` block
  crashed with `undefined method '[]' for nil` (pipeline-1). `[]` and `[]=` in
  `lib/elkrb/graph/layout_options.rb` are now `(@properties || {})` /
  `(@properties ||= {})`, and the 12 typed getters/setters
  (`port_constraints`, `self_loop_side`, …) route through `self[…]` instead of
  `properties[…]`.
- **RC3** — `Elkrb.known_layout_algorithms` and `Elkrb.known_layout_options`
  called `AlgorithmRegistry.all`, which does not exist (pipeline-3, gap2-5).
  They now call `all_algorithm_info` and `available_algorithms`.
- **RC4 self-loops** — `layered/layer_assigner.rb` gained `self_loop_edge?`
  and skips such edges at both incoming-edge scans, killing the
  `SystemStackError` (layered-2, docs-packaging-1, gap3-4). `mrtree.rb`
  replaced `build_tree`'s unguarded recursion with `build_subtree(root, graph,
  0, Set.new)` and rejects already-visited children (tree-family-1).
- **RC4 nil collections** — `graph.rb#all_edges` and `#hierarchical?` guard
  `@edges`/`@children` being nil after deserialization (data-model-5, gap2-7).
- **RC4 sizeless nodes and text-only labels** — read-site guards in
  `base_algorithm.rb`, `box.rb`, `force.rb`, `random.rb`, `disco.rb` and a
  rewritten `label_placer.rb` with `width_of`/`height_of` helpers
  (docs-packaging-3, formats-23, pipeline-8).

What it did NOT fix, on purpose: **duplicate node ids** still pass `validate`
and crash layered (gap3-3). That is item 11 (S7).

Slice 1 is a read-site guard, not an attribute default. A node or label that
never had a width/height still carries nil on the object:

```sh
git show v2:lib/elkrb/layout/label_placer.rb | grep -n "def width_of\|def height_of"
```

That is decision 5 of the remediation plan (output omits `width`/`height` for
LEAF nodes that never had them; nodes with children always get a computed
size). Item 02 tracks it as the `D5` rows in its ledger; item 03 replaces
those rows with a real matcher.

## Do

Nothing is implemented here. These are the standing rules this item imposes on
every other item, and they are settled:

1. Do not re-plan, rebase, or rewrite `fix/crash-on-elk-input` or `v2`.
   a008889 is frozen.
2. Any change the maintainer asks for on PR #2 lands as an **additional
   commit** on `fix/crash-on-elk-input` and is then merged forward into `v2`
   with a merge commit. `v2` is never rewritten.
3. Every other item's line numbers are as of `6ac367c` in the source plans.
   Re-locate them against `v2` before touching a file — method names are
   authoritative, line numbers are not.
4. Items 02 and 03 author their ledgers against `v2`, not `main`. The
   self-loop, sizeless-node and no-children cases carry **no** `no_crash`
   rows, because this slice already fixed those crashes.
5. Item 06 (S3) deletes this slice's typed-getter specs and its
   `LayoutOptions` nil guards, but keeps its pipeline specs and the
   `if graph.children` dispatch guard. Item 14 (S10) keeps that guard too.
6. Release is a separate maintainer step. This slice may ship alone as 1.0.3
   before the 2.0.0 batch; the bump never happens in a branch.

## Done when

Already done. The record:

- `git merge-base --is-ancestor a008889 origin/v2` exits 0 — the seed is on
  origin.
- `bundle exec rspec` on a008889 → 625 examples, 0 failures.
- The four crash repros from the audit no longer raise. Cheapest check, from
  the repo root:
  ```sh
  bundle exec ruby -relkrb -rjson -e 'g = Elkrb::Graph::Graph.from_json(%q({"id":"r","layoutOptions":{"elk.direction":"DOWN"},"children":[{"id":"a"}],"edges":[{"id":"e","sources":["a"],"targets":["a"]}]})); Elkrb.layout(g); puts "ok"'
  ```
  prints `ok`. The same line on `main` (6ac367c) dies with
  `stack level too deep (SystemStackError)` out of `graph.rb:57` — the
  self-loop recursion — and, once that is past, with `NoMethodError` for nil
  on the `layoutOptions` read.

No review gates apply. The slice is taken as given — no thermo-nuclear, no
dependency-contract-check, no execution-diff, no Codex, no copilot-review were
run against it as part of this effort, and none will be. Its correctness is
carried by PR #2's own review.
