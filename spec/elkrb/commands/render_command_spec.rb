# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/elkrb/graphviz_wrapper"
require_relative "../../../lib/elkrb/commands/render_command"

RSpec.describe Elkrb::Commands::RenderCommand do
  let(:temp_dir) { Dir.mktmpdir }
  let(:dot_content) do
    <<~DOT
      digraph G {
        n1 -> n2;
      }
    DOT
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#run" do
    before do
      allow_any_instance_of(Elkrb::GraphvizWrapper).to receive(:render)
    end

    it "renders DOT to PNG" do
      dot_file = File.join(temp_dir, "input.dot")
      output_file = File.join(temp_dir, "output.png")

      File.write(dot_file, dot_content)

      expect_any_instance_of(Elkrb::GraphvizWrapper).to receive(:render)
        .with(dot_file, output_file, :png, hash_including(engine: "dot",
                                                          dpi: 96))

      command = described_class.new(dot_file, { output: output_file })
      command.run
    end

    it "renders DOT to SVG" do
      dot_file = File.join(temp_dir, "input.dot")
      output_file = File.join(temp_dir, "output.svg")

      File.write(dot_file, dot_content)

      expect_any_instance_of(Elkrb::GraphvizWrapper).to receive(:render)
        .with(dot_file, output_file, :svg, anything)

      command = described_class.new(dot_file, { output: output_file })
      command.run
    end

    it "renders DOT to PDF" do
      dot_file = File.join(temp_dir, "input.dot")
      output_file = File.join(temp_dir, "output.pdf")

      File.write(dot_file, dot_content)

      expect_any_instance_of(Elkrb::GraphvizWrapper).to receive(:render)
        .with(dot_file, output_file, :pdf, anything)

      command = described_class.new(dot_file, { output: output_file })
      command.run
    end

    it "uses custom engine" do
      dot_file = File.join(temp_dir, "input.dot")
      output_file = File.join(temp_dir, "output.png")

      File.write(dot_file, dot_content)

      expect_any_instance_of(Elkrb::GraphvizWrapper).to receive(:render)
        .with(dot_file, output_file, :png, hash_including(engine: "neato"))

      command = described_class.new(dot_file, {
                                      output: output_file,
                                      engine: "neato",
                                    })
      command.run
    end

    it "uses custom DPI" do
      dot_file = File.join(temp_dir, "input.dot")
      output_file = File.join(temp_dir, "output.png")

      File.write(dot_file, dot_content)

      expect_any_instance_of(Elkrb::GraphvizWrapper).to receive(:render)
        .with(dot_file, output_file, :png, hash_including(dpi: 150))

      command = described_class.new(dot_file, {
                                      output: output_file,
                                      dpi: 150,
                                    })
      command.run
    end

    it "raises error for non-existent file" do
      output_file = File.join(temp_dir, "output.png")

      command = described_class.new("nonexistent.dot", { output: output_file })

      expect { command.run }.to raise_error(ArgumentError, /File not found/)
    end

    it "raises error for unknown image format" do
      dot_file = File.join(temp_dir, "input.dot")
      output_file = File.join(temp_dir, "output.xyz")

      File.write(dot_file, dot_content)

      command = described_class.new(dot_file, { output: output_file })

      expect do
        command.run
      end.to raise_error(ArgumentError, /Cannot detect image format/)
    end

    it "supports PS format" do
      dot_file = File.join(temp_dir, "input.dot")
      output_file = File.join(temp_dir, "output.ps")

      File.write(dot_file, dot_content)

      expect_any_instance_of(Elkrb::GraphvizWrapper).to receive(:render)
        .with(dot_file, output_file, :ps, anything)

      command = described_class.new(dot_file, { output: output_file })
      command.run
    end
  end
end
