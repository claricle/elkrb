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
  end
end
