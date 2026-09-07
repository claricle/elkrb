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

  # Stages every file beside its target and renames them into place only
  # after all of them have been written, so a failure part-way through
  # publishing leaves the committed fixtures exactly as they were.
  # `File.write` follows a symlink; `rename` replaces the link itself.
  #
  # Each tmp path is recorded BEFORE its bytes are written, so a write
  # that dies part-way still leaves a path for `ensure` to remove. With
  # the recording after the write, a failure on the second graph left
  # both temp files behind -- measured.
  def publish(graphs, out_dir)
    FileUtils.mkdir_p(out_dir)
    staged = {}
    graphs.each do |name, graph|
      tmp, target = paths_for(out_dir, name)
      staged[tmp] = target
      write_json(tmp, graph)
    end
    commit(staged)
  ensure
    staged&.each_key { |tmp| FileUtils.rm_f(tmp) }
  end

  def paths_for(out_dir, name)
    [File.join(out_dir, ".#{name}.json.#{Process.pid}.tmp"),
     File.join(out_dir, "#{name}.json")]
  end

  # EXCL, not TRUNC. The staging path is predictable, and `CREAT|TRUNC`
  # FOLLOWS a symlink sitting there: a link pre-created at
  # `.a.json.<pid>.tmp` had the capture written straight through it to
  # the link's referent, and the link was then installed as a.json --
  # measured, a file outside the directory was overwritten. `CREAT|EXCL`
  # refuses any existing path, symlink included, before a byte is
  # written; NOFOLLOW would be redundant beside it.
  def write_json(tmp, graph)
    File.open(tmp, File::WRONLY | File::CREAT | File::EXCL) do |file|
      file.write("#{JSON.pretty_generate(graph)}\n")
    end
  end

  # Renames every staged file into place, and puts the directory back
  # the way it was if any rename fails. Renaming one at a time is not
  # all-or-nothing on its own: a DIRECTORY standing where a fixture
  # belongs made the second rename raise EISDIR with the first target
  # already replaced -- measured. `refuse_unpublishable!` rejects that
  # case before anything moves; the undo log covers the rest.
  def commit(staged)
    undone = []
    published = false
    refuse_unpublishable!(staged)
    staged.each { |tmp, target| replace(tmp, target, undone) }
    published = true
  ensure
    finish(undone, published)
  end

  # `ensure`, not `rescue SystemCallError`. Ctrl-C raises Interrupt,
  # which that rescue did not catch: an interrupted publish left a.json
  # updated, b.json missing and both backups on disk -- measured. An
  # ensure runs for EVERY exit, so the undo does not depend on
  # enumerating which exceptions an interruption can arrive as.
  def finish(undone, published)
    undone.each do |target, stashed|
      if published
        FileUtils.rm_f(stashed) if stashed
      else
        roll_back(target, stashed)
      end
    end
  end

  # The undo entry is recorded BEFORE the rename, so the file whose
  # rename is the one that failed gets rolled back too.
  def replace(tmp, target, undone)
    undone.unshift([target, stash(target)])
    File.rename(tmp, target)
    puts "wrote #{target}"
  end

  # A rename may replace a regular file, a symlink or nothing at all.
  # Anything else is refused while the directory is still untouched.
  def refuse_unpublishable!(staged)
    blocked = staged.each_value.reject do |target|
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

  def stash(target)
    return nil unless present?(target)

    stashed = "#{target}.#{Process.pid}.bak"
    File.rename(target, stashed)
    stashed
  end

  def roll_back(target, stashed)
    FileUtils.rm_f(target) if present?(target)
    File.rename(stashed, target) if stashed
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
