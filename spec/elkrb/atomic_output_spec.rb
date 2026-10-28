# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../lib/elkrb/cli"
require_relative "../../lib/elkrb/commands/convert_command"
require_relative "../../lib/elkrb/commands/diagram_command"
require_relative "../../lib/elkrb/commands/render_command"

RSpec.describe "atomic CLI output" do
  let(:directory) { Dir.mktmpdir }
  let(:destination) { File.join(directory, "result.json") }

  before { File.write(destination, "original") }

  after { FileUtils.remove_entry(directory) }

  def fail_staged_text_write
    allow(File).to receive(:binwrite)
      .and_wrap_original do |original, path, content|
      if File.basename(path).start_with?(".elkrb-")
        File.write(path, content.to_s.byteslice(0, 7))
        raise IOError, "writer stopped"
      end

      original.call(path, content)
    end
  end

  it "preserves layout output when its write stops partway" do
    fail_staged_text_write
    cli = Elkrb::Cli.new
    allow(cli).to receive(:options)
      .and_return(output: destination, format: "json", verbose: false)
    result = instance_double(Elkrb::Graph::Graph, to_json: "replacement")

    expect { cli.send(:output_result, result) }
      .to raise_error(IOError, "writer stopped")
    expect(File.read(destination)).to eq("original")
  end

  it "preserves convert output when its write stops partway" do
    input = File.join(directory, "input.json")
    File.write(input, { id: "root", children: [], edges: [] }.to_json)
    fail_staged_text_write

    command = Elkrb::Commands::ConvertCommand.new(
      input, output: destination, format: "json"
    )

    expect { command.run }.to raise_error(IOError, "writer stopped")
    expect(File.read(destination)).to eq("original")
  end

  it "preserves text diagram output when its write stops partway" do
    input = File.join(directory, "input.json")
    graph = {
      id: "root",
      layoutOptions: { "elk.algorithm" => "fixed" },
      children: [],
      edges: [],
    }
    File.write(input, graph.to_json)
    fail_staged_text_write

    command = Elkrb::Commands::DiagramCommand.new(
      input, output: destination, format: "json"
    )

    expect { command.run }.to raise_error(IOError, "writer stopped")
    expect(File.read(destination)).to eq("original")
  end
end
