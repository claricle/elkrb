# frozen_string_literal: true

require "reek"
require "reek/smell_detectors/missing_safe_method"
require "reek/smell_detectors/irresponsible_module"
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
  # Shrunk 2026-09-10: the bare `Elkrb::Graph` (IrresponsibleModule) and
  # `Elkrb::GraphvizWrapper` (MissingSafeMethod) entries in `.reek.yml` were
  # removed -- they are what caused every `Elkrb::GraphvizWrapper*` name to
  # show up here, since `"Elkrb::GraphvizWrapper".include?("Elkrb::Graph")`
  # (String#include?, not Module#include?) is true with no `#`/`::` boundary
  # right after it. `Elkrb::Graph`'s three undocumented reopenings
  # (lib/elkrb/graph/deep_stringify_keys.rb, normalize_option_keys.rb,
  # read_only_mapping.rb) got real descriptive comments instead of an
  # exemption. `Elkrb::GraphvizWrapper`'s moved to an inline
  # `:reek:MissingSafeMethod{...}` comment naming only the three methods that
  # need it (lib/elkrb/graphviz_wrapper.rb) -- which reek attaches to the AST
  # node rather than matching by name, so it cannot leak onto an unrelated
  # class the way a `.reek.yml` substring can. It DOES leak to a nested
  # class/module unless that nested thing resets it (see
  # `GraphvizNotFoundError`'s own reset comment in that file).
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

  # `Reek::Context::CodeContext#config_for` merges a PARENT context's
  # comment-derived config into every descendant's -- `parent_config_for(d) =
  # parent.config_for(d)`, then `.merge`d with the descendant's own comment.
  # So an inline `:reek:MissingSafeMethod{ exclude: [...] }` on
  # `GraphvizWrapper` is inherited by its nested `GraphvizNotFoundError`
  # unless THAT class resets it -- a real leak this branch found by
  # construction (adding a same-named bang method to the nested class and
  # watching reek stay silent) before adding the reset. This locks the reset
  # in: delete it from lib/elkrb/graphviz_wrapper.rb and this goes red.
  def smells_for(relative_path)
    path = Pathname.new(File.expand_path("../#{relative_path}", __dir__))
    Reek::Examiner.new(path).smells
  end

  def missing_safe_method_smells(smells)
    smells.select { |s| s.smell_type == "MissingSafeMethod" }
  end

  # Reads reek's own resolved config for a context, the same way
  # `BaseDetector#value`/`#exception?` do -- this is what actually decides
  # whether a method is exempted, not a smell run against an isolated
  # tempfile (an early version of this example ran `Reek::Examiner` on a
  # mutated copy and asserted `smells.map(&:context).to include(...)`; that
  # passed even with the fix reverted, because an isolated tempfile with no
  # `.reek.yml` reports an UNRELATED IrresponsibleModule smell on the same
  # context name, which satisfies a context-only check regardless of
  # MissingSafeMethod. Reading the resolved config directly has no such
  # proxy).
  def graphviz_wrapper_context_tree
    rel = "../lib/elkrb/graphviz_wrapper.rb"
    path = Pathname.new(File.expand_path(rel, __dir__))
    tree = Reek::Source::SourceCode.from(path).syntax_tree
    Reek::ContextBuilder.new(tree).context_tree
  end

  def find_context(full_name)
    graphviz_wrapper_context_tree.each.find do |c|
      c.exp.respond_to?(:full_name) && c.full_name == full_name
    end
  end

  def missing_safe_method_config_for(full_name)
    context = find_context(full_name)
    raise "context #{full_name} not found in graphviz_wrapper.rb" unless context

    context.config_for(Reek::SmellDetectors::MissingSafeMethod)
  end

  it "resets the nested class's exclude instead of inheriting the parent's" do
    # Without the reset, `CodeContext#config_for` merges GraphvizWrapper's
    # `{"exclude"=>["validate_engine!", ...]}` straight into its nested
    # class -- indistinguishable from a deliberate, narrower exclude unless
    # asserted exactly. `{}` (no comment resolved at all, e.g. on origin/v2
    # before this branch) is a DIFFERENT value and must not satisfy this.
    expect(missing_safe_method_config_for("Elkrb::GraphvizWrapper::GraphvizNotFoundError"))
      .to eq({ "exclude" => [] })
  end

  it "keeps GraphvizWrapper's own three validators exempt" do
    smells = smells_for("lib/elkrb/graphviz_wrapper.rb")
    expect(missing_safe_method_smells(smells)).to be_empty
  end

  # The three `module Graph` reopenings are fixed with a REAL descriptive
  # comment, not a `:reek:IrresponsibleModule` directive -- deliberately, so
  # there is no comment-derived config at all for a nested declaration to
  # inherit (the same inheritance hazard the GraphvizNotFoundError reset
  # above exists to close). This locks that choice in: reintroducing the
  # directive here restores the exact inheritance leak, and every one of
  # these files would then need its own reset the way GraphvizNotFoundError
  # does -- these examples fail the moment that happens.
  def graph_reopening_files
    %w[
      lib/elkrb/graph/deep_stringify_keys.rb
      lib/elkrb/graph/normalize_option_keys.rb
      lib/elkrb/graph/read_only_mapping.rb
    ]
  end

  def context_tree_for(relative_path)
    path = Pathname.new(File.expand_path("../#{relative_path}", __dir__))
    tree = Reek::Source::SourceCode.from(path).syntax_tree
    Reek::ContextBuilder.new(tree).context_tree
  end

  # ALL matching contexts, not `.find`'s first match -- a file that reopened
  # `module Graph` a second time would have its second occurrence silently
  # skipped by `.find`, and every check below would pass while that second
  # occurrence carried whatever config it liked. Caught in review: an
  # earlier version used `.find` and passed against a hand-built file with a
  # second, undocumented `module Graph` reopening plus a directive.
  def all_matching_contexts(relative_path, full_name)
    matches = context_tree_for(relative_path).each.select do |c|
      c.exp.respond_to?(:full_name) && c.full_name == full_name
    end
    raise "no #{full_name} context in #{relative_path}" if matches.empty?

    matches
  end

  # Neither half of this is enough alone:
  # - `config_for(IrresponsibleModule) == {}` is ALSO true on origin/v2's
  #   ORIGINAL file, which has no comment at all and is genuinely unfixed --
  #   a `:reek:X` disable and "no comment" both resolve to no comment-derived
  #   config. Mutation-check.sh caught this: an earlier version asserted only
  #   `config_for == {}` and STAYED GREEN with the fix reverted.
  # - `descriptively_commented?` ALONE misses a `:reek:IrresponsibleModule`
  #   directive added ALONGSIDE the real comment rather than instead of it --
  #   the prose still reads as descriptive, but `config_for` resolves to
  #   `{"enabled"=>false}`, which is inherited by any nested declaration the
  #   same way GraphvizNotFoundError's leak worked. Both must hold, on EVERY
  #   matching context in the file, not just the first.
  it "fixes each Graph reopening with a real comment, not a directive" do
    graph_reopening_files.each do |relative_path|
      all_matching_contexts(relative_path, "Elkrb::Graph").each do |context|
        expect(context.descriptively_commented?).to be(true), relative_path
        config = context.config_for(Reek::SmellDetectors::IrresponsibleModule)
        expect(config).to eq({}), "#{relative_path}: #{config.inspect}"
      end
    end
  end
end
