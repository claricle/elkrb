# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require "stringio"
require_relative "../../../lib/elkrb/commands/validate_command"

RSpec.describe Elkrb::Commands::ValidateCommand do
  # Every "detects X" example below only asserts `raise_error(SystemExit)`
  # -- it proves SOME error fired, never which one or what it says. Mutant
  # found this: the exact field name, the recursive descent into nested
  # children/ports, and which of several sources/targets is unknown can all
  # be broken (wrong field name, no recursion, checking only the first
  # element) while every "detects X" example here stays green, because the
  # CLI exits 1 either way. This captures the real bullet list #run prints
  # so a few specs can pin its actual content instead of its mere presence.
  def run_capturing_errors(command)
    original_stdout = $stdout
    $stdout = StringIO.new
    begin
      command.run
    rescue SystemExit
      nil
    ensure
      output = $stdout.string
      $stdout = original_stdout
    end
    output.lines.grep(/^ {2}• /).map { |line| line.sub(/^ {2}• /, "").chomp }
  end

  let(:temp_dir) { Dir.mktmpdir }
  let(:valid_graph) do
    {
      id: "root",
      children: [
        { id: "n1", width: 100, height: 60 },
        { id: "n2", width: 100, height: 60 },
      ],
      edges: [
        { id: "e1", sources: ["n1"], targets: ["n2"] },
      ],
    }
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run" do
    it "validates a valid graph" do
      input_file = File.join(temp_dir, "valid.json")
      File.write(input_file, valid_graph.to_json)

      command = described_class.new(input_file, {})

      expect { command.run }.to output(/✅.*valid/).to_stdout
    end

    it "detects missing graph ID" do
      input_file = File.join(temp_dir, "invalid.json")
      File.write(input_file, { children: [], edges: [] }.to_json)

      command = described_class.new(input_file, {})

      expect { command.run }.to raise_error(SystemExit)
    end

    it "detects missing node ID" do
      input_file = File.join(temp_dir, "invalid.json")
      graph = {
        id: "root",
        children: [{ width: 100, height: 60 }],
        edges: [],
      }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, {})

      expect { command.run }.to raise_error(SystemExit)
    end

    it "detects missing edge sources" do
      input_file = File.join(temp_dir, "invalid.json")
      graph = {
        id: "root",
        children: [{ id: "n1", width: 100, height: 60 }],
        edges: [{ id: "e1", targets: ["n1"] }],
      }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, {})

      expect { command.run }.to raise_error(SystemExit)
    end

    it "detects missing edge targets" do
      input_file = File.join(temp_dir, "invalid.json")
      graph = {
        id: "root",
        children: [{ id: "n1", width: 100, height: 60 }],
        edges: [{ id: "e1", sources: ["n1"] }],
      }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, {})

      expect { command.run }.to raise_error(SystemExit)
    end

    it "validates strict mode with dimensions" do
      input_file = File.join(temp_dir, "valid.json")
      File.write(input_file, valid_graph.to_json)

      command = described_class.new(input_file, { strict: true })

      expect { command.run }.to output(/✅.*valid/).to_stdout
    end

    it "detects missing width in strict mode" do
      input_file = File.join(temp_dir, "invalid.json")
      graph = {
        id: "root",
        children: [{ id: "n1", height: 60 }],
        edges: [],
      }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, { strict: true })

      expect { command.run }.to raise_error(SystemExit)
    end

    it "detects invalid node references in strict mode" do
      input_file = File.join(temp_dir, "invalid.json")
      graph = {
        id: "root",
        children: [{ id: "n1", width: 100, height: 60 }],
        edges: [{ id: "e1", sources: ["n1"], targets: ["n2"] }],
      }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, { strict: true })

      expect { command.run }.to raise_error(SystemExit)
    end

    it "names the node and field missing an ID, at any nesting depth" do
      input_file = File.join(temp_dir, "invalid.json")
      grandchild = { width: 10, height: 10 }
      child = { id: "n1", width: 100, height: 60, children: [grandchild] }
      graph = { id: "root", children: [child], edges: [] }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, {})

      errors = run_capturing_errors(command)
      expected = "children[0].children[0]: Node missing 'id' field"

      expect(errors).to include(expected)
    end

    # A String width does not survive the round trip through
    # Elkrb::Graph::Graph -- lutaml-model coerces "wide" to 0.0 before
    # #validate_node ever sees it (measured), so the ">is_a?(Numeric)" half
    # of the guard is only reachable via a non-Graph Hash input. Zero and a
    # negative number both stay numeric and are what a real caller's typo
    # (an accidental 0, a sign error) actually produces.
    it "flags a zero width and a negative height separately" do
      input_file = File.join(temp_dir, "invalid.json")
      graph = {
        id: "root",
        children: [
          { id: "n1", width: 0, height: -5 },
        ],
        edges: [],
      }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, { strict: true })

      errors = run_capturing_errors(command)

      expect(errors).to include(
        "children[0]: Node 'n1' has invalid width: 0.0",
        "children[0]: Node 'n1' has invalid height: -5.0",
      )
    end

    it "names every unknown source and target, not just the first" do
      input_file = File.join(temp_dir, "invalid.json")
      edge = {
        id: "e1",
        sources: %w[n1 ghost-source],
        targets: %w[ghost-target1 ghost-target2],
      }
      node = { id: "n1", width: 100, height: 60 }
      graph = { id: "root", children: [node], edges: [edge] }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, { strict: true })

      errors = run_capturing_errors(command)

      expect(errors).to include(
        "edges[0]: Edge 'e1' references unknown source node 'ghost-source'",
        "edges[0]: Edge 'e1' references unknown target node 'ghost-target1'",
        "edges[0]: Edge 'e1' references unknown target node 'ghost-target2'",
      )
      expect(errors)
        .not_to include(a_string_matching(/unknown source node 'n1'/))
    end

    # A plain `output(...).to_stdout` assertion here would NOT catch this
    # being broken -- measured: disabling the recursive
    # collect_node_ids(node, ids) call makes #run exit 1 instead of
    # printing the checkmark, and RSpec's output matcher does not surface a
    # SystemExit raised inside its block as a failure, so the example would
    # stay green either way. Capture the actual errors instead.
    it "collects nested child IDs so strict references can find them" do
      input_file = File.join(temp_dir, "valid.json")
      nested = { id: "nested", width: 10, height: 10 }
      parent = { id: "parent", width: 100, height: 60, children: [nested] }
      graph = {
        id: "root",
        children: [parent],
        edges: [{ id: "e1", sources: ["parent"], targets: ["nested"] }],
      }
      File.write(input_file, graph.to_json)

      command = described_class.new(input_file, { strict: true })

      expect(run_capturing_errors(command)).to be_empty
    end

    it "validates YAML files" do
      input_file = File.join(temp_dir, "valid.yml")
      File.write(input_file, valid_graph.to_yaml)

      command = described_class.new(input_file, {})

      expect { command.run }.to output(/✅.*valid/).to_stdout
    end

    it "validates ELKT files" do
      input_file = File.join(temp_dir, "valid.elkt")
      File.write(input_file, "node n1\nnode n2\nedge n1 -> n2")

      command = described_class.new(input_file, {})

      expect { command.run }.to output(/✅.*valid/).to_stdout
    end

    # #load_any_format only reaches #detect_and_parse when the extension is
    # unrecognized, and every example above uses .json/.yml/.elkt -- so this
    # auto-detect chain had near-zero mutation coverage and hid a real
    # defect: Graph.from_json/.from_yaml raise
    # Lutaml::Model::InvalidFormatError on bad content (measured directly
    # against lutaml-model), not the stdlib JSON::ParserError /
    # Psych::SyntaxError this method used to rescue. So it never fell
    # through past JSON to try YAML or ELKT; it raised, unhandled, on the
    # first attempt for any non-JSON content. Fixed by also rescuing
    # InvalidFormatError; these specs pin that YAML and ELKT are now
    # actually reachable.
    it "auto-detects YAML when the extension is unrecognized" do
      input_file = File.join(temp_dir, "valid.graph")
      File.write(input_file, valid_graph.to_yaml)

      command = described_class.new(input_file, {})

      expect { command.run }.to output(/✅.*valid/).to_stdout
    end

    it "auto-detects ELKT when the extension is unrecognized" do
      input_file = File.join(temp_dir, "valid.graph")
      File.write(input_file, "node n1\nnode n2\nedge n1 -> n2")

      command = described_class.new(input_file, {})

      expect { command.run }.to output(/✅.*valid/).to_stdout
    end

    it "raises a clear error when nothing can parse the content" do
      input_file = File.join(temp_dir, "invalid.graph")
      # A lone ")" is invalid JSON, invalid ELKT, and -- unlike most garbage
      # strings -- also invalid YAML (a bare flow-mapping close character).
      File.write(input_file, ")")

      command = described_class.new(input_file, {})

      expect { command.run }.to raise_error(ArgumentError,
                                            /Unable to parse input file/)
    end

    it "raises error for non-existent file" do
      command = described_class.new("nonexistent.json", {})

      expect { command.run }.to raise_error(ArgumentError, /File not found/)
    end
  end
end
