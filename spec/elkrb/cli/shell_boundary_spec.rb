# frozen_string_literal: true

require "spec_helper"
require "support/cli_runner"
require "json"
require "tmpdir"
require "fileutils"
require "elkrb/format_sniffer"
require "elkrb/graphviz_wrapper"
require "elkrb/commands/batch_command"
require "yaml"

RSpec.describe "elkrb CLI shell boundary" do
  include CliRunner

  let(:simple_graph_path) { File.join(CliRunner::ROOT, "spec/fixtures/simple_graph.json") }

  describe "layout" do
    it "exits 0 for a JSON file with no recognized extension" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "graph.noext")
        FileUtils.cp(simple_graph_path, file)

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 0 for a YAML file with no recognized extension" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "graph.noext")
        graph = JSON.parse(File.read(simple_graph_path))
        File.write(file, graph.to_yaml)

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 1 with a stderr message for unparsable input" do
      garbage_file = File.join(CliRunner::ROOT,
                               "spec/fixtures/corpus/garbage.txt")

      stdout, stderr, status = run_elkrb("layout", garbage_file)

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq("")
      expect(stderr).not_to eq("")
    end

    # Cli#error_output writes with $stderr.puts rather than Kernel#warn
    # because warn is a no-op once warnings are off, which would delete
    # every CLI error message for anyone running under -W0.
    it "still reports the error on stderr under RUBYOPT=-W0" do
      garbage_file = File.join(CliRunner::ROOT,
                               "spec/fixtures/corpus/garbage.txt")

      stdout, stderr, status = run_elkrb("layout", garbage_file,
                                         env: { "RUBYOPT" => "-W0" })

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq("")
      expect(stderr).to start_with("Error: ")
    end

    it "exits 0 for an ELKT file the sniff-then-parse fallback can read" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "graph.elkt")
        File.write(file, "node n1\nnode n2\nedge n1 -> n2\n")

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 0 for an ELKT file with only a layout option, no nodes" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "options_only.noext")
        # Valid YAML (a one-key mapping with no recognized Graph fields),
        # so from_yaml succeeds silently with an empty/hollow model. The
        # guard must still fall through to ElktParser rather than treating
        # that hollow "success" as a real (if empty) graph.
        File.write(file, "algorithm: layered\n")

        _stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
      end
    end

    it "exits 1 for a YAML mapping with no recognized graph or ELKT content" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "garbage_mapping.noext")
        # Also valid (if pointless) YAML: succeeds silently as a hollow
        # model, same as the case above. The hyphen keeps it from matching
        # ElktParser's `key: value` property regex too (\w excludes "-"),
        # so unlike "algorithm: layered" this really is garbage all the
        # way down -- must be rejected, not returned as an empty "success".
        File.write(file, "unknown-key: value\n")

        stdout, stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("")
        expect(stderr).not_to eq("")
      end
    end

    it "keeps the children of a flow-style YAML file" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "flow.noext")
        # Flow-style YAML opens with "{" like JSON but does not parse as
        # JSON. Falling straight through to ELKT reads "id: root," and
        # "children: [" as layout options, so the graph comes back with no
        # children and no error at all.
        File.write(file,
                   "{\n  id: root,\n  children: [\n    " \
                   "{id: n1, width: 30, height: 30}\n  ]\n}\n")

        stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
        ids = JSON.parse(stdout)["children"].map { |child| child["id"] }
        expect(ids).to eq(["n1"])
      end
    end

    it "reads every declaration in a BOM-prefixed ELKT file" do
      bom_file = File.join(CliRunner::ROOT, "spec/fixtures/corpus/bom.elkt")

      stdout, _stderr, status = run_elkrb("layout", bom_file)

      expect(status.exitstatus).to eq(0)
      ids = JSON.parse(stdout)["children"].map { |child| child["id"] }
      expect(ids).to eq(%w[a b])
    end

    # JSON is the tool's primary format and was the only one the mark broke:
    # lutaml passes the leading U+FEFF to the JSON parser, which rejects the
    # document. The sniffed and ELKT paths stripped it, .json did not.
    it "reads a BOM-prefixed .json file" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "bom.json")
        File.write(file, "\uFEFF" \
                         '{"id":"root","children":' \
                         '[{"id":"a","width":30,"height":30}]}')

        stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
        ids = JSON.parse(stdout)["children"].map { |child| child["id"] }
        expect(ids).to eq(["a"])
      end
    end

    # YAML is the dangerous half. Psych does not reject a marked document --
    # it silently drops every key after the first, so the graph laid out as
    # an empty one and the CLI exited 0. Asserting the children is what
    # catches that; asserting the exit code is not, because 0 is exactly
    # what the broken version returned.
    it "reads a BOM-prefixed .yaml file" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "bom.yaml")
        yaml = <<~YAML
          id: root
          children:
            - id: a
              width: 30
              height: 30
        YAML
        File.write(file, "\uFEFF#{yaml}")

        stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
        ids = JSON.parse(stdout)["children"].map { |child| child["id"] }
        expect(ids).to eq(["a"])
      end
    end

    it "accepts a JSON file whose only recognized field is properties" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "props.noext")
        File.write(file, '{"properties":{"note":"hello"}}')

        stdout, _stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(0)
        expect(JSON.parse(stdout)["properties"]).to eq({ "note" => "hello" })
      end
    end

    it "exits 1 for a top-level JSON sequence, not a NoMethodError" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "sequence.noext")
        # Parses without raising (Lutaml returns an Array for a top-level
        # JSON sequence), so this only fails via the type check, not the
        # InvalidFormatError rescue -- must not leak "undefined method
        # 'id' for an instance of Array" from hollow_model?.
        File.write(file, "[]")

        stdout, stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("")
        expect(stderr).to eq("Error: Unable to parse input file. " \
                             "Supported formats: JSON, YAML, ELKT\n")
      end
    end

    it "exits 1 for a top-level YAML sequence, not a NoMethodError" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "sequence.noext")
        File.write(file, "- id: g\n")

        stdout, stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("")
        expect(stderr).to eq("Error: Unable to parse input file. " \
                             "Supported formats: JSON, YAML, ELKT\n")
      end
    end

    # Psych's safe loader refuses these rather than failing to parse them,
    # and lutaml-model does not normalize its refusals, so they reach the
    # sniffer as raw Psych errors. The user must still see the normalized
    # message, not "Tried to load unspecified class: Struct".
    it "exits 1 for YAML naming a disallowed class, not a Psych error" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "disallowed.noext")
        File.write(file, "--- !ruby/object:Struct\nfoo: 1\n")

        stdout, stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("")
        expect(stderr).to eq("Error: Unable to parse input file. " \
                             "Supported formats: JSON, YAML, ELKT\n")
      end
    end

    it "exits 1 for YAML using an alias, not a Psych error" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "alias.noext")
        File.write(file, "a: &x\n  b: *x\n")

        stdout, stderr, status = run_elkrb("layout", file)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("")
        expect(stderr).to eq("Error: Unable to parse input file. " \
                             "Supported formats: JSON, YAML, ELKT\n")
      end
    end
  end

  describe "batch" do
    it "exits non-zero when any file in the directory fails" do
      Dir.mktmpdir do |input_dir|
        Dir.mktmpdir do |output_dir|
          FileUtils.cp(simple_graph_path, File.join(input_dir, "good.json"))
          File.write(File.join(input_dir, "bad.json"), "not valid json")

          _stdout, _stderr, status = run_elkrb(
            "batch", input_dir, "--output-dir", output_dir, "--format", "dot"
          )

          expect(status.exitstatus).not_to eq(0)
        end
      end
    end
  end
end

RSpec.describe "failures that must not look like successes" do
  let(:input_dir) { Dir.mktmpdir }
  let(:output_dir) { Dir.mktmpdir }

  before do
    File.write(File.join(input_dir, "g.json"),
               '{"id":"r","children":[{"id":"a","width":10,"height":10}]}')
  end

  after do
    FileUtils.remove_entry(input_dir)
    FileUtils.remove_entry(output_dir)
  end

  context "when Graphviz cannot render" do
    before do
      allow_any_instance_of(Elkrb::GraphvizWrapper)
        .to receive(:available?).and_return(false)
    end

    it "fails the batch instead of counting the file as processed" do
      command = Elkrb::Commands::BatchCommand.new(input_dir,
                                                  output_dir: output_dir,
                                                  format: "svg")

      expect { command.run }.to raise_error(Elkrb::Error, /failed/)
    end

    it "leaves no DOT text sitting under the requested image filename" do
      command = Elkrb::Commands::BatchCommand.new(input_dir,
                                                  output_dir: output_dir,
                                                  format: "svg")

      begin
        command.run
      rescue Elkrb::Error
        nil
      end

      expect(Dir.children(output_dir)).to be_empty
    end
  end
end

RSpec.describe "malformed collection shapes" do
  # An empty extension takes read's else branch, which is the sniffed path
  # these examples are about. Asserting the real UNPARSEABLE text pins the
  # message a user actually sees, which a custom one never could.
  let(:unparseable) do
    "Unable to parse input file. Supported formats: JSON, YAML, ELKT"
  end

  it "reports a normalized parse error rather than leaking NoMethodError" do
    expect do
      Elkrb::FormatSniffer.read('{"id":"r","children":{"a":1}}', "")
    end.to raise_error(ArgumentError, unparseable)
  end

  it "still accepts a properly shaped children list" do
    graph = Elkrb::FormatSniffer.read(
      '{"id":"r","children":[{"id":"a","width":10,"height":10}]}', ""
    )

    expect(graph.children).to be_an(Array)
  end
end

RSpec.describe "a file whose extension already names the format" do
  include CliRunner

  it "rejects a .elkt file whose content is not ELKT at all" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "junk.elkt")
      File.write(path, "this is definitely not ELKT\n")

      _stdout, stderr, status = run_elkrb("layout", path)

      expect(status.exitstatus).to eq(1)
      expect(stderr).to include("Unable to parse")
    end
  end

  it "accepts a comment-only ELKT file as a valid empty graph" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "comment.elkt")
      File.write(path, "// just a comment\n")

      stdout, _stderr, status = run_elkrb("layout", path)

      expect(status.exitstatus).to eq(0)
      expect(stdout).to include('"id"')
    end
  end

  it "accepts an empty ELKT graph, which the parser and serializer " \
     "both round-trip" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "empty.elkt")
      File.write(path, "")

      stdout, _stderr, status = run_elkrb("layout", path)

      expect(status.exitstatus).to eq(0)
      expect(stdout).to include('"id"')
    end
  end
end

RSpec.describe "Graphviz lookup along PATH" do
  # Sets the real environment instead of stubbing ENV, the way
  # graphviz_wrapper_spec's with_path_only does. A stub named after one
  # reader (ENV#[]) stops intercepting the moment the code switches to
  # another (ENV#fetch), and the example then silently reads whatever the
  # developer's own environment happens to hold.
  it "reads an empty PATH component as the working directory, " \
     "like the shell does" do
    original_path = ENV.fetch("PATH", nil)
    original_elkrb_dot = ENV.fetch("ELKRB_DOT", nil)

    Dir.mktmpdir do |dir|
      dot = File.join(dir, "dot")
      File.write(dot, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, dot)

      Dir.chdir(dir) do
        # A bare separator: one empty component, meaning "here". The absolute
        # fallback locations are blanked so the example turns on that
        # component alone, not on the developer having Graphviz installed.
        stub_const("Elkrb::GraphvizWrapper::FALLBACK_DOT_PATHS", [])
        ENV["PATH"] = File::PATH_SEPARATOR
        ENV.delete("ELKRB_DOT")

        expect(Elkrb::GraphvizWrapper.new).to be_available
      end
    end
  ensure
    ENV["PATH"] = original_path
    ENV["ELKRB_DOT"] = original_elkrb_dot
  end
end

RSpec.describe "every command reads input through one path" do
  include CliRunner

  # The extension dispatch used to be copy-pasted into four places, so a guard
  # added to one left the other three accepting malformed input.
  it "rejects a malformed shape from layout, validate and diagram alike" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.json")
      File.write(path, '{"id":"r","children":{"a":1}}')

      %w[layout validate].each do |command|
        _stdout, stderr, status = run_elkrb(command, path)

        expect(status.exitstatus).to eq(1),
                                     "#{command} accepted a malformed shape"
        expect(stderr).to include("Unable to parse"),
                          "#{command} leaked an internal error"
      end
    end
  end

  it "still accepts a well-formed graph from every command" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ok.json")
      File.write(path,
                 '{"id":"r","children":[{"id":"a","width":10,"height":10}]}')

      %w[layout validate].each do |command|
        _stdout, _stderr, status = run_elkrb(command, path)

        expect(status.exitstatus).to eq(0), "#{command} rejected a valid graph"
      end
    end
  end

  it "accepts an ELKT graph that carries only its own size" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "rootsize.elkt")
      File.write(path, "layout [ size: 30, 40 ]\n")

      stdout, _stderr, status = run_elkrb("layout", path)

      expect(status.exitstatus).to eq(0)
      expect(stdout).to include('"width"')
    end
  end
end

RSpec.describe "byte order mark removal across input encodings" do
  # File.read tags content with Encoding.default_external, which RUBYOPT=-E,
  # an explicit -E, or the locale is free to set to anything. A character
  # level String#delete_prefix against a UTF-8 mark literal raises
  # Encoding::CompatibilityError on any receiver in another encoding that
  # holds a non-ASCII byte, so the mark comes off by byte instead.
  let(:json) do
    '{"id":"root","children":[{"id":"a","width":30,"height":30}]}'
  end

  let(:yaml) do
    "id: root\nchildren:\n  - id: a\n    width: 30\n    height: 30\n"
  end

  # A lone high byte: e-acute in ISO-8859-1, not valid UTF-8 on its own.
  let(:accented_json) { json.sub("root", "caf\xE9") }

  let(:accented_yaml) { yaml.sub("root", "caf\xE9") }

  def child_ids(content, extension)
    Elkrb::FormatSniffer.read(content, extension).children.map(&:id)
  end

  it "strips the mark from UTF-8 content" do
    expect(child_ids("\uFEFF#{json}", ".json")).to eq(["a"])
  end

  it "leaves UTF-8 content without a mark alone" do
    expect(child_ids(json, ".json")).to eq(["a"])
  end

  it "reads unmarked ISO-8859-1 JSON holding a non-ASCII byte" do
    content = accented_json.force_encoding(Encoding::ISO_8859_1)

    expect(child_ids(content, ".json")).to eq(["a"])
  end

  it "reads unmarked ISO-8859-1 YAML holding a non-ASCII byte" do
    content = accented_yaml.force_encoding(Encoding::ISO_8859_1)

    expect(child_ids(content, ".yaml")).to eq(["a"])
  end

  it "strips the mark from BINARY content" do
    content = "\uFEFF#{json}".force_encoding(Encoding::BINARY)

    expect(child_ids(content, ".json")).to eq(["a"])
  end

  it "reads unmarked BINARY content holding a non-ASCII byte" do
    content = accented_json.force_encoding(Encoding::BINARY)

    expect(child_ids(content, ".json")).to eq(["a"])
  end
end
