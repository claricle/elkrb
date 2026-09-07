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

fixture_dir, out_dir = ARGV
abort "usage: ruby capture.rb <fixture dir> <output dir>" if out_dir.nil?
FileUtils.mkdir_p(out_dir)

TYPES.each do |name, type|
  handlers = Sirena::DiagramRegistry.get(type)
  abort "sirena has no handlers for diagram type #{type}" if handlers.nil?

  source = File.join(fixture_dir, "src", "#{name}.mmd")
  diagram = handlers[:parser].new.parse(File.read(source))
  transform = handlers[:transform].new

  # Older sirena revisions take the date as a second argument. None of
  # these transforms read it, so it never reaches the output.
  graph =
    if transform.method(:to_graph).arity == 1
      transform.to_graph(diagram)
    else
      transform.to_graph(diagram, Date.today)
    end

  target = File.join(out_dir, "#{name}.json")
  File.write(target, "#{JSON.pretty_generate(graph)}\n")
  puts "wrote #{target}"
end
