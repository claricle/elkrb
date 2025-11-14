# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/elkrb/commands/batch_command"

RSpec.describe Elkrb::Commands::BatchCommand do
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
    it "processes multiple JSON files" do
      input_dir = File.join(temp_dir, "input")
      output_dir = File.join(temp_dir, "output")
      FileUtils.mkdir_p(input_dir)

      File.write(File.join(input_dir, "graph1.json"), graph_data.to_json)
      File.write(File.join(input_dir, "graph2.json"), graph_data.to_json)

      command = described_class.new(input_dir, {
                                      output_dir: output_dir,
                                      format: "dot",
                                    })
      command.run

      expect(File.exist?(File.join(output_dir, "graph1.dot"))).to be true
      expect(File.exist?(File.join(output_dir, "graph2.dot"))).to be true
    end

    it "processes multiple YAML files" do
      input_dir = File.join(temp_dir, "input")
      output_dir = File.join(temp_dir, "output")
      FileUtils.mkdir_p(input_dir)

      File.write(File.join(input_dir, "graph1.yml"), graph_data.to_yaml)
      File.write(File.join(input_dir, "graph2.yaml"), graph_data.to_yaml)

      command = described_class.new(input_dir, {
                                      output_dir: output_dir,
                                      format: "json",
                                    })
      command.run

      expect(File.exist?(File.join(output_dir, "graph1.json"))).to be true
      expect(File.exist?(File.join(output_dir, "graph2.json"))).to be true
    end

    it "processes ELKT files" do
      input_dir = File.join(temp_dir, "input")
      output_dir = File.join(temp_dir, "output")
      FileUtils.mkdir_p(input_dir)

      File.write(File.join(input_dir, "graph1.elkt"),
                 "node n1\nnode n2\nedge n1 -> n2")

      command = described_class.new(input_dir, {
                                      output_dir: output_dir,
                                      format: "dot",
                                    })
      command.run

      expect(File.exist?(File.join(output_dir, "graph1.dot"))).to be true
    end

    it "creates output directory if needed" do
      input_dir = File.join(temp_dir, "input")
      output_dir = File.join(temp_dir, "output")
      FileUtils.mkdir_p(input_dir)

      File.write(File.join(input_dir, "graph1.json"), graph_data.to_json)

      command = described_class.new(input_dir, {
                                      output_dir: output_dir,
                                      format: "dot",
                                    })
      command.run

      expect(Dir.exist?(output_dir)).to be true
    end

    it "handles empty directory" do
      input_dir = File.join(temp_dir, "input")
      output_dir = File.join(temp_dir, "output")
      FileUtils.mkdir_p(input_dir)

      command = described_class.new(input_dir, {
                                      output_dir: output_dir,
                                      format: "dot",
                                    })

      expect { command.run }.to output(/No graph files found/).to_stdout
    end

    it "continues on error" do
      input_dir = File.join(temp_dir, "input")
      output_dir = File.join(temp_dir, "output")
      FileUtils.mkdir_p(input_dir)

      File.write(File.join(input_dir, "valid.json"), graph_data.to_json)
      File.write(File.join(input_dir, "invalid.json"), "not valid json")

      command = described_class.new(input_dir, {
                                      output_dir: output_dir,
                                      format: "dot",
                                    })

      expect { command.run }.to output(/Error processing/).to_stderr
    end

    it "reports success and error counts" do
      input_dir = File.join(temp_dir, "input")
      output_dir = File.join(temp_dir, "output")
      FileUtils.mkdir_p(input_dir)

      File.write(File.join(input_dir, "graph1.json"), graph_data.to_json)
      File.write(File.join(input_dir, "graph2.json"), graph_data.to_json)

      command = described_class.new(input_dir, {
                                      output_dir: output_dir,
                                      format: "dot",
                                    })

      expect { command.run }.to output(/Processed 2 file/).to_stdout
    end

    it "raises error for non-existent directory" do
      output_dir = File.join(temp_dir, "output")

      command = described_class.new("nonexistent", {
                                      output_dir: output_dir,
                                      format: "dot",
                                    })

      expect do
        command.run
      end.to raise_error(ArgumentError, /Directory not found/)
    end
  end
end
