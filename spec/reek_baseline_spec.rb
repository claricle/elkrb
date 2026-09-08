# frozen_string_literal: true

require "prism"
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
  # Every `Class#method` and `Class#self.method` defined under lib/, built from
  # the AST rather than a grep so a `def` inside a nested module gets its real
  # qualified name.
  def method_full_names
    root = File.expand_path("../lib/**/*.rb", __dir__)
    # Order is irrelevant: the assertion sorts. Glob order is not a language
    # guarantee, so nothing here may depend on it.
    Dir.glob(root).flat_map do |file|
      methods_in(Prism.parse_file(file).value, [])
    end
  end

  def methods_in(node, scope)
    case node
    when Prism::ModuleNode, Prism::ClassNode
      nested = scope + [node.constant_path.slice]
      children_of(node.body).flat_map { |child| methods_in(child, nested) }
    when Prism::DefNode
      ["#{scope.join('::')}#{node.receiver ? '#self.' : '#'}#{node.name}"]
    else
      children_of(node).flat_map { |child| methods_in(child, scope) }
    end
  end

  def children_of(node)
    node ? node.child_nodes.compact : []
  end

  def method_level_exclusions
    config = YAML.load_file(File.expand_path("../.reek.yml", __dir__))
    detectors = config.fetch("detectors").values
    excluded = detectors.flat_map { |detector| detector["exclude"] || [] }
    excluded.grep(String).uniq.select { |name| name.include?("#") }
  end

  # Recorded 2026-09-08 against the baseline as generated. Each entry is a real
  # method that is exempt from some detector only because a SHORTER excluded
  # name is a substring of it -- `#serialize` swallowing `#serialize_node`,
  # `#initialize` swallowing `#initialize_positions`. Nothing may be ADDED here
  # without saying why; shrinking it is the point.
  #
  # A `let` and not a constant: RuboCop's Lint/ConstantDefinitionInBlock fires
  # on a constant here, and its autocorrect turns one into a block-local, which
  # is a documented way to make a spec quietly stop asserting what it says.
  let(:recorded_swallowed) do
    [
      "Elkrb::Layout::Algorithms::BaseAlgorithm#layout_flat",
      "Elkrb::Layout::Algorithms::Force#initialize_positions",
      "Elkrb::Layout::Algorithms::Stress#initialize_positions",
      "Elkrb::Layout::Constraints::AlignmentConstraint#validate_group_alignment",
      "Elkrb::Layout::Constraints::RelativePositionConstraint" \
      "#apply_relative_position",
      "Elkrb::Layout::EdgeRouter#route_edge_with_style",
      "Elkrb::Layout::EdgeRouter#route_edges",
      "Elkrb::Layout::EdgeRouter#route_self_loop_with_ports",
      "Elkrb::Layout::LabelPlacer#place_edge_label_estimated",
      "Elkrb::Layout::LabelPlacer#place_edge_label_on_section",
      "Elkrb::Layout::LabelPlacer#place_edge_labels",
      "Elkrb::Layout::LabelPlacer#place_port_label_by_side",
      "Elkrb::Layout::LabelPlacer#place_port_labels",
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

  it "exempts no method it does not name, beyond the recorded set" do
    exclusions = method_level_exclusions
    swallowed = method_full_names.select do |name|
      exclusions.any? { |excluded| name != excluded && name.include?(excluded) }
    end

    expect(swallowed.uniq.sort).to eq(recorded_swallowed.sort)
  end

  # The positive control for the example above. If the AST walk or the YAML
  # read silently returned nothing, the comparison would still hold whenever
  # the recorded set happened to be empty -- and it would go on holding as
  # methods were added. These two say the inputs are real.
  it "reads a real baseline and a real lib tree" do
    expect(method_level_exclusions.size).to be > 100
    expect(method_full_names.size).to be > 500
  end
end
