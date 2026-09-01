#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "timeout"
require_relative "../../lib/elkrb"

# Runs every corpus case through Elkrb.layout and records pass/error/timeout.
#
# The corpus is every spec/fixtures/*.json (bare graph, default algorithm
# "layered"), every spec/fixtures/corpus/*.json (wrapper {"algorithm":,
# "graph":}; the non-JSON fixtures in that directory, bom.elkt and
# garbage.txt, are deliberately excluded here -- they belong to
# spec/elkrb/cli_spec.rb's "input format detection" examples, which read
# them through the CLI, not through layout), and every entry of each
# spec/cross_validation/fixtures/*/imported_tests.json file. This is the
# single enumeration every later slice's execution-diff gate diffs
# against, so `.cases` is the one place that logic lives.
#
# Every case's file is always written, regardless of outcome -- `run`'s
# own exit status (via the CLI entrypoint below) is informational only,
# never something a caller chains on; XD compares dump directories, not
# exit codes. A case's wrapper may carry "expect": "error" to mark a
# deliberate, permanent crasher (tracked by its own RC/decision id
# elsewhere, e.g. corpus_spec.rb's KNOWN_FAILURES) rather than a fresh
# regression -- the CLI entrypoint's exit code reflects only failures
# that were NOT declared expected.
class CorpusRunner
  ROOT = File.expand_path("../..", __dir__)
  TIMEOUT_SECONDS = 30

  # The dump's index file is "summary.json", so this is the one case id a
  # dump directory cannot hold.
  RESERVED_ID = "summary"

  # A fixed seed reseeded before every case. force/random call unseeded
  # Kernel#rand, so without this, two dumps of identical, unchanged code
  # would disagree on those cases, breaking every later slice's
  # execution-diff comparison. Reseeding right before each case (not once
  # per run) keeps one case's random-number consumption from shifting a
  # later case's output. elk.randomSeed support is S14's job; this only
  # makes this runner's own dumps reproducible in the meantime. The value
  # itself is arbitrary -- any fixed integer works equally well.
  DETERMINISTIC_SEED = 20_260_819

  # Case ids are fixture basenames, so dumping into one of the corpus's own
  # source directories would overwrite the tracked inputs with layout
  # output.
  SOURCE_DIRS = [
    File.join(ROOT, "spec/fixtures"),
    File.join(ROOT, "spec/cross_validation/fixtures"),
  ].freeze

  # `expect` is nil for every ordinary case; a corpus wrapper (or an
  # imported_tests.json entry) may set "expect": "error" to mark a
  # deliberate, permanent crasher (duplicate_ids: RC4/S7; the two SPOrE
  # cases, which resolve to their algorithms and then crash on nil
  # arithmetic inside them) so a healthy dump's exit status
  # reflects unexpected regressions, not known, already-tracked bugs.
  Case = Struct.new(:id, :algorithm, :graph, :expect, keyword_init: true)

  class << self
    def cases
      all_cases = [
        *top_level_fixture_cases,
        *corpus_fixture_cases,
        *imported_cases,
      ]
      refuse_duplicate_ids!(all_cases)
      refuse_reserved_id!(all_cases)
      all_cases
    end

    # `outdir` is expanded once, here, so the guard and every write that
    # follows are talking about the same directory: source_directory?
    # compares expanded paths, and comparing one path while writing to
    # another is how a guard ends up passing for a directory nobody wrote
    # to.
    def run(outdir, timeout: TIMEOUT_SECONDS)
      outdir = File.expand_path(outdir)
      refuse_source_directory!(outdir)
      claim_output_directory!(outdir)
      corpus = cases
      prune_stale_dumps(outdir, corpus)

      summary = new_summary
      corpus.each { |kase| dump_case(kase, summary, outdir, timeout) }

      summary["unexpected_failures"] = unexpected_failure?(summary)
      write_json(File.join(outdir, "summary.json"), summary)
      summary
    end

    # 1 when `summary` has a failure that was not declared "expect" on its
    # wrapper, OR when the run found no cases at all, and 0 otherwise. The
    # empty case matters as much as the failing one: a corpus that silently
    # stopped being discovered used to exit 0 and read as green.
    #
    # Extracted so the CLI entrypoint's exit decision is directly testable --
    # calling `exit` from inside an example would end the test run, not just
    # the example.
    def exit_code(summary)
      summary["unexpected_failures"] ? 1 : 0
    end

    # The runner DELETES files it believes are stale, so it may only write
    # into a directory that is its own. An empty or absent directory becomes
    # its own and gets the marker; a directory already carrying the marker is
    # its own already. Anything else is somebody's working directory and is
    # refused, because a `summary.json` that merely looks right is not
    # provenance -- a run once adopted an unrelated one and deleted a file
    # named in it.
    OWNER_MARKER = ".elkrb-corpus-dump"

    def claim_output_directory!(outdir)
      if File.directory?(outdir)
        marker = File.join(outdir, OWNER_MARKER)
        return if File.file?(marker)

        unless Dir.empty?(outdir)
          raise ArgumentError,
                "#{outdir} was not written by the corpus runner and holds " \
                "files it does not own. Name a new or empty directory " \
                "instead -- `rake 'corpus:dump[dir]'`, or the positional " \
                "argument to this script -- or clear that one yourself."
        end
      end

      FileUtils.mkdir_p(outdir)
      File.write(File.join(outdir, OWNER_MARKER), <<~TEXT)
        Written by spec/cross_validation/corpus_runner.rb.
        Its presence is what lets the runner delete stale dumps here.
        Delete this file and the directory stops being the runner's.
      TEXT
    end

    # A case id reaches the filesystem, and importers are a documented
    # extension point, so an id is not assumed to be a bare name. An id of
    # `../victim` used to resolve outside `outdir` and overwrite a sibling.
    def case_path(outdir, id)
      name = "#{id}.json"
      path = File.expand_path(name, outdir)

      unless File.basename(name) == name && File.dirname(path) == outdir
        raise ArgumentError,
              "case id #{id.inspect} does not name a file inside the output " \
              "directory. Ids become filenames, so they may not contain a " \
              "path separator or traverse upwards."
      end

      path
    end

    # True when `outdir` is, or sits under, one of SOURCE_DIRS.
    #
    # Comparing path strings is not enough. On a case-insensitive
    # filesystem spec/Fixtures IS spec/fixtures, and a symlink aliases
    # either one under any name at all; both slip past a lexical prefix
    # check and would let a dump overwrite the tracked inputs. Compare by
    # device+inode instead, which is what "the same directory" actually
    # means, and walk the destination's ancestors, because an outdir that
    # does not exist yet still sits under an existing -- possibly aliased
    # -- parent.
    #
    # Public so its own specs can assert the rule without calling `run`.
    # Pointing `run` at spec/fixtures is exactly the accident this guard
    # exists to stop, and a test that does it for real deletes the
    # fixtures the moment the guard regresses.
    def source_directory?(outdir)
      ancestor_paths(File.expand_path(outdir))
        .any? { |dir| SOURCE_DIRS.any? { |src| File.identical?(dir, src) } }
    end

    private

    def refuse_source_directory!(outdir)
      return unless source_directory?(outdir)

      raise ArgumentError,
            "refusing to dump into a corpus source directory: #{outdir}"
    end

    def new_summary
      { "total" => 0, "ok" => 0, "error" => 0, "timeout" => 0, "cases" => [] }
    end

    # A failure whose wrapper did not declare it. Derived from the recorded
    # entries so summary.json and the exit code cannot disagree.
    # An EMPTY run is a failure, not a pass. A corpus that silently stopped
    # being found wrote `total: 0` and exited 0, so a caller could not tell
    # "everything passed" from "nothing ran" -- and CI reads the exit code.
    def unexpected_failure?(summary)
      return true if summary["total"].to_i.zero?

      summary["cases"].any? do |entry|
        entry["status"] != "ok" && !entry["expected"]
      end
    end

    def refuse_duplicate_ids!(all_cases)
      duplicates = all_cases.map(&:id).tally.select { |_, n| n > 1 }.keys
      return if duplicates.empty?

      raise ArgumentError,
            "duplicate corpus case ids: #{duplicates.join(', ')}"
    end

    # Every case is dumped to "#{id}.json", so a case called "summary"
    # would write the dump's own index and then be overwritten by it.
    def refuse_reserved_id!(all_cases)
      clashing = all_cases.find { |kase| kase.id.to_s.casecmp?(RESERVED_ID) }
      return unless clashing

      # Compared case-INSENSITIVELY on purpose. macOS and Windows resolve
      # `SUMMARY.json` and `summary.json` to one file, so an id of "SUMMARY"
      # slipped this guard and then had its payload overwritten by the dump's
      # own index. Measured: both names came back File.identical? and the file
      # on disk held the summary, not the case.
      #
      # This refuses "SUMMARY" on a case-sensitive filesystem too, where the
      # two names really are different files. A corpus that works on Linux and
      # quietly corrupts a case on macOS is the worse outcome.
      raise ArgumentError,
            "corpus case id #{clashing.id.inspect} collides with " \
            "#{RESERVED_ID}.json, which the runner writes itself"
    end

    # Counts the case, records its summary entry, and writes its dump. The
    # dump is written whatever the outcome; see the class comment on why the
    # exit status is informational only.
    def dump_case(kase, summary, outdir, timeout)
      status, payload = run_case(kase, timeout)
      summary["total"] += 1
      summary[status] += 1
      summary["cases"] << case_entry(kase, status)
      write_json(case_path(outdir, kase.id), payload)
    end

    # "expected" is recorded only for a failure the wrapper declared, so a
    # reader of summary.json can tell a tracked bug from a fresh regression
    # without consulting the corpus.
    def case_entry(kase, status)
      entry = {
        "id" => kase.id,
        "algorithm" => kase.algorithm,
        "status" => status,
      }
      entry["expected"] = true if status != "ok" && kase.expect == status
      entry
    end

    # Both dump sites go through here: a case file and summary.json have to
    # agree on the canonical format, which is what every later slice diffs.
    def write_json(path, value)
      File.write(path, JSON.pretty_generate(value))
    end

    def ancestor_paths(path)
      paths = []
      loop do
        paths << path
        parent = File.dirname(path)
        break if parent == path

        path = parent
      end
      paths
    end

    # A dump directory is a canonical snapshot that XD compares with
    # `diff -r`, and validate:run always reuses tmp/corpus. Left alone, a
    # case that was renamed or dropped keeps its old file there and every
    # later comparison reports a difference that no longer exists.
    #
    # Deleting is aimed at whatever path a caller passed on the command
    # line, so the delete set is the ids the PREVIOUS summary.json recorded
    # minus the ids this run is about to write. A file this runner never
    # wrote is then not a candidate at all.
    #
    # Choosing the set the other way round -- every *.json that is not a
    # current case -- made the first run authorise the second. `run` is
    # what writes summary.json, so pointing it twice at a directory of
    # someone else's JSON swept it: run 1 left the summary that run 2 read
    # as proof the directory was ours.
    #
    # The loop walks what the directory actually holds, so a recorded id is
    # only ever resolved against a name in it; nothing outside can be named
    # by a summary this runner did not write. `base:` scopes the glob to
    # the directory itself, which is taken literally -- joining the path
    # into the pattern instead let a metacharacter in a caller-supplied
    # `outdir` reach a sibling.
    def prune_stale_dumps(outdir, corpus)
      dropped = recorded_case_ids(outdir) - corpus.map(&:id)
      stale = dropped.map { |id| "#{id}.json" }
      Dir.glob("*.json", base: outdir).each do |name|
        next unless stale.include?(name)

        path = File.join(outdir, name)
        File.delete(path) if File.file?(path)
      end
    end

    # The case ids the previous dump recorded, or none when this directory
    # holds no summary of ours to read them from. A summary that is absent,
    # unreadable, not JSON, or not the shape `new_summary` writes prunes
    # nothing: deleting on a guess is the failure this set exists to avoid.
    def recorded_case_ids(outdir)
      summary = JSON.parse(File.read(File.join(outdir, "summary.json")))
      entries = summary.is_a?(Hash) ? summary["cases"] : nil
      return [] unless entries.is_a?(Array)

      entries.grep(Hash).filter_map { |entry| entry["id"] }
    rescue SystemCallError, JSON::ParserError
      []
    end

    # Kernel's generator is process-wide and the spec suite seeds it
    # deliberately, so the seed is put back on the way out.
    #
    # Putting the SEED back is not the same as putting the STREAM back, and
    # this comment used to claim it was. `srand(previous_seed)` restarts that
    # seed's sequence from its first value rather than resuming where the
    # caller had reached -- measured, the next value repeated 0.929616...
    # instead of continuing to 0.316375... Ruby exposes no way to snapshot the
    # global generator's position, so what is guaranteed here is only that a
    # later `srand`-based reproduction sees the seed it expects.
    def run_case(kase, timeout)
      previous_seed = Kernel.srand(DETERMINISTIC_SEED)
      result = Timeout.timeout(timeout) do
        Elkrb.layout(kase.graph, algorithm: kase.algorithm)
      end
      ["ok", canonicalize(JSON.parse(result.to_json))]
    rescue Timeout::Error
      ["timeout", { "error" => "Timeout" }]
    rescue StandardError, SystemStackError => e
      ["error", { "error" => "#{e.class}: #{e.message}" }]
    ensure
      Kernel.srand(previous_seed)
    end

    def canonicalize(value)
      case value
      when Hash
        value.transform_values { |v| canonicalize(v) }.sort.to_h
      when Array
        value.map { |v| canonicalize(v) }
      when Float
        value.round(6)
      else
        value
      end
    end

    # `base:` scopes the glob to `dir` itself, which is taken literally. Every
    # corpus source directory is built from ROOT -- the checkout path, wherever
    # the repo happens to sit -- so joining it into the pattern instead let a
    # glob metacharacter in it be interpreted rather than matched: the glob and
    # the later `File.read` disagreed about which directory was meant. A `*` or
    # `?` still matched its own directory and quietly added a sibling's files;
    # a `[...]`, `{...}` or unclosed `[` did not match it, so the listing was
    # entirely foreign or empty. This list is what `run` prunes against, so a
    # mislisting here becomes a delete in `prune_stale_dumps`.
    def fixture_paths(dir, pattern)
      Dir.glob(pattern, base: dir).map { |name| File.join(dir, name) }
    end

    def top_level_fixture_cases
      fixture_paths(File.join(ROOT, "spec/fixtures"), "*.json").map do |path|
        Case.new(
          id: File.basename(path, ".json"),
          algorithm: "layered",
          graph: JSON.parse(File.read(path)),
        )
      end
    end

    def corpus_fixture_cases
      dir = File.join(ROOT, "spec/fixtures/corpus")
      fixture_paths(dir, "*.json").map do |path|
        wrapper = JSON.parse(File.read(path))
        Case.new(
          id: File.basename(path, ".json"),
          algorithm: wrapper.fetch("algorithm", "layered"),
          graph: wrapper.fetch("graph"),
          expect: wrapper["expect"],
        )
      end
    end

    # Sorted by whole path. The wildcard here is a directory component, and
    # for that shape glob's own order is component-wise, so the two disagree:
    # given elkjs/, elkjs-2/ and java_elk/, glob returns elkjs before elkjs-2
    # while sort returns the reverse. The case list is the fixed enumeration
    # every later slice diffs against, so it is ordered explicitly.
    def imported_cases
      dir = File.join(ROOT, "spec/cross_validation/fixtures")
      fixture_paths(dir, "*/imported_tests.json").sort.flat_map do |path|
        JSON.parse(File.read(path)).map do |entry|
          Case.new(
            id: entry.fetch("id"),
            algorithm: entry.fetch("algorithm", "layered"),
            graph: entry.fetch("graph"),
            expect: entry["expect"],
          )
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  outdir = ARGV[0] or abort "usage: corpus_runner.rb <outdir>"
  summary = CorpusRunner.run(outdir)
  puts "corpus: #{summary['ok']} ok, #{summary['error']} error, " \
       "#{summary['timeout']} timeout (#{summary['total']} total)"
  # Every case's dump is always written first, regardless of outcome --
  # the exit status is a convenience signal, not something XD (or any
  # caller) should chain on: it distinguishes a genuine regression from
  # the corpus's permanent, individually-tracked known crashers (each
  # marked "expect": "error" in its own wrapper).
  exit CorpusRunner.exit_code(summary)
end
