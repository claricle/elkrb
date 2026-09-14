# sirena consumer fixtures

Graph hashes captured from [claricle/sirena], the consumer that drives
elkrb. They exist so "the consumer sends this shape" is a committed file
rather than a claim. Item 35 (S27b) asserts the contract against them.

**No JSON in this directory is hand-edited.** The 8 fixtures are
captured by `rake fixtures:sirena`. The 8 `.mmd` sources under `src/` are
hand-written by design — that is a different thing, and it is why they
are kept beside the output they produced.

## Provenance

| | |
|---|---|
| sirena commit | `c3820364551b3f107b6177bba8d1e2c0c6d3940b` |
| sirena branch | `plan/architecture-update` |
| working tree | clean (`git status --porcelain` empty) |
| captured on | 2026-08-28 |

Without the sha nobody can tell a stale fixture from a changed consumer.
Assert it before re-capturing; do not check it out.

### The card referenced an older sirena

Card 34 was verified against `942499a`. sirena has moved since:
`git diff --shortstat 942499a c382036 -- lib/` reports 27 files
changed, 1815 insertions, 370 deletions. The split matters when
comparing these fixtures to the card:

- **The ELK option builders are byte-identical** between the two shas —
  `transform/c4.rb`, `transform/base.rb`, `transform/mindmap.rb` are
  unchanged. Every `layoutOptions` figure in the card still holds.
- **The parsers and node/edge transforms changed**, so node and edge
  content can differ from what the card's author would have seen:
  `parser/grammars/flowchart.rb` (+475/-35),
  `parser/transforms/flowchart.rb` (+209/-89),
  `parser/transforms/sequence.rb` (+71/-38),
  `parser/transforms/c4.rb` (+18/-18),
  `parser/class_diagram.rb` (+8/-17),
  `transform/sequence.rb` (+3/-1).

The capture is from `c382036` because the fixtures exist to prove what
the consumer sends, and that is the consumer that exists.

## The capture command

Run it from the elkrb repo root. `SIRENA_DIR` is your sirena checkout:

```sh
rake fixtures:sirena SIRENA_DIR=~/claricle/sirena
```

It re-captures all 8 fixtures in place. Add `OUT_DIR=<dir>` to write them
somewhere else, which is what you want before comparing (see
*Re-capturing* below).

The task prints the sirena sha and whether that working tree is clean, so
you can check both against the table above before you trust the output.

The work itself is in `capture.rb` in this directory. It runs inside
sirena's own bundle, because sirena is a separate gem. It uses only
sirena's public classes: `DiagramRegistry`, the parser and the transform.
The diagram type of each fixture is listed in `capture.rb`, so sirena's
private type detection is never called.

Older sirena revisions pass the date into `to_graph`. `capture.rb` still
does that when the method takes it. None of these transforms read the
date, so it never reaches the output and the fixtures cannot drift with
it. The date in the table above is provenance, not a byte in any file.

## What each fixture captures

| fixture | shape |
|---|---|
| `flowchart_td.json` | `graph TD`, 5 nodes, 4 edges, one branch — flat |
| `flowchart_lr.json` | `flowchart LR`, the same transform with `elk.direction` RIGHT |
| `class_flat.json` | class diagram, one inheritance edge, `INCLUDE_CHILDREN` on a flat graph |
| `state.json` | a composite `state Connected { … }` that the transform **flattens** to 6 siblings |
| `er.json` | two entities with attribute blocks, one relationship |
| `sequence.json` | two participants, an activation and a return; root `metadata` |
| `user_journey.json` | two sections, three tasks; root `metadata` |
| `c4_nested.json` | **the nested case** — `acme` containing `shop` and `billing`, each boundary carrying `elk.algorithm: box`, and `rel_1` crossing from `api` in `shop` to `ledger` in `billing` at the root |

Only C4 nests. Every other transform emits a flat graph today. No
transform emits ports or per-edge `layoutOptions`. mindmap is not
captured: it returns `{nodes:, connections:, width:, height:, root:}`,
which is not an ELK graph.

## The synthetic algorithm options

`mrtree`, `stress`, `force` and `sporeOverlap` are **not captured** —
sirena emits none of these algorithms yet. So no fixture file exists for
them. The spec takes `flowchart_td.json` and swaps in the option map,
nothing else. That keeps one copy of the graph instead of five.

The option maps are not typed by hand either. They come from sirena's own
`build_elk_options`:

```sh
cd ~/claricle/sirena && bundle exec ruby -rjson -rsirena -e \
  't = Sirena::Transform::FlowchartTransform.new;
   b = Sirena::Transform::Base;
   puts JSON.pretty_generate(
     t.send(:build_elk_options, algorithm: b::ALGORITHM_MRTREE,
                                direction: b::DIRECTION_DOWN))'
```

`mrtree` and `sporeOverlap` get only `algorithm` and `elk.direction`;
`build_elk_options` merges algorithm defaults for `layered`, `stress`
and `force` only. `stress` and `force` additionally carry
`elk.spacing.nodeNode` `75.0` (a Float — `DEFAULT_NODE_SPACING * 1.5`)
beside two Integer `30`s.

**What they pin, and what they do not.** They carry the bare `algorithm`
key sirena really writes — `ElkOptions::ALGORITHM` is `"algorithm"`, not
`"elk.algorithm"`. elkrb selects its algorithm from the call options and
otherwise defaults to `layered`, so all four run layered today. They pin
that an algorithm value elkrb does not dispatch on **survives the round
trip untouched**. They do not show elkrb running mrtree.

## Re-capturing

Assert the sha and a clean tree, capture into a scratch directory, and
compare the 8 captures **by name**:

```sh
rake fixtures:sirena SIRENA_DIR=~/claricle/sirena OUT_DIR=/tmp/sirena-capture
for f in /tmp/sirena-capture/*.json; do
  diff "$f" "spec/fixtures/consumers/sirena/$(basename "$f")"
done
```

A `diff -r` of the two directories cannot pass: this directory also holds
`README.md`, `capture.rb` and `src/`, so it reports "Only in" lines even
when every capture is byte-identical.

A difference after re-capture means **sirena changed**. That is the
whole reason the sha is recorded here.

[claricle/sirena]: https://github.com/claricle/sirena
