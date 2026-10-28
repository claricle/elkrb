# 05 — CLI and shell boundary
Slice S2 · branch `fix/s2-cli-shell`

Status: built, **not gated, not merged**. Branch `fix/s2-cli-shell` @
249a4d8, 20 commits ahead of `origin/v2`.

**Its base is frozen and both halves have moved on.** Measured 2026-08-27:
the branch forks from the `v2` seed `a008889` and carries 02's **old** tip
`dcec6d0`. It contains neither current `origin/v2` (`75bdb13`) nor current 02
(`37bb0ce`), and its own Rakefile still runs `task default: :spec`, so
`bundle exec rake` there does not measure RuboCop at all.

The base is what it is because this item un-pends 02's `cli_spec` examples
and cannot build without its `cli_runner` and `fake_dot`. Before it gates:

1. 02 lands first.
2. Merge current `origin/v2` into this branch — that brings 04's rake task.
3. Run the full `bundle exec rake`, spec **and** rubocop, and clear it.
4. Gate the exact branch tip that step 3 passed on — not an earlier SHA,
   and not one with commits added after. The approval names that tip.

**This is the critical path.** Nothing else unblocks 09, and 09 is what
unblocks 10, and 10 is what unblocks 19 of the remaining cards. 24 sit
behind 05 itself — see the closure table in `00-overview.md`.

Can start: after 02 (S0b) — specifically its `spec/support/cli_runner.rb`,
`spec/support/fake_dot.rb` and the four `pending "RC10"` examples in
`spec/elkrb/cli_spec.rb`, which are this item's failing tests. Blocks the START
of 09 (S5, which overlaps in `cli.rb`, `diagram_command.rb`, `batch_command.rb`
and `cli_spec`), 26 (S20, validate correctness) and 36 (S29, which rewrites
every command's option block wholesale). Medium (16 files, ~600 lines). Not
BREAKING for users with `dot` on `PATH` — but exit codes and streams change for
anyone scripting the CLI, and the absolute-path fallback for `dot` is gone.
Report it, do not put it in a `## Breaking` section.

## Facts

Measured on `v2` (a008889) — slice 1 touched no CLI file, so `main` behaves
identically.

- **Shell injection is live.** `graphviz_wrapper.rb:84` joins argv into one
  string (`cmd_parts.join(" ")`) and `:88` runs `system(cmd)`, which goes
  through `/bin/sh`. Proven, not argued (cli-security-1, tests-3):
  ```sh
  S=$(mktemp -d); printf 'digraph{a->b}' > $S/in.dot
  bundle exec ruby -relkrb/graphviz_wrapper -e "Elkrb::GraphvizWrapper.new.render('$S/in.dot', '$S/out.png; touch $S/PWNED', :png)"
  ls $S    # => PWNED  in.dot
  ```
  It reaches users through `elkrb diagram -o <path>`, `elkrb render -o
  <path>`, and `elkrb batch`, where the input filenames become the DOT path.
- **Usage errors exit 0.** `Elkrb::Cli` never overrides `exit_on_failure?`
  (cli-security-3):
  ```sh
  bundle exec exe/elkrb layout; echo "exit=$?"    # exit=0, plus a Thor deprecation warning
  ```
- **Diagnostics land on stdout.** `cli.rb:220` `error_output` and `:216`
  `verbose_output` both use Thor's `say` (cli-security-5, cli-security-6):
  ```sh
  bundle exec exe/elkrb layout nope.json > out.json; cat out.json
  # => Error: No such file or directory @ rb_sysopen - nope.json
  bundle exec exe/elkrb layout spec/fixtures/simple_graph.json --verbose 2>/dev/null | ruby -rjson -e 'JSON.parse($stdin.read)'
  # => JSON::ParserError
  ```
- **The format-detect fallback is dead code.** `cli.rb:173` and
  `detect_and_parse` in `convert_command.rb:65`, `validate_command.rb:66`,
  `diagram_command.rb:74` all rescue `JSON::ParserError`. lutaml-model 0.8.19
  raises `Lutaml::Model::InvalidFormatError` (data-model-18, gap3-10,
  formats-9):
  ```sh
  bundle exec ruby -relkrb -e 'begin; Elkrb::Graph::Graph.from_json("id: root\n"); rescue => e; p e.class, e.is_a?(JSON::ParserError); end'
  # => Lutaml::Model::InvalidFormatError, false
  ```
  So a YAML or ELKT file with no recognised extension fails with
  "input format is invalid, try to pass correct `json` format", on stdout,
  and the YAML and ELKT branches never run.
- **`exe/elkrb:4` requires `bundler/setup`**, so the installed executable
  raises `LoadError` inside any project whose Gemfile omits elkrb
  (cli-security-4).
- **`find_graphviz` trusts a directory.** `graphviz_wrapper.rb:63` tests
  `File.executable?(path)` with `"dot"` first in the candidate list, so a
  directory named `dot` in cwd wins (cli-security-13). The candidate list also
  carries four absolute paths, and `:65` shells out to
  `system("which #{path} …")`.
- **`batch` reports success on failure.** `batch_command.rb:37-43` counts
  `error_count` and `:48` prints it, then the method returns normally — no
  non-zero exit.
- **`version` uses backticks.** `graphviz_wrapper.rb:38`:
  `` `#{@dot_path} -V 2>&1` `` — a shell interpolation, and
  `graphviz_wrapper_spec.rb:109` stubs the backtick method itself.
- **`build_command` emits the `-o<path>` suffix form** at
  `graphviz_wrapper.rb:81`, not a separate `-o` token.
- On this branch, `bundle exec rspec` → **749 examples, 0 failures, 12
  pending** (measured 2026-08-21). Base was 729/0/16 — 4 of 02's pendings are
  un-pended here.

## Do

1. `graphviz_wrapper.rb`: `build_command` returns an **Array**
   `[@dot_path, "-K#{engine}", "-T#{format}", "-Gdpi=#{dpi}", "-o",
   output_file, input_file]`. Separate `-o` and path tokens — settled, and 02's
   fake `dot` already logs both forms so nothing has to guess.
   `execute_command(argv)` calls `system(*argv)`. No string form anywhere.
2. `find_graphviz` becomes **PATH-only**. `ENV["ELKRB_DOT"]`, when set to a
   non-empty value, is the sole candidate — used as-is when
   `File.file?(p) && File.executable?(p)`, otherwise treated as not found,
   with no PATH fallback. Unset or empty means no override. Otherwise take the
   first `File.join(dir, "dot")` over `ENV["PATH"].split(File::PATH_SEPARATOR)`
   that is `File.file?` **and** `File.executable?`, so a directory named `dot`
   cannot match. Delete the absolute-candidate list and the `which` shell-out:
   an absolute fallback would make the unavailable-Graphviz spec
   non-deterministic, because `/opt/homebrew/bin/dot` is executable on the dev
   host. Document `ELKRB_DOT` in `find_graphviz`'s YARD and in
   `installation_message`.
3. `version` goes through `Open3.capture2e(@dot_path, "-V")`, with
   `require "open3"` at the top of `graphviz_wrapper.rb` — `v2` never requires
   it anywhere.
4. `cli.rb`: `def self.exit_on_failure? = true`; `error_output` →
   `$stderr.puts`; `verbose_output` → stderr (keep the colour helper only if
   it can target stderr).
5. `read_input_file`: for extensions that are not `.json`/`.yml`/`.yaml`,
   sniff the first non-whitespace character — `{` or `[` → `from_json`, else
   `from_yaml`. Rescue `Lutaml::Model::InvalidFormatError`, not
   `JSON::ParserError`. Then `require_relative "parsers/elkt_parser"` and try
   `ElktParser.parse`. If that returns a graph with no children and no edges,
   raise `ArgumentError, "Unable to parse input file. Supported formats: JSON,
   YAML, ELKT"`. That guard is load-bearing: the ELKT parser is lenient until
   item 27 (S21) and turns arbitrary text into an empty graph, so without it
   adding the fallback would make `layout garbage.txt` start exiting 0.
6. Put the sniff in **one** place. `cli.rb#read_input_file` and
   `detect_and_parse` in `convert_command.rb`, `validate_command.rb` and
   `diagram_command.rb` need identical behaviour; four private copies drift.
   Extract `lib/elkrb/format_sniffer.rb` and call it from all four.
7. Two shapes the sniff must reject rather than accept as success, both found
   during review: a top-level JSON or YAML **sequence** (`[]`, `- id: g`)
   parses without raising but returns an Array, not a `Graph` — treat it as a
   failed parse; and lutaml-model 0.8.19 succeeds on any mapping, even one
   with no recognised keys, returning a graph whose every field is nil — treat
   that as a failed parse too.
8. `batch_command.rb`: after the summary at `:46-48`, exit non-zero when
   `error_count > 0`.
9. `exe/elkrb`: delete `require "bundler/setup"`.
10. `spec/elkrb/graphviz_wrapper_spec.rb`: replace every `receive(:system)`
    stub (`#render` at `:27`, stubs at `:34`, `:40`, `:46`, `:52`, `:60`,
    `:97`) with `with_fake_dot` argv assertions — argv equality, and that the
    metacharacter path produced no file. Rewrite
    the `#available?` examples (`:9` onward) to drive `PATH` (the fake-dot dir,
    or an empty dir with `ELKRB_DOT` unset) instead of stubbing
    `File.executable?`/`system`: after the PATH-only rewrite those stubs no
    longer drive `find_graphviz`, and an empty-dir `PATH` is deterministically
    unavailable on every host once the absolute candidates are gone. Add one
    `ELKRB_DOT`-override example. Rewrite the `#version` examples
    (`:106` onward; `:109` stubs the backtick method itself, dead once `Open3`
    is used) against the fake
    dot: teach 02's script to print
    `dot - graphviz version 2.44.1 (20200629.0846)` for `-V`, then assert the
    logged argv is `[dot, "-V"]` and `version == "2.44.1"`, and that `version`
    is nil under an empty-dir `PATH`. Point one `ELKRB_DOT` example at a copy
    of the fake dot inside a directory whose name contains a space — the old
    unquoted backtick interpolation would break on it, so that example is what
    actually proves the backticks are gone.
11. Specs first. Un-pend 02's four `RC10` examples, then add, in an S2
    `describe` section or `spec/elkrb/cli/shell_boundary_spec.rb`: `layout
    file.noext` with JSON content → exit 0; with YAML content → exit 0;
    `layout spec/fixtures/corpus/garbage.txt` → exit 1 with non-empty stderr;
    `batch` over a directory with one bad file → exit 1. Run them red first.

**Do not touch:** `validate` semantics (item 26, S20); option mapping and
`build_layout_options` (item 09, S5); `diagram --direction` and the flag →
option table (item 09).

## Done when

Done. What was verified:

- `bundle exec exe/elkrb layout; echo $?` → **1**.
- `bundle exec exe/elkrb layout missing.json` → stdout empty, stderr
  `Error: No such file or directory @ rb_sysopen - missing.json`, exit 1.
- `bundle exec exe/elkrb layout spec/fixtures/simple_graph.json --verbose
  2>/dev/null | ruby -rjson -e 'JSON.parse($stdin.read)'` → parses.
- The cli-security-1 repro from `## Facts` leaves **no** `PWNED` file. `dot`
  receives the literal path as one argv element and reports
  `Could not open "…/out.png; touch …/PWNED" for writing`, which the wrapper
  surfaces as `GraphvizNotFoundError`.
- `bundle exec rspec` on b9c6730 → **749 examples, 0 failures, 12 pending**.

Gates that were mandatory and what they found:

- **thermo-nuclear** — run on plan and diff.
- **dependency-contract-check** — mandatory, and it constructed the real
  objects: Thor's `exit_on_failure?` genuinely changing the process exit
  status for a missing required option and an unknown command;
  `Lutaml::Model::InvalidFormatError` confirmed as what
  `Graph.from_json("not json")` and `Graph.from_yaml(":\n  - [")` actually
  raise; `system(*argv)` with a `;` inside an element.
- **execution-diff** — mandatory. Driver: `bundle exec rake
  "corpus:dump[<dir>]"` (quote the brackets) on d8275ce, this branch's own
  merge base, and on the branch, then `diff -r` of the two dump directories.
  The rake exit status is informational and was not chained on.
  **Intended differences: none in the corpus dump.** `corpus_runner.rb` calls
  `Elkrb.layout` directly and never goes through `exe/elkrb` or `Cli`, so this
  slice's diffs live entirely in `cli_spec.rb`, `shell_boundary_spec.rb` and
  `graphviz_wrapper_spec.rb` — the CLI exit-code and stream matrix. Result:
  zero diff, re-confirmed after each of the four fix rounds.
- **Codex** — APPROVE.
- **copilot-review** — run last.
- **Gate A** found 2 High and 2 Low; all fixed. The High that mattered: the
  four sniff sites had drifted, fixed by extracting the shared
  `lib/elkrb/format_sniffer.rb`.
- **Gate B** round 1 found 1 Medium — an Array leaking out of the sniff.
  Fixed. Round 2: APPROVE.

Recorded for later items, not fixed here — **except the first, which was
subsequently fixed on this branch at `d4cba2e` ("propagate render failures
and reject malformed shapes"). The paragraph below describes the state
before that commit.**

- **`batch` still reports success when Graphviz rendering itself fails.**
  `diagram_command.rb#render_to_image` rescues
  `GraphvizWrapper::GraphvizNotFoundError` with a `warn` and a bare `return`,
  so `BatchCommand#process_file` never sees an exception and counts the file
  as a success. Real and reachable — `batch`'s default `--format` is `svg`.
  Rejected here as out of scope: this item's batch change is "propagate the
  loop's existing `error_count` to the exit code", and `render_to_image`'s
  error handling belongs to item 36 (S29) or its own fix.
- The absolute-candidate fallback for `dot` is gone and `ELKRB_DOT` is the
  documented override for a `dot` off `PATH`. Users with `dot` on `PATH` see
  no change, so this goes in the PR body as a note, not as a `## Breaking`
  section.
