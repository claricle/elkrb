# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "pathname"
require_relative "../../lib/elkrb/graphviz_wrapper"

RSpec.describe Elkrb::GraphvizWrapper do
  let(:wrapper) { described_class.new }

  describe "#available?" do
    it "returns true when Graphviz is found" do
      allow(File).to receive(:executable?).and_return(false)
      allow_any_instance_of(described_class).to receive(:system).and_return(true)

      test_wrapper = described_class.new
      expect(test_wrapper.available?).to be true
    end

    it "returns false when Graphviz is not found" do
      allow(File).to receive(:executable?).and_return(false)
      allow_any_instance_of(described_class).to receive(:system).and_return(false)

      wrapper_without_graphviz = described_class.new
      expect(wrapper_without_graphviz.available?).to be false
    end
  end

  describe "#render" do
    before do
      allow(wrapper).to receive(:available?).and_return(true)
      allow(File).to receive(:exist?).and_return(true)
    end

    it "renders DOT file to PNG" do
      expect(wrapper).to receive(:system).and_return(true)

      wrapper.render("input.dot", "output.png", :png)
    end

    it "renders DOT file to SVG" do
      expect(wrapper).to receive(:system).and_return(true)

      wrapper.render("input.dot", "output.svg", :svg)
    end

    it "renders DOT file to PDF" do
      expect(wrapper).to receive(:system).and_return(true)

      wrapper.render("input.dot", "output.pdf", :pdf)
    end

    it "uses specified engine" do
      expect(wrapper).to receive(:system) do |*command|
        expect(command).to include("-Kneato")
        true
      end

      wrapper.render("input.dot", "output.png", :png, engine: "neato")
    end

    it "uses specified DPI" do
      expect(wrapper).to receive(:system) do |*command|
        expect(command).to include("-Gdpi=150")
        true
      end

      wrapper.render("input.dot", "output.png", :png, dpi: 150)
    end

    it "does not execute a shell metacharacter embedded in the output path" do
      skip "no 'true' binary on PATH" unless system("which true > /dev/null 2>&1")

      Dir.mktmpdir do |dir|
        marker = File.join(dir, "PWNED")
        dot_file = File.join(dir, "in.dot")
        File.write(dot_file, "digraph{a->b}")
        malicious_output = File.join(dir, "out.png; touch #{marker}")

        # No system stub here: this runs the real execute_command against a
        # real (harmless, always-succeeding) command, so a shell would
        # actually have to be invoked for the metacharacter to fire. The
        # available?/File.exist? stubs below override the file-level `before`
        # block's blanket stubs so this test hits the real filesystem too.
        wrapper.instance_variable_set(:@dot_path, "true")
        allow(wrapper).to receive(:available?).and_call_original
        allow(File).to receive(:exist?).and_call_original

        expect(wrapper.render(dot_file, malicious_output, :png)).to be true
        expect(File.file?(marker)).to be false
      end
    end

    it "raises error when Graphviz is not available" do
      allow(wrapper).to receive(:available?).and_return(false)

      expect do
        wrapper.render("input.dot", "output.png", :png)
      end.to raise_error(Elkrb::GraphvizWrapper::GraphvizNotFoundError,
                         /Graphviz is required/)
    end

    it "raises error for unsupported format" do
      expect do
        wrapper.render("input.dot", "output.xyz", :xyz)
      end.to raise_error(ArgumentError, /Unsupported format/)
    end

    it "raises error for unsupported engine" do
      expect do
        wrapper.render("input.dot", "output.png", :png, engine: "invalid")
      end.to raise_error(ArgumentError, /Unsupported engine/)
    end

    it "raises error when input file does not exist" do
      allow(File).to receive(:exist?).with("missing.dot").and_return(false)

      expect do
        wrapper.render("missing.dot", "output.png", :png)
      end.to raise_error(ArgumentError, /Input file not found/)
    end

    it "coerces a Pathname input file to a String" do
      expect(wrapper).to receive(:system) do |*command|
        expect(command.last).to eq("input.dot")
        expect(command.last).to be_a(String)
        true
      end

      wrapper.render(Pathname.new("input.dot"), "output.png", :png)
    end

    it "coerces any input file object to a String, not just Pathname" do
      custom_path = Object.new
      def custom_path.to_s = "input.dot"

      expect(wrapper).to receive(:system) do |*command|
        expect(command.last).to eq("input.dot")
        expect(command.last).to be_a(String)
        true
      end

      wrapper.render(custom_path, "output.png", :png)
    end

    it "raises error when command fails" do
      allow(wrapper).to receive(:system).and_return(false)

      expect do
        wrapper.render("input.dot", "output.png", :png)
      end.to raise_error(Elkrb::GraphvizWrapper::GraphvizNotFoundError,
                         /command failed/)
    end
  end

  describe "#version" do
    it "returns Graphviz version when available" do
      allow(wrapper).to receive(:available?).and_return(true)
      allow(wrapper).to receive(:`).and_return("dot - graphviz version 2.44.1 (20200629.0846)")

      expect(wrapper.version).to eq("2.44.1")
    end

    it "returns nil when Graphviz is not available" do
      allow(wrapper).to receive(:available?).and_return(false)

      expect(wrapper.version).to be_nil
    end
  end

  describe "#supported_formats" do
    it "returns list of supported formats" do
      formats = wrapper.supported_formats

      expect(formats).to include(:png, :svg, :pdf, :ps, :eps)
    end
  end

  describe "#supported_engines" do
    it "returns list of supported engines" do
      engines = wrapper.supported_engines

      expect(engines).to include("dot", "neato", "fdp", "sfdp", "twopi",
                                 "circo")
    end
  end

  describe "error messages" do
    it "provides helpful installation instructions" do
      allow(wrapper).to receive(:available?).and_return(false)

      begin
        wrapper.render("input.dot", "output.png", :png)
      rescue Elkrb::GraphvizWrapper::GraphvizNotFoundError => e
        expect(e.message).to include("brew install graphviz")
        expect(e.message).to include("apt-get install graphviz")
        expect(e.message).to include("elkrb diagram")
      end
    end
  end
end
