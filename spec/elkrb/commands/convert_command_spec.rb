# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/elkrb/commands/convert_command"

RSpec.describe Elkrb::Commands::ConvertCommand do
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
    it "converts JSON to YAML" do
      input_file = File.join(temp_dir, "input.json")
      output_file = File.join(temp_dir, "output.yml")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "converts JSON to DOT" do
      input_file = File.join(temp_dir, "input.json")
      output_file = File.join(temp_dir, "output.dot")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("digraph")
    end

    it "converts JSON to ELKT" do
      input_file = File.join(temp_dir, "input.json")
      output_file = File.join(temp_dir, "output.elkt")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("node")
    end

    it "converts YAML to JSON" do
      input_file = File.join(temp_dir, "input.yml")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_yaml)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { JSON.parse(content) }.not_to raise_error
    end

    it "converts ELKT to JSON" do
      input_file = File.join(temp_dir, "input.elkt")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, "node n1\nnode n2\nedge n1 -> n2")

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      result = JSON.parse(content)
      expect(result["children"]).to be_an(Array)
    end

    it "converts ELKT to DOT" do
      input_file = File.join(temp_dir, "input.elkt")
      output_file = File.join(temp_dir, "output.dot")

      File.write(input_file, "node n1\nnode n2\nedge n1 -> n2")

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("digraph")
    end

    it "creates output directory if needed" do
      input_file = File.join(temp_dir, "input.json")
      output_file = File.join(temp_dir, "subdir", "output.yml")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "raises error for non-existent file" do
      output_file = File.join(temp_dir, "output.yml")

      command = described_class.new("nonexistent.json", { output: output_file })

      expect { command.run }.to raise_error(ArgumentError, /File not found/)
    end

    it "uses explicit format option" do
      input_file = File.join(temp_dir, "input.json")
      output_file = File.join(temp_dir, "output.txt")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      format: "yaml",
                                    })
      command.run

      content = File.read(output_file)
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "raises error when format cannot be detected" do
      input_file = File.join(temp_dir, "input.json")
      output_file = File.join(temp_dir, "output.unknown")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })

      expect do
        command.run
      end.to raise_error(ArgumentError, /Cannot detect output format/)
    end
  end
end
