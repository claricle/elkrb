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
  def publish(graphs, out_dir)
    FileUtils.mkdir_p(out_dir)
    staged = graphs.to_h { |name, graph| stage(out_dir, name, graph) }
    staged.each do |tmp, target|
      File.rename(tmp, target)
      puts "wrote #{target}"
    end
  ensure
    staged&.each_key { |tmp| FileUtils.rm_f(tmp) }
  end

  def stage(out_dir, name, graph)
    target = File.join(out_dir, "#{name}.json")
    tmp = File.join(out_dir, ".#{name}.json.#{Process.pid}.tmp")
    File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC) do |file|
      file.write("#{JSON.pretty_generate(graph)}\n")
    end
    [tmp, target]
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
