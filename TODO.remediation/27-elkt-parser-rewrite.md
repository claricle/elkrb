# 27 — ELKT parser rewrite
Slice S21 · branch `fix/s21-elkt-parser`

Can start after 06 (S3) — the parser's output is a Hash fed to
`Graph.from_hash`, and until S3 deep-stringifies keys and makes
`layout_options` an open map, every option the parser produces is
dropped on the way into the model, so a parser fix could not be asserted
end to end. The XD gate needs 02 (S0b's `corpus:dump` driver and the
`bom.elkt` / `garbage.txt` corpus fixtures). Blocks the START of 28
(S22), whose ELKT serializer is specified by round-tripping through this
parser. Large (~400 lines). Not BREAKING in the D13 sense — no output
shape moves — but `Elkrb::ParseError` on garbage is new behaviour where
exit 0 used to be.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree.
`lib/elkrb/parsers/elkt_parser.rb` is 248 lines; slice 1 did not touch
it, so the 6ac367c line numbers still hold. ELKT is Xtext-generated and
whitespace-insensitive; every case below is valid input that Java ELK
and ELK's own `ElkGraphFormatter` produce or accept.

One-line `{ … }` blocks never close (gap1-1; formats-1). `parse_line`
dispatches on whole lines (`when /^node\s+(\w+)\s*\{/` at `:63`) and
only pops on a `}` that starts a line, so everything after a one-line
block nests inside it and the in-line content is discarded:

```sh
bundle exec ruby -relkrb -relkrb/parsers/elkt_parser -rjson -e 'puts JSON.generate(Elkrb::Parsers::ElktParser.parse("node n1 { label \"One\" }\nnode n2\nedge n1 -> n2\n"))'
# {"id":"root",…,"children":[{"id":"n1",…,"children":[{"id":"n2",…}],"edges":[{"id":"e0","sources":["n1"],"targets":["n2"]}]}],"edges":[]}
```

`n2` became a child of `n1`, the label vanished, and nothing was raised.

Multi-line `layout [ … ]` — ELK's canonical output form — drops all
geometry and invents options (gap1-3; formats-11). The rule at `:71`
requires `[` and `]` on one line; the inner lines fall through to the
property rule, so `position: 12, 12` becomes
`layoutOptions["elk.position"] = "12, 12"` and the node keeps the 40×40
default. In the single-line form, `parse_layout_block` (`:144`) is an
`if size … elsif position`, so `position` is discarded whenever `size`
is present, and its number pattern `\d+(?:\.\d+)?` rejects `-10`, `+5`
and `1e2` (gap1-9) — negative port positions are normal ELK output.

`label "…" { … }` and `edge … { … }` blocks are never pushed (gap1-4;
gap1-2; formats-2). The label rule at `:75` ignores the trailing `{`,
so the label's own properties land on the enclosing node and its `}`
pops that node. `parse_edge` (`:169`) takes everything after `->` as the
target, so `edge a -> b {` yields `targets: ["b {"]`. Per the grammar,
`{ }` is the ONLY place an ELKT edge label can be written, so elkrb
cannot parse any ELKT edge label correctly today.

`n1.p1 -> n2.p2` loses the ports (formats-4). `create_edge` (`:182`)
emits `sources: ["n1"], sourcePort: "p1"`. `Edge` has no such attribute,
so `Graph.from_hash`/`from_json` and the layout engine drop the keys —
only the ELKT serializer reads them back. The same dotted syntax is how
ELKT references a nested node, which the parser also misreads as a port.

Comment stripping runs before string tokenising (gap1-5; formats-16).
`preprocess` removes `/* … */` over the whole input at `:37` and `//…$`
per line at `:41`, before any string is recognised. A `/*` inside one
label plus a real block comment later deletes everything between them,
including closing braces; a `//` inside a label (URLs) truncates the
line so the label regex no longer matches and the label disappears.

A UTF-8 BOM silently eats the first statement (gap1-10). `String#strip`
does not remove U+FEFF, so every anchored `^…` rule misses:

```sh
printf '\xEF\xBB\xBFalgorithm: force\nnode n1\n' | bundle exec ruby -relkrb -relkrb/parsers/elkt_parser -rjson -e 'puts JSON.generate(Elkrb::Parsers::ElktParser.parse(STDIN.read)[:layoutOptions])'
# {}
```

There is no syntax error at all (gap1-11; formats-10). Arbitrary text
parses to an empty graph, and the commands fall back to ELKT, so
`validate` blesses a DOT or HTML file:

```sh
bundle exec ruby -relkrb -relkrb/parsers/elkt_parser -rjson -e 'puts JSON.generate(Elkrb::Parsers::ElktParser.parse("<html><body>nonsense</body></html>"))'
# {"id":"root","layoutOptions":{},"children":[],"edges":[]}
```

Quoted property values keep their quotes and `org.eclipse.elk.*` keys
get a second prefix (gap1-7; formats-17): `:96` does
`elk_key = key.start_with?("elk.") ? key : "elk.#{key}"`, so
`org.eclipse.elk.direction` becomes `elk.org.eclipse.elk.direction`.
Escaped, single-quoted and empty labels are dropped (gap1-6) — the label
rule at `:75` is `/^label\s+"([^"]+)"/`. Hyperedges collapse into one
bogus id (gap1-8). Auto edge ids collide: `:244` returns
`"e#{current_node[:edges]&.length || 0}"` with no check against ids
already used, and every nested node restarts at `e0` (gap1-15).

`require "elkrb"` does not load the parser or the ELKT serializer
(formats-24). `lib/elkrb.rb` requires `serializers/dot_serializer` at
`:22` and nothing else from `parsers/` or `serializers/`:

```sh
bundle exec ruby -relkrb -e 'p defined?(Elkrb::Parsers::ElktParser), defined?(Elkrb::Serializers::ElktSerializer), defined?(Elkrb::Serializers::DotSerializer)'
# nil  nil  "constant"
```

`spec/elkrb/parsers/elkt_parser_spec.rb` is 482 lines and asserts none
of the above (gap1-16). There is no `spec/fixtures/*.elkt` corpus.

`lib/elkrb/errors.rb` is 30 lines: `Error` `:5`,
`UnsupportedConfigurationException` `:8-16`, `ValidationError` `:19`,
`AlgorithmNotFoundError` `:22-29`.

## Do

Everything below is settled — do not re-decide the shape.

1. Replace the per-line regex dispatcher with a **tokenizer plus a
   recursive-descent parser**. Nothing short of that fixes gap1-1,
   gap1-3, gap1-4 and gap1-5 together, because each is a case of a
   construct crossing a line boundary or a comment crossing a string
   boundary.
2. Tokenizer: skip a leading UTF-8 BOM; recognise double- and
   single-quoted strings with backslash escapes as ATOMIC tokens FIRST,
   and only then strip `//` line comments and `/* … */` block comments;
   emit `[`, `]`, `{`, `}`, `:`, `,`, `->`, numbers
   (`[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?`) and dotted identifiers. Track
   line and column on every token.
3. Grammar: `graph`, `node <id> { … }`, `port <id> { … }`,
   `label "text" { … }`, `edge <id>: a.p -> b.q { … }`, multi-target
   edges into a `targets` array, `layout [ … ]` spanning lines with
   `position` and `size` handled by two independent `if`s (never
   `elsif`), and option lines `key: value` into `layoutOptions`. Braces
   and brackets nest wherever they appear, not only at line starts.
4. `org.eclipse.elk.` keys are kept verbatim — no second `elk.` prefix.
   Quoted values are unquoted. Alias resolution is NOT here: item 08's
   registry and item 09's resolver own that.
5. Resolve `a.b` endpoints against the parsed tree: if `b` is a port of
   node `a`, emit `sources: ["b"]` (the ELK JSON convention); if `b` is a
   child node of `a`, emit its node id. Drop the `sourcePort`/`targetPort`
   keys — no model, no engine and no JSON output ever read them.
6. Generate auto edge ids from a graph-wide counter that skips ids
   already seen, so `edge e1: a -> b` followed by `edge a -> c` cannot
   produce two `e1`s and a nested node cannot restart at `e0`.
7. Add `Elkrb::ParseError < Error` in `lib/elkrb/errors.rb`, directly
   after `ValidationError` at `:19` — not at EOF, because item 09 (S5)
   edits `AlgorithmNotFoundError` at `:22-28`. Raise it with line and
   column for any unparseable input, unbalanced braces at EOF included.
8. Require the parser and both serializers from `lib/elkrb.rb`, next to
   the existing `serializers/dot_serializer` require at `:22`. Item 09's
   resolver require sits after the registry require and item 07 deleted
   `:13`, so keep the hunks apart.
9. Write the spec corpus first: `spec/fixtures/elkt/<case>.elkt` beside
   `<case>.json` holding the expected `Graph#to_json`. Cover every case
   in Facts — one-line blocks, `edge a -> b { label }`, `n1.p1 -> n2.p2`
   port refs, nested `parent.child` refs, multi-line `layout [ … ]` with
   position and size and a negative number, label blocks, `/*` inside a
   label, a `//` inside a label, BOM, escaped / single-quoted / empty
   labels, a hyperedge, `org.eclipse.elk.` keys, unique auto edge ids —
   plus a garbage file that must raise `Elkrb::ParseError`.

Do not touch: the ELKT serializer and the DOT serializer (item 28),
alias resolution and precedence (items 08 and 09), `README.adoc`
(item 30).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- Every `spec/fixtures/elkt/<case>.elkt` parses to its committed
  `<case>.json`, and the garbage file raises `Elkrb::ParseError` naming a
  line and a column.
- The three repros above:
  - the one-line-block command prints `n1` and `n2` as siblings, `n1`
    carrying the label `One`;
  - the BOM command prints `{"algorithm":"force"}`, not `{}`;
  - the HTML command raises `Elkrb::ParseError` instead of returning an
    empty graph.
- `bundle exec ruby -relkrb -e 'p defined?(Elkrb::Parsers::ElktParser)'`
  prints `"constant"`.
- `bundle exec exe/elkrb validate spec/fixtures/corpus/garbage.txt`
  exits 1 (it currently blesses the file through the ELKT fall-through).
- `grep -rn sourcePort lib/` returns nothing.

Mandatory gates, in order: `thermo-nuclear-review` →
`dependency-contract-check` → `execution-diff` → Codex (max reasoning,
read-only, verify-before-critique) → `copilot-review` last.

dependency-contract-check is mandatory and its subject is the ELKT
format itself, not a gem: take real `.elkt` samples from the ELK
documentation and from `ElkGraphFormatter` output, run them through the
new parser, and record what each construct actually produces — do not
reason from the grammar alone. Confirm in the same pass that `validate`
now rejects a DOT file (the fall-through that used to bless it is gone).

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s21` stack base — and again on the branch, then `diff -r` the two
dump dirs. `corpus:dump`'s exit status is informational; never chain on
it.

INTENDED execution-diff differences, and nothing else:

- `bom.elkt` gains the `algorithm` option it used to swallow.
- `garbage.txt` moves from an empty graph to an `Elkrb::ParseError`
  entry — flip its `KNOWN_FAILURES` row.
- Every JSON corpus case is byte-identical: no JSON input goes through
  this parser.

Also run `convert` and `validate` over the new ELKT corpus before and
after and record that matrix in the report.

The report carries no `## Breaking` section for output shape. State
instead, in the report body, that unparseable input now raises
`Elkrb::ParseError` where it used to yield an empty graph and exit 0, and
that `sourcePort`/`targetPort` keys are gone from the parser's Hash.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
