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
# "graph":}), and every entry of each spec/cross_validation/fixtures/*/
# imported_tests.json file. The non-JSON fixtures bom.elkt and garbage.txt
# belong to spec/elkrb/cli_spec.rb, which reads them through the CLI, so
# they are not cases here. `.cases` is the single enumeration every later
# slice's execution-diff gate diffs against.
#
# Every case's file is always written, whatever the outcome. `run`'s exit
# status (via the CLI entrypoint below) is informational only; XD compares
# dump directories, not exit codes. A wrapper may carry "expect": "error"
# to mark a deliberate, permanent crasher, so the exit code reflects only
# failures that were NOT declared expected.
#
# The history behind each guard here -- what broke, what was measured, and
# the attempts that were rejected -- is in
# TODO.remediation/02-corpus-cli-harness.md, section "Why the corpus
# runner's guards look the way they do".
class CorpusRunner
  ROOT = File.expand_path("../..", __dir__)
  TIMEOUT_SECONDS = 30

  # The dump's index file is "summary.json", so this is the one case id a
  # dump directory cannot hold.
  RESERVED_ID = "summary"

  # The runner DELETES files it believes are stale, so it may only write
  # into a directory that is its own. This marker is what says so, and it
  # is also the lock file two concurrent runs take turns on.
  OWNER_MARKER = ".elkrb-corpus-dump"

  OWNER_MARKER_TEXT = <<~TEXT
    Written by spec/cross_validation/corpus_runner.rb.
    Its presence is what lets the runner delete stale dumps here.
    Delete this file and the directory stops being the runner's.
  TEXT

  # A fixed seed reseeded before every case. force/random call unseeded
  # Kernel#rand, so without this two dumps of identical code would disagree
  # on those cases. Reseeding per case (not once per run) keeps one case's
  # random consumption from shifting a later case's output. The value is
  # arbitrary; any fixed integer works.
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
  # deliberate, permanent crasher, so a healthy dump's exit status reflects
  # unexpected regressions, not known, already-tracked bugs.
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
      refuse_colliding_file_names!(all_cases)
      all_cases
    end

    # `outdir` is expanded once, here, so the guard and every write that
    # follows are talking about the same directory.
    def run(outdir, timeout: TIMEOUT_SECONDS)
      outdir = File.expand_path(outdir)
      refuse_source_directory!(outdir)
      # Discovery and every id's SHAPE are checked before the claim. Both
      # can raise, and claiming creates the directory and prunes stale
      # dumps -- so doing it first deleted the last good dump and left a
      # claimed, empty directory behind for a corpus the runner then
      # refused.
      corpus = cases
      corpus.each { |kase| case_file_path(outdir, kase.id) }

      claim_output_directory!(outdir)
      with_directory_lock(outdir) { dump_corpus(outdir, corpus, timeout) }
    end

    # 1 when `summary` records an unexpected failure, 0 otherwise. What
    # counts as one is `unexpected_failure?`'s decision.
    #
    # Extracted so the CLI entrypoint's exit decision is directly testable:
    # calling `exit` inside an example would end the whole test run.
    def exit_code(summary)
      summary["unexpected_failures"] ? 1 : 0
    end

    # True when `outdir` is, or sits under, one of SOURCE_DIRS.
    #
    # Compared by device+inode, not by path string: on a case-insensitive
    # filesystem spec/Fixtures IS spec/fixtures, and a symlink aliases
    # either one under any name. Ancestors are walked because an outdir
    # that does not exist yet still sits under an existing -- possibly
    # aliased -- parent.
    #
    # Public so its own specs can assert the rule without calling `run`.
    def source_directory?(outdir)
      ancestor_paths(File.expand_path(outdir))
        .any? { |dir| SOURCE_DIRS.any? { |src| File.identical?(dir, src) } }
    end

    private

    # Pruning, the dumps and the final summary, all under the directory
    # lock, so a second run cannot interleave its writes with this one's
    # prune and leave files that summary.json does not describe.
    def dump_corpus(outdir, corpus, timeout)
      prune_stale_dumps(outdir, corpus)
      # AFTER pruning, immediately before the dumps. Written inside the
      # claim it was skipped on a second run (the claim returns early for a
      # directory it already owns), and pruning could delete an aliased
      # summary right after it was placed.
      place_summary_marker(outdir)

      summary = new_summary
      written = {}
      corpus.each { |kase| dump_case(kase, summary, outdir, timeout, written) }

      summary["unexpected_failures"] = unexpected_failure?(summary)
      write_json(File.join(outdir, "#{RESERVED_ID}.json"), summary)
      summary
    end

    def refuse_source_directory!(outdir)
      return unless source_directory?(outdir)

      raise ArgumentError,
            "refusing to dump into a corpus source directory: #{outdir}"
    end

    # An empty or absent directory becomes the runner's and gets the
    # marker; a directory already carrying the marker is its own already.
    # Anything else is somebody's working directory and is refused: a
    # `summary.json` that merely looks right is not provenance -- a run
    # once adopted an unrelated one and deleted a file named in it.
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
      write_file(File.join(outdir, OWNER_MARKER), OWNER_MARKER_TEXT)
    end

    # Two runs pointed at one directory used to interleave: one pruned and
    # wrote while the other was still dumping, so the directory held files
    # that neither summary.json described. The owner marker doubles as the
    # lock, so the second run waits instead. The previous summary is read
    # inside the lock, after it is taken, so pruning sees a settled
    # directory.
    def with_directory_lock(outdir)
      File.open(File.join(outdir, OWNER_MARKER), File::RDONLY) do |lock|
        lock.flock(File::LOCK_EX)
        begin
          yield
        ensure
          lock.flock(File::LOCK_UN)
        end
      end
    end

    # A placeholder so `refuse_summary_alias!` can ASK the filesystem
    # whether an id aliases this name rather than trying to predict the
    # answer. `run` overwrites it with the real summary at the end.
    def place_summary_marker(outdir)
      summary = File.join(outdir, "#{RESERVED_ID}.json")
      write_file(summary, "{}") unless File.exist?(summary)
    end

    # Does this id name the summary file? ASK, do not predict.
    #
    # A string guard cannot settle it: whether two spellings fold onto one
    # name depends on the volume and the locale, not on the bytes. Three
    # review rounds found three ids that fold on a real disk and not in
    # Ruby, and one that a UTF-8 reinterpretation wrongly claimed was a
    # collision. `summary.json` exists by the time any case is dumped, so a
    # colliding id is one whose path is already `File.identical?` to it.
    def refuse_summary_alias!(outdir, path, id)
      summary = File.join(outdir, "#{RESERVED_ID}.json")
      return if path == summary
      return unless File.exist?(path) && File.exist?(summary)
      return unless File.identical?(path, summary)

      raise ArgumentError,
            "case id #{id.inspect} names the same file as " \
            "#{RESERVED_ID}.json on this filesystem, which the runner " \
            "writes itself. Rename the case."
    end

    # Two ids whose paths turn out to be one file on this volume. The
    # cheap ASCII check in `refuse_colliding_file_names!` cannot see a
    # non-ASCII fold, and the second dump would silently overwrite the
    # first while summary.json still counted both cases.
    def refuse_alias_of_written_case!(path, id, written)
      twin = written.find { |other, _| File.identical?(other, path) }
      return unless twin

      raise ArgumentError,
            "case ids #{twin.last.inspect} and #{id.inspect} name the same " \
            "file on this filesystem, so one dump would overwrite the " \
            "other. Rename one of the cases."
    end

    # Where this case is dumped: the id's shape, plus the filesystem's own
    # answer to "does this id name summary.json here?".
    def case_path(outdir, id)
      path = case_file_path(outdir, id)
      refuse_summary_alias!(outdir, path, id)
      path
    end

    # The id's shape only. Raises for anything that would not land inside
    # `outdir` as its own file. Touches no directory, so `run` can check
    # every id before it claims or prunes anything.
    def case_file_path(outdir, id)
      text = id.to_s
      # `strip`, `casecmp?` and friends RAISE on invalid bytes rather than
      # answering, so such an id used to surface Ruby's own "invalid byte
      # sequence" from deep inside a guard, after the directory was already
      # claimed. Refuse it here, with the same message as the other
      # unusable ids.
      refuse_unusable_id!(id) unless text.valid_encoding?

      name = "#{text}.json"
      # `File.join`, not `expand_path`: expand_path performs ~ and ~user
      # expansion, so an id beginning with ~ either escaped before the
      # guard ran or raised Ruby's own "user doesn't exist".
      path = File.join(outdir, name)

      # An EMPTY id passes both shape checks -- `".json"` has no separator
      # and its dirname is `outdir` -- and would quietly write
      # `outdir/.json`, a dotfile no listing shows.
      usable = !text.strip.empty? &&
        File.basename(name) == name &&
        File.dirname(path) == outdir
      refuse_unusable_id!(id) unless usable

      path
    end

    def refuse_unusable_id!(id)
      raise ArgumentError,
            "case id #{id.inspect} does not name a file inside the output " \
            "directory. Ids become filenames, so they may not be blank, " \
            "contain a path separator, traverse upwards, or carry bytes " \
            "that are invalid in their own encoding."
    end

    def new_summary
      { "total" => 0, "ok" => 0, "error" => 0, "timeout" => 0, "cases" => [] }
    end

    # A failure whose wrapper did not declare it. Derived from the recorded
    # entries so summary.json and the exit code cannot disagree.
    # An EMPTY run is a failure, not a pass: a corpus that silently stopped
    # being found wrote `total: 0` and exited 0, so a caller could not tell
    # "everything passed" from "nothing ran".
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

    # The ids are DIFFERENT and their file names are the same: the integer
    # 1 and the string "1" both dump to 1.json, and on macOS or Windows so
    # do "Foo" and "foo". One dump then overwrote the other while
    # summary.json still counted two cases, so a case vanished from the
    # snapshot every later slice diffs against.
    #
    # ASCII-only folding, like `reserved_id?`. This refuses "Foo"/"foo" on
    # a case-sensitive filesystem too, where they really are two files. A
    # corpus that works on Linux and quietly loses a case on macOS is the
    # worse outcome. Folds beyond ASCII are the filesystem's answer to
    # give, and `refuse_alias_of_written_case!` asks it at dump time.
    def refuse_colliding_file_names!(all_cases)
      groups = all_cases.group_by { |kase| kase.id.to_s.b.downcase }
      clashing = groups.values.find { |group| group.size > 1 }
      return unless clashing

      refuse_colliding_ids!(clashing.map(&:id))
    end

    def refuse_colliding_ids!(ids)
      raise ArgumentError,
            "corpus case ids #{ids.map(&:inspect).join(', ')} become the " \
            "same dump file name, so one case would overwrite the other. " \
            "Rename one of them."
    end

    # Every case is dumped to "#{id}.json", so a case called "summary"
    # would write the dump's own index and then be overwritten by it.
    # A CHEAP early guard, ASCII case only, run before any directory is
    # touched, so the obvious "summary"/"SUMMARY" fails with a clear
    # message. It does NOT decide the real question; that is
    # `refuse_summary_alias!`'s job. `String#b` keeps it to ASCII and never
    # raises, whatever the encoding.
    def reserved_id?(id)
      id.to_s.b.casecmp?(RESERVED_ID.b)
    end

    def refuse_reserved_id!(all_cases)
      clashing = all_cases.find { |kase| reserved_id?(kase.id) }
      return unless clashing

      # Case-INSENSITIVE on purpose. macOS and Windows resolve
      # `SUMMARY.json` and `summary.json` to one file, so an id of
      # "SUMMARY" slipped this guard and had its payload overwritten by the
      # dump's own index. Refusing it on a case-sensitive filesystem too is
      # the lesser evil.
      raise ArgumentError,
            "corpus case id #{clashing.id.inspect} collides with " \
            "#{RESERVED_ID}.json, which the runner writes itself"
    end

    # Counts the case, records its summary entry, and writes its dump. The
    # dump is written whatever the outcome; see the class comment on why
    # the exit status is informational only.
    def dump_case(kase, summary, outdir, timeout, written)
      path = case_path(outdir, kase.id)
      refuse_alias_of_written_case!(path, kase.id, written)

      status, payload = run_case(kase, timeout)
      summary["total"] += 1
      summary[status] += 1
      summary["cases"] << case_entry(kase, status)
      write_json(path, payload)
      written[path] = kase.id
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
      write_file(path, JSON.pretty_generate(value))
    end

    # Writes through a temp file in the same directory and renames it over
    # the target. `File.write` FOLLOWS a symlink, so a link sitting in a
    # directory the runner owns sent a dump straight out of it -- measured,
    # a case wrote over /tmp/probe_symlink/victim.txt. `rename` replaces
    # the link itself, so nothing outside the directory is touched.
    def write_file(path, text)
      dir = File.dirname(path)
      tmp = File.join(dir, ".#{File.basename(path)}.#{Process.pid}.tmp")
      File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC) do |file|
        file.write(text)
      end
      File.rename(tmp, path)
    ensure
      FileUtils.rm_f(tmp) if tmp
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
    # The delete set is the ids the PREVIOUS summary.json recorded minus
    # the ids this run is about to write, so a file this runner never wrote
    # is not a candidate at all. Choosing it the other way round -- every
    # *.json that is not a current case -- made run 1 authorise run 2 and
    # sweep a directory of someone else's JSON.
    #
    # `base:` scopes the glob to the directory itself, which is taken
    # literally: joining the path into the pattern let a metacharacter in a
    # caller-supplied `outdir` reach a sibling.
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
      summary = JSON.parse(
        File.read(File.join(outdir, "#{RESERVED_ID}.json")),
      )
      entries = summary.is_a?(Hash) ? summary["cases"] : nil
      return [] unless entries.is_a?(Array)

      entries.grep(Hash).filter_map { |entry| entry["id"] }
    rescue SystemCallError, JSON::ParserError
      []
    end

    # Kernel's generator is process-wide and the spec suite seeds it
    # deliberately, so the seed is put back on the way out.
    #
    # Putting the SEED back is not the same as putting the STREAM back.
    # `srand(previous_seed)` restarts that seed's sequence from its first
    # value rather than resuming where the caller had reached, and Ruby
    # exposes no way to snapshot the global generator's position. What is
    # guaranteed is only that a later `srand`-based reproduction sees the
    # seed it expects.
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

    # `base:` scopes the glob to `dir`, which is taken literally. Every
    # corpus source directory is built from ROOT -- the checkout path -- so
    # joining it into the pattern let a glob metacharacter in it be
    # interpreted rather than matched, and the glob and the later
    # `File.read` disagreed about which directory was meant. This list is
    # what `run` prunes against, so a mislisting here becomes a delete.
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
    # for that shape glob's own order is component-wise, so the two
    # disagree: given elkjs/, elkjs-2/ and java_elk/, glob returns elkjs
    # before elkjs-2 while sort returns the reverse. The case list is the
    # fixed enumeration every later slice diffs against, so it is ordered
    # explicitly.
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
  # Every case's dump is always written first, whatever the outcome -- the
  # exit status is a convenience signal, not something XD (or any caller)
  # should chain on. It tells a genuine regression from the corpus's
  # permanent, individually-tracked known crashers.
  exit CorpusRunner.exit_code(summary)
end
