# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/elkrb/commands/diagram_command"

RSpec.describe Elkrb::Commands::DiagramCommand do
  let(:temp_dir) { Dir.mktmpdir }
  let(:graph_data) do
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
    it "creates diagram from JSON file" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.dot")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "creates diagram from YAML file" do
      input_file = File.join(temp_dir, "graph.yml")
      output_file = File.join(temp_dir, "output.dot")

      File.write(input_file, graph_data.to_yaml)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "creates diagram from ELKT file" do
      input_file = File.join(temp_dir, "graph.elkt")
      output_file = File.join(temp_dir, "output.dot")

      elkt_content = <<~ELKT
        node n1
        node n2
        edge n1 -> n2
      ELKT

      File.write(input_file, elkt_content)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "applies layout algorithm" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      algorithm: "layered",
                                    })
      command.run

      result = JSON.parse(File.read(output_file))
      expect(result["children"]).to be_an(Array)
    end

    it "outputs to JSON format" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { JSON.parse(content) }.not_to raise_error
    end

    it "outputs to YAML format" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.yml")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "outputs to DOT format" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.dot")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("digraph")
    end

    it "outputs to ELKT format" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.elkt")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("node n1")
      expect(content).to include("edge")
    end

    it "creates output directory if needed" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "subdir", "output.dot")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "raises error for non-existent file" do
      output_file = File.join(temp_dir, "output.dot")

      command = described_class.new("nonexistent.json", { output: output_file })

      expect { command.run }.to raise_error(ArgumentError, /File not found/)
    end

    it "applies spacing option" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      spacing: 100,
                                    })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "applies direction option" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      direction: "DOWN",
                                    })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "detects format from explicit option" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.txt")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      format: "dot",
                                    })
      command.run

      content = File.read(output_file)
      expect(content).to include("digraph")
    end

    it "auto-detects JSON format from extension" do
      input_file = File.join(temp_dir, "input.elkt")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, "node n1\nnode n2\nedge n1 -> n2")

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { JSON.parse(content) }.not_to raise_error
    end

    it "auto-detects YAML format from extension" do
      input_file = File.join(temp_dir, "input.json")
      output_file = File.join(temp_dir, "output.yaml")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "loads a YAML file with no recognized extension" do
      input_file = File.join(temp_dir, "graph.noext")
      output_file = File.join(temp_dir, "output.dot")
      File.write(input_file, graph_data.to_yaml)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("n1")
      expect(content).to include("n2")
    end

    it "raises for unparsable content with no recognized extension" do
      input_file = File.join(temp_dir, "graph.noext")
      output_file = File.join(temp_dir, "output.dot")
      File.write(input_file, "this is not a graph, just garbage!!! {{{ ]]] ###")

      command = described_class.new(input_file, { output: output_file })

      expect { command.run }.to raise_error(ArgumentError,
                                            /Unable to parse input file/)
    end
  end
  describe "when staging the DOT fails" do
    # I claimed this was covered and it was not. The existing cleanup
    # examples all run AFTER a successful staging write, so none of them
    # exercised the path where staging itself raises.
    #
    # The image path must never hold DOT. It used to: the DOT was written
    # under `out.svg` and read back, so any failure between those points left
    # a `.svg` beginning `digraph G{`. Cleanup could not be relied on to undo
    # that either -- `FileUtils.rm_f` swallows an unlink failure.
    let(:input_file) do
      File.join(temp_dir, "graph.json").tap do |path|
        File.write(path, graph_data.to_json)
      end
    end
    let(:output_file) { File.join(temp_dir, "out.svg") }

    before { FileUtils.mkdir_p("#{output_file}.tmp.dot") }

    it "leaves no image file behind" do
      expect do
        described_class.new(input_file, { output: output_file }).run
      end.to raise_error(StandardError)

      expect(File.exist?(output_file)).to be(false)
    end

    it "does not clobber a file already at the image path" do
      File.write(output_file, "PRE-EXISTING USER CONTENT")

      expect do
        described_class.new(input_file, { output: output_file }).run
      end.to raise_error(StandardError)

      # Naming the content, not just "it still exists": the defect wrote DOT
      # over it, and a bare existence check would pass on that.
      expect(File.read(output_file)).to eq("PRE-EXISTING USER CONTENT")
    end
  end
end
