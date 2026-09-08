# frozen_string_literal: true

# Re-captures every sirena consumer fixture in this directory.
#
# Do not run this by hand. Run `rake fixtures:sirena`, which points it at
# a sirena checkout and runs it inside sirena's own bundle.
#
#   ruby capture.rb <this directory> <output directory>
#
# It uses only sirena's public classes: DiagramRegistry, the parser and
# the transform. The diagram type is listed below, so sirena's private
# type detection is never called.

require "date"
require "fileutils"
require "json"
require "sirena"
require "tmpdir"

# Everything this script does lives in methods that RAISE. Nothing in the
# module decides an exit status, because requiring the file used to run
# the command-line body: a plain `require` with an empty ARGV reached the
# usage `abort` and took the requiring process down with SystemExit 1.
# Only the entry point at the bottom of the file may exit.
module SirenaCapture
  class Error < StandardError; end

  TYPES = {
    "c4_nested" => :c4,
    "class_flat" => :class_diagram,
    "er" => :er_diagram,
    "flowchart_lr" => :flowchart,
    "flowchart_td" => :flowchart,
    "sequence" => :sequence,
    "state" => :state_diagram,
    "user_journey" => :user_journey,
  }.freeze

  module_function

  # Produces every graph first and publishes them only once all of them
  # exist. Writing inside the transform loop left the directory holding
  # two different captures when a later transform raised -- measured, a
  # failure on the second type left c4_nested.json already overwritten.
  def capture(fixture_dir, out_dir)
    graphs = TYPES.map do |name, type|
      [name, graph_for(fixture_dir, name, type)]
    end
    publish(graphs, out_dir)
  end

  def graph_for(fixture_dir, name, type)
    handlers = Sirena::DiagramRegistry.get(type)
    raise Error, "sirena has no handlers for diagram type #{type}" if
      handlers.nil?

    source = File.join(fixture_dir, "src", "#{name}.mmd")
    diagram = handlers[:parser].new.parse(File.read(source))
    to_graph(handlers[:transform].new, diagram)
  end

  # Older sirena revisions take the date as a second argument. None of
  # these transforms read it, so it never reaches the output.
  def to_graph(transform, diagram)
    if transform.method(:to_graph).arity == 1
      transform.to_graph(diagram)
    else
      transform.to_graph(diagram, Date.today)
    end
  end

  # Stages every file inside a private directory this run creates, and
  # renames them into place only once all of them exist, so a failure
  # part-way through publishing leaves the committed fixtures exactly as
  # they were. `File.write` follows a symlink; `rename` replaces the link.
  #
  # The private staging directory is the design, not a detail. Staging
  # used to be `.<name>.json.<pid>.tmp` NEXT TO the target, which is a
  # predictable path in a directory other people own, and two defects came
  # out of that. A symlink pre-created there had the capture written
  # straight through it to the link's referent. A plain FILE pre-created
  # there made the run refuse to write and then DELETE that file on the
  # way out, because cleanup could not tell a path it had created from one
  # it had merely named. Both measured. Everything under `Dir.mktmpdir`
  # was created by this invocation, so removing all of it can never take
  # someone else's file with it -- and the backups live there too, for
  # exactly the same reason.
  def publish(graphs, out_dir)
    FileUtils.mkdir_p(out_dir)
    with_directory_lock(out_dir) { publish_locked(graphs, out_dir) }
  end

  def publish_locked(graphs, out_dir)
    staging = Dir.mktmpdir(".capture", out_dir)
    undone = []
    published = false
    staged = stage(graphs, staging, out_dir)
    refuse_unpublishable!(staged)
    staged.each { |row| replace(*row, undone) }
    published = true
  ensure
    settle(staging, undone, published)
  end

  # Two runs pointed at one output directory used to interleave -- measured
  # in a two-process probe that committed a.json from one run beside b.json
  # from the other, with both runs reporting success. The lock is taken on
  # the output DIRECTORY itself: `flock` works on any descriptor, and a
  # lock file would have to sit among the committed fixtures. Measured on
  # macOS only. If a platform ever refuses to open a directory read-only
  # the open RAISES here, before anything is staged, so the failure is
  # loud and the fixtures are untouched.
  def with_directory_lock(out_dir)
    File.open(out_dir, File::RDONLY) do |lock|
      lock.flock(File::LOCK_EX)
      begin
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end
  end

  # Each row carries the path its target will be backed up to, so `commit`
  # never has to invent one. A backup name derived from the target used to
  # land beside it as `<target>.<pid>.bak`, where it overwrote a file
  # already at that name and then deleted it -- measured. `bak.<n>` also
  # keeps a backup from ever looking like a `<name>.json` staged file.
  def stage(graphs, staging, out_dir)
    graphs.each_with_index.map do |(name, graph), index|
      tmp = File.join(staging, "#{name}.json")
      write_json(tmp, graph)
      [tmp, File.join(out_dir, "#{name}.json"),
       File.join(staging, "bak.#{index}")]
    end
  end

  # EXCL, not TRUNC. The staging directory is created fresh by this run
  # and is mode 0700, so nothing can be lying in wait at this path; EXCL
  # is what says so out loud, and it refuses rather than silently
  # overwriting should two rows ever claim one name.
  def write_json(tmp, graph)
    File.open(tmp, File::WRONLY | File::CREAT | File::EXCL) do |file|
      file.write("#{JSON.pretty_generate(graph)}\n")
    end
  end

  # `ensure`, not `rescue SystemCallError`. Ctrl-C raises Interrupt,
  # which that rescue did not catch: an interrupted publish left a.json
  # updated, b.json missing and both backups on disk -- measured. An
  # ensure runs for EVERY exit, so the undo does not depend on
  # enumerating which exceptions an interruption can arrive as.
  #
  # Sweeping the staging directory is what makes the backups disposable,
  # so it may only happen once nothing in there is still needed. The
  # block form of `Dir.mktmpdir` removed it UNCONDITIONALLY: one SIGINT
  # during restoration stopped the undo at that row and the sweep then
  # took every backup it had not yet put back, leaving the output
  # directory EMPTY -- measured. When anything is stranded the directory
  # stays and its path is printed, because a backup nobody can find is
  # the same as no backup.
  def settle(staging, undone, published)
    return if staging.nil?

    stranded = published ? [] : restore_all(undone)
    return FileUtils.remove_entry(staging) if stranded.empty?

    warn "capture could not restore #{stranded.join(', ')} -- " \
         "the originals are in #{staging}"
  end

  # Attempts EVERY restoration whatever any one of them raises, and
  # returns the targets still not back in place. Stopping at the first
  # failure left the remaining fixtures missing with their only copies
  # about to be swept. Interrupt is named beside StandardError because
  # Ctrl-C is the interruption this path exists for and is not one.
  def restore_all(undone)
    undone.filter_map do |target, stashed, existed|
      roll_back(target, stashed, existed)
      nil
    rescue StandardError, Interrupt
      target
    end
  end

  # The undo entry is recorded BEFORE anything moves, and it records
  # whether the target was THERE, because that is the one thing rollback
  # cannot work out afterwards. Recording it after the stash rename left a
  # window an Interrupt fitted into: the original was already sitting in
  # the backup with no entry naming it, so rollback ran with nothing to
  # restore and the fixture stayed missing -- measured with a TracePoint.
  def replace(tmp, target, stashed, undone)
    existed = present?(target)
    undone.unshift([target, stashed, existed])
    File.rename(target, stashed) if existed
    File.rename(tmp, target)
    puts "wrote #{target}"
  end

  # Renaming one at a time is not all-or-nothing on its own: a DIRECTORY
  # standing where a fixture belongs made the second rename raise EISDIR
  # with the first target already replaced -- measured. This rejects that
  # case while the output directory is still untouched; the undo log
  # covers everything it cannot see.
  #
  # A rename may replace a regular file or nothing at all, and a symlink
  # to a regular file counts as a regular file here because `File.file?`
  # follows it -- the rename then replaces the LINK, not its referent. A
  # link to a directory reads as neither, so it is refused along with a
  # real directory, while the output directory is still untouched.
  def refuse_unpublishable!(staged)
    blocked = staged.map { |row| row[1] }.reject do |target|
      !File.exist?(target) || File.file?(target)
    end
    return if blocked.empty?

    raise Error, "refusing to publish: #{blocked.join(', ')} " \
                 "is not a regular file"
  end

  # `File.exist?` FOLLOWS a symlink, so a dangling link at the target read
  # as "nothing here" and rollback deleted it instead of putting it back
  # -- measured. What has to be restored is whatever DIRECTORY ENTRY was
  # there, link or file, which is what `symlink?` adds.
  def present?(path)
    File.exist?(path) || File.symlink?(path)
  end

  # Asks the filesystem which side of the stash rename this row stopped
  # on rather than assuming the rename ran. An ABSENT backup for a target
  # that existed means the original never moved and is still sitting at
  # the target, so removing the target there would destroy the very file
  # this exists to restore.
  def roll_back(target, stashed, existed)
    unless existed
      FileUtils.rm_f(target)
      return
    end
    return unless present?(stashed)

    FileUtils.rm_f(target)
    File.rename(stashed, target)
  end
end

if __FILE__ == $PROGRAM_NAME
  fixture_dir, out_dir = ARGV
  abort "usage: ruby capture.rb <fixture dir> <output dir>" if out_dir.nil?

  begin
    SirenaCapture.capture(fixture_dir, out_dir)
  rescue SirenaCapture::Error => e
    abort e.message
  end
end
