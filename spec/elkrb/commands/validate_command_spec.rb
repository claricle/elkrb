# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/elkrb/commands/validate_command"

RSpec.describe Elkrb::Commands::ValidateCommand do
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

    it "raises error for non-existent file" do
      command = described_class.new("nonexistent.json", {})

      expect { command.run }.to raise_error(ArgumentError, /File not found/)
    end
  end
end
