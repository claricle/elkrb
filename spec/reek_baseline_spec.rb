# frozen_string_literal: true

require "reek"
# reek uses Pathname but does not require it -- `grep -rn 'require "pathname"'`
# over the installed gem returns nothing -- so this file must not rely on
# something else in the process having loaded it.
require "pathname"
require "yaml"

# `.reek.yml` is a generated todo baseline, and reek matches a String
# exclusion as an UNANCHORED SUBSTRING of a method's fully qualified name --
# `reek-6.5.0/lib/reek/context/code_context.rb:131` does
# `Regexp.quote(candidate)` and then `/#{candidate}/ =~ my_fq_name`, with no
# anchors. So excluding `Foo#layout` also exempts `Foo#layout_async`, and a
# method written tomorrow can inherit an exemption nobody granted it.
#
# ANCHORING IS NOT AVAILABLE. A non-String candidate would be used as a
# regexp source directly, but reek loads its config with a plain
# `YAML.load_file` (configuration_file_finder.rb:60), which under Psych 4
# refuses a `!ruby/regexp` entry:
#
#   Reek::Errors::ConfigFileError: Invalid configuration file,
#   error is Tried to load unspecified class: Regexp
#
# Measured. So the exemption cannot be narrowed in the config, and the answer
# is to make the over-reach VISIBLE and hold it still: this example fails the
# moment a new method falls under an exclusion that does not name it. The
# recorded set below is the same kind of ratchet as `.reek.yml` itself and
# `.rubocop_todo.yml` -- burn it down, never regenerate it larger.
RSpec.describe ".reek.yml" do
  # Reek's OWN context enumeration, not a hand-rolled AST walk. This is the
  # whole point of the shape: `ContextBuilder` produces exactly the
  # `full_name`s that `CodeContext#matches?` later tests the exclusions
  # against, so the scanner cannot disagree with reek about what a declaration
  # is called.
  #
  # A `def`-only Prism walk stood here for two rounds and was wrong twice, in
  # ways that are invisible until someone writes that form: it missed
  # `attr_accessor :x`, then `self.attr_accessor :x`, then `private def x`.
  # Each was a real declaration reek names and the baseline could silently
  # exempt. Enumerating forms is a list of the ones you thought of; asking
  # reek is the list that exists. DO NOT replace this with a bespoke walk.
  #
  # The `respond_to?` guard is for the root context, which is a sentinel with
  # no expression to name.
  def reek_context_names
    files = Dir.glob(File.expand_path("../lib/**/*.rb", __dir__))
    files.flat_map { |file| context_names(Pathname.new(file)) }.uniq
  end

  def context_names(source)
    tree = Reek::Source::SourceCode.from(source).syntax_tree
    named = Reek::ContextBuilder.new(tree).context_tree.each.select do |context|
      context.exp.respond_to?(:full_name)
    end
    named.map(&:full_name).reject { |name| name.nil? || name.empty? }
  end

  # EVERY exclusion, class-level ones included. Filtering to entries containing
  # "#" dropped them, and reek applies the same substring match to a bare class
  # name: `.reek.yml`'s `Elkrb::Graph::Node` exemption silently covered a new
  # `Elkrb::Graph::NodeProbe`. Measured -- NodeProbe reported no smells while an
  # identically-shaped FreshProbe reported InstanceVariableAssumption.
  def baseline_exclusions
    config = YAML.load_file(File.expand_path("../.reek.yml", __dir__))
    detectors = config.fetch("detectors").values
    excluded = detectors.flat_map { |detector| detector["exclude"] || [] }
    excluded.grep(String).uniq
  end

  # A containment is INTENDED when the excluded name is followed by a real
  # boundary: `Foo` covering `Foo#bar` and `Foo::Inner#bar` is the whole point
  # of a class-level entry. It is ACCIDENTAL for anything else -- `Node`
  # reaching `NodeConstraints`, `#serialize` reaching `#serialize_node` -- and
  # accidental is what this file exists to hold still.
  def accidentally_covered?(name, excluded)
    return false if name == excluded
    return false unless name.include?(excluded)

    !name.start_with?("#{excluded}#", "#{excluded}::")
  end

  # Recorded 2026-09-08. Each entry is a real declaration that is exempt from
  # some detector only because a SHORTER excluded name is a substring of it --
  # `#serialize` swallowing `#serialize_node`, `#initialize` swallowing
  # `#initialize_positions`. Nothing may be ADDED here without saying why;
  # shrinking it is the point.
  #
  # A `let` and not a constant: RuboCop's Lint/ConstantDefinitionInBlock fires
  # on a constant here, and its autocorrect turns one into a block-local, which
  # is a documented way to make a spec quietly stop asserting what it says.
  let(:recorded_swallowed) do
    [
      "Elkrb::Graph::EdgeSection",
      "Elkrb::Graph::EdgeSection#add_bend_point",
      "Elkrb::Graph::EdgeSection#initialize",
      "Elkrb::Graph::EdgeSection#length",
      "Elkrb::Graph::NodeConstraints",
      "Elkrb::Graph::NodeConstraints#__elkrb_merge_legacy_aliases",
      "Elkrb::Graph::NodeConstraints#align_direction=",
      "Elkrb::Graph::NodeConstraints#cast_legacy",
      "Elkrb::GraphvizWrapper",
      "Elkrb::GraphvizWrapper#available?",
      "Elkrb::GraphvizWrapper#build_command",
      "Elkrb::GraphvizWrapper#execute_command",
      "Elkrb::GraphvizWrapper#initialize",
      "Elkrb::GraphvizWrapper#installation_message",
      "Elkrb::GraphvizWrapper#render",
      "Elkrb::GraphvizWrapper#supported_engines",
      "Elkrb::GraphvizWrapper#supported_formats",
      "Elkrb::GraphvizWrapper#validate_engine!",
      "Elkrb::GraphvizWrapper#validate_file_exists!",
      "Elkrb::GraphvizWrapper#validate_format!",
      "Elkrb::GraphvizWrapper#version",
      "Elkrb::GraphvizWrapper::GraphvizNotFoundError",
      "Elkrb::Layout::Algorithms::BaseAlgorithm#layout_flat",
      "Elkrb::Layout::Algorithms::Force#initialize_positions",
      "Elkrb::Layout::Algorithms::Stress#initialize_positions",
      "Elkrb::Layout::Constraints::AlignmentConstraint#validate_group_alignment",
      "Elkrb::Layout::Constraints::RelativePositionConstraint#apply_relative_position",
      "Elkrb::Layout::EdgeRouter#route_edge_with_style",
      "Elkrb::Layout::EdgeRouter#route_edges",
      "Elkrb::Layout::EdgeRouter#route_self_loop_with_ports",
      "Elkrb::Layout::LabelPlacer#place_edge_label_estimated",
      "Elkrb::Layout::LabelPlacer#place_edge_label_on_section",
      "Elkrb::Layout::LabelPlacer#place_edge_labels",
      "Elkrb::Layout::LabelPlacer#place_port_label_by_side",
      "Elkrb::Layout::LabelPlacer#place_port_labels",
      "Elkrb::Options::KVectorChain",
      "Elkrb::Options::KVectorChain#==",
      "Elkrb::Options::KVectorChain#[]",
      "Elkrb::Options::KVectorChain#add",
      "Elkrb::Options::KVectorChain#each",
      "Elkrb::Options::KVectorChain#empty?",
      "Elkrb::Options::KVectorChain#initialize",
      "Elkrb::Options::KVectorChain#self.coordinate_pairs?",
      "Elkrb::Options::KVectorChain#self.from_array",
      "Elkrb::Options::KVectorChain#self.from_string",
      "Elkrb::Options::KVectorChain#self.parse",
      "Elkrb::Options::KVectorChain#size",
      "Elkrb::Options::KVectorChain#to_a",
      "Elkrb::Options::KVectorChain#to_s",
      "Elkrb::Parsers::Elkt::Lexer#advance_with",
      "Elkrb::Parsers::Elkt::Lexer#take_string_char",
      "Elkrb::Parsers::Elkt::Parser#parse_edge_body",
      "Elkrb::Parsers::Elkt::Parser#parse_edge_layout",
      "Elkrb::Parsers::Elkt::Parser#parse_members",
      "Elkrb::Parsers::Elkt::Parser#parse_section_body",
      "Elkrb::Serializers::ElktSerializer#serialize_edge",
      "Elkrb::Serializers::ElktSerializer#serialize_graph",
      "Elkrb::Serializers::ElktSerializer#serialize_layout_options",
      "Elkrb::Serializers::ElktSerializer#serialize_node",
      "Elkrb::Serializers::ElktSerializer#serialize_node_block",
      "Elkrb::Serializers::ElktSerializer#serialize_port",
      "Elkrb::Serializers::ElktSerializer#serialize_port_block",
    ]
  end

  it "covers no declaration accidentally, beyond the recorded set" do
    exclusions = baseline_exclusions
    covered = reek_context_names.select do |name|
      exclusions.any? { |excluded| accidentally_covered?(name, excluded) }
    end

    expect(covered.uniq.sort).to eq(recorded_swallowed.sort)
  end

  # The positive control. If the enumeration or the YAML read silently returned
  # nothing, the comparison above would still hold whenever the recorded set
  # happened to be empty, and would go on holding as declarations were added.
  it "reads a real baseline and a real lib tree" do
    expect(baseline_exclusions.size).to be > 100
    expect(reek_context_names.size).to be > 500
  end

  # The three forms that broke the hand-rolled walk, pinned against reek's
  # enumeration so a future change to it cannot quietly stop seeing them.
  it "names every declaration form the baseline can match" do
    source = <<~RUBY
      class Probe
        attr_accessor :plain_attr
        self.attr_accessor :self_attr
        private def private_method; end
        def public_method; end
      end
    RUBY
    expect(context_names(source)).to include(
      "Probe#plain_attr", "Probe#self_attr",
      "Probe#private_method", "Probe#public_method"
    )
  end
end
