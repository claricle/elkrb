# 36 — CLI UX and option introspection
Slice S29 · branch `fix/s29-cli-ux`

Can start after 05 (S2 fixes `exit_on_failure?` and the output streams — this
item rewrites the option blocks on top of that, not around it), 08 (S4's
registry is what `elkrb options` prints and where the enum values in the help
text come from), 09 (S5 wrote `apply_flags_to_root` and the flag → option
table in `cli.rb`; this item moves them verbatim into a Thor module), and 26
(S20's validate examples must already be in `cli_spec.rb`). The XD gate and
every spec need 02 (S0b's `run_elkrb`). Merge 13 (S9) in before touching
`cli_spec.rb`: 13 adds its own `describe` section there and this item rewrites
the file wholesale. Blocks the START of 35 (S27b) — the contract cites `elkrb
options` — and of 37 (S30), which documents the final command set. Medium
(~250 lines). Not BREAKING for the library; the CLI's surface grows and its
help text changes.

## Facts

Verified against `v2` (a008889) extracted to a scratch tree.
`lib/elkrb/cli.rb` is 224 lines.

The CLI registers 8 commands — `desc` lines at `cli.rb:16` (`layout`),
`:59` (`algorithms`), `:76` (`diagram`), `:99` (`convert`), `:112`
(`render`), `:127` (`validate`), `:138` (`batch`), `:153` (`version`).
There is no `options` command.

`--json` does not exist on any command:

```sh
bundle exec exe/elkrb algorithms --json
# ERROR: "elkrb algorithms" was called with arguments ["--json"]
# Usage: "elkrb algorithms"
```

The output format ignores `--output`'s extension.
`option :format, type: :string, default: "json", enum: %w[json yaml]`
sits at `cli.rb:21-23`, and `output_result` (`:200-214`) branches on
`options[:format]` alone:

```sh
d=$(mktemp -d); bundle exec exe/elkrb layout spec/fixtures/simple_graph.json --output $d/r.yml
head -c 40 $d/r.yml
# {"id":"root","width":54.0,"height":234.0,…
```

`README.adoc:917` shows exactly that command as the way to get YAML.

Diagnostics go to stdout: `verbose_output` (`:216-218`) and
`error_output` (`:220-222`) both call Thor's `say`. Item 05 (S2) moves
both to stderr — do not redo it, build on it.

Thor exits 0 on every usage error at `v2`:

```sh
bundle exec exe/elkrb nosuchcommand; echo $?   # 0
bundle exec exe/elkrb layout; echo $?          # 0
```

Item 05 (S2) adds `def self.exit_on_failure? = true`, which fixes the
exit code but not the message. Errors still print no hint about what to
do next.

The flag → option table and `apply_flags_to_root` live in `cli.rb` after
item 09 (S5), duplicated in
`lib/elkrb/commands/diagram_command.rb:95-103`. `batch` reaches the same
table through `DiagramCommand`.

Item 08 (S4) gave every registry row a `status:` (`:honoured`,
`:partial`, `:accepted`, `:unsupported`) and a `note:`, exposed through
`Registry.status(id)`, `Registry.note(id)`,
`Elkrb.known_layout_options[id][:status]` and
`AlgorithmRegistry.algorithm_info[:supported_options]`. That status field
is what this item prints and what 35 (S27b) asserts. Nothing prints it
today.

`AlgorithmRegistry.available_algorithms.size` is 15 on `v2`.

## Do

Everything below is settled — do not re-decide.

1. New `lib/elkrb/cli/layout_flags.rb`: one Thor module carrying
   `--algorithm --direction --edge-routing --spacing --layer-spacing
   --padding-top --padding-bottom --padding-left --padding-right` and
   `apply_flags_to_root(graph, options)`, **moved verbatim** from item
   09's `cli.rb`. Include it in `layout`, `diagram` and `batch`. One
   table, three commands — the duplication in
   `diagram_command.rb:95-103` goes with it.
2. `layout`: when `--format` is not given, derive the format from
   `--output`'s extension (`.yml`/`.yaml` → YAML, else JSON). `--format`
   given always wins. Touch `cli.rb:21-23` and `output_result`
   (`:200-214`). This moved here from item 26 deliberately: it is
   `layout`'s behaviour, not `validate`'s.
3. New command `elkrb options [ALGORITHM] [--json]`. Text output is
   columns `id  type  default  status  aliases`. JSON output is
   `{"options":[{"id","type","default","status","aliases":[],"algorithms":[]}]}`.
   With an ALGORITHM argument, filter by
   `Registry.for_algorithm(name)`. The data comes from the registry — no
   second table anywhere.
4. `elkrb algorithms --json`:
   `{"algorithms":[{"id","name","description","category","supports_hierarchy","supported_options":[]}]}`,
   with `supported_options` from `algorithm_info[:supported_options]`.
5. Enum values in every command's help text come from the registry, not
   from literals in `cli.rb`. A new registry value must show up in
   `--help` without a CLI edit.
6. Every error path: message to stderr, exit 1, and one line saying what
   to do — e.g. `Try: elkrb validate --strict FILE`. `--verbose` output
   to stderr (item 05 already moved it; confirm, do not redo).
7. Rewrite `spec/elkrb/cli_spec.rb` around a matrix: for each of the 9
   commands (the 8 that exist plus `options`) × {ok, missing file,
   unknown algorithm, bad flag}, assert the exit code, which stream
   carried the output, and — for `--json` — that it parses and holds the
   keys listed in steps 3 and 4. Drive it all through 02's `run_elkrb`
   subprocess runner; never `Cli.start` in-process, except for the
   flag → root-option table where a unit test is the point.
8. Add `layout --output x.yml` writes YAML as an explicit example.

Do not touch: `validate`'s own semantics (item 26 owns
`validate_command.rb`), the registry table (item 08), the resolver and
precedence (item 09), `README.adoc` (items 30 and 37).

## Done when

- `bundle exec rake` is green (spec + rubocop; 04/S28 made that the bar).
- `bundle exec exe/elkrb options --json | ruby -rjson -e 'j=JSON.parse($stdin.read); p j["options"].size, j["options"][0].keys.sort'`
  parses and every entry carries `id`, `type`, `default`, `status`,
  `aliases`, `algorithms`.
- `bundle exec exe/elkrb options layered` lists only ids
  `Registry.for_algorithm("layered")` returns.
- `bundle exec exe/elkrb algorithms --json` parses and lists every
  registered algorithm with `supported_options`.
- `bundle exec exe/elkrb layout spec/fixtures/simple_graph.json --output $d/r.yml`
  writes YAML; adding `--format json` writes JSON to the same path.
- Every command in the 9 × 4 matrix has its exit code, stream and hint
  asserted, and the whole matrix is in the report.
- `bundle exec exe/elkrb --help` shows the registry's enum values for
  `--direction` and `--edge-routing`.
- `grep -rn 'apply_flags_to_root' lib/` shows exactly one definition, in
  `lib/elkrb/cli/layout_flags.rb`.

Mandatory gates, in order: `thermo-nuclear-review` →
`dependency-contract-check` → `execution-diff` → Codex (max reasoning,
read-only, verify-before-critique) → `copilot-review` last.

dependency-contract-check is mandatory and its subject is Thor.
Construct the real CLI and run it — do not reason about Thor's behaviour
from memory. Cover: a Thor module of `option` declarations included into
three commands, and whether an absent flag is absent from `options` in
each; `enum:` values built at class-definition time from the registry;
`--json` on a command that takes no arguments; the exit status Thor
produces for an unknown command, a missing required argument and an
out-of-enum value with `exit_on_failure?` true; and which stream Thor's
own usage errors go to. Record the Thor version that answered.

execution-diff driver: `bundle exec rake "corpus:dump[<dir>]"` (quote the
brackets) on the branch's base ref — its merge-base with `v2`, or the
`int/s29` stack base — and again on the branch, then `diff -r` the two
dump dirs. `corpus:dump`'s exit status is informational; never chain on
it.

INTENDED execution-diff differences, and nothing else:

- **The corpus dump is byte-identical.** This item changes no layout
  code; a difference there means a flag default leaked.
- The observable change is the CLI matrix. Drive it separately: run
  `bundle exec exe/elkrb layout` over every `spec/fixtures/*.json` on the
  base ref and on the branch and diff the outputs — they must match
  byte for byte, because moving the flag table into a module is a
  refactor. The only new outputs are `elkrb options`, `algorithms --json`
  and `--output x.yml` now producing YAML.

The report carries no `## Breaking` section for library API. State
instead that `--output x.yml` now writes YAML where it wrote JSON, that
`elkrb options` is new, and that `algorithms` gained `--json`.

Publication is the orchestrator's: Gate A (`multi-agent-review`) then
Gate B (Codex `ultra`) on the exact head SHA, both clean, then push and
`gh pr create --draft` against `v2`.
