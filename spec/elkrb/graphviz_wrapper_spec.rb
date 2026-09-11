# frozen_string_literal: true

require "spec_helper"
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

  describe "#find_graphviz" do
    # Both examples above stub File.executable? and #system unconditionally,
    # so they only ever exercise the FIRST candidate -- the candidate list's
    # content, its order, and the per-candidate `which` fallback are never
    # actually reached. Mutant found this: every path in the list can be
    # blanked, reordered, or dropped, and either branch of the if/else can be
    # inverted or collapsed, with both #available? examples staying green.
    it "checks every candidate in the declared order before giving up" do
      checked_executable = []
      checked_which = []
      allow(File).to receive(:executable?) do |path|
        checked_executable << path
        false
      end
      allow_any_instance_of(described_class).to receive(:system) do |_, cmd|
        checked_which << cmd
        false
      end

      test_wrapper = described_class.new

      expect(checked_executable).to eq(
        ["dot", "/usr/bin/dot", "/usr/local/bin/dot", "/opt/homebrew/bin/dot", "/opt/local/bin/dot"],
      )
      expect(checked_which).to eq(
        [
          "which dot > /dev/null 2>&1",
          "which /usr/bin/dot > /dev/null 2>&1",
          "which /usr/local/bin/dot > /dev/null 2>&1",
          "which /opt/homebrew/bin/dot > /dev/null 2>&1",
          "which /opt/local/bin/dot > /dev/null 2>&1",
        ],
      )
      expect(test_wrapper.send(:find_graphviz)).to be_nil
    end

    it "returns the last candidate once it is found directly executable" do
      allow(File).to receive(:executable?) { |path| path == "/opt/local/bin/dot" }
      allow_any_instance_of(described_class).to receive(:system).and_return(false)

      test_wrapper = described_class.new

      expect(test_wrapper.send(:find_graphviz)).to eq("/opt/local/bin/dot")
    end

    it "returns the candidate found via `which` when it is not directly executable" do
      allow(File).to receive(:executable?).and_return(false)
      allow_any_instance_of(described_class).to receive(:system) do |_, cmd|
        cmd.include?("/opt/homebrew/bin/dot")
      end

      test_wrapper = described_class.new

      expect(test_wrapper.send(:find_graphviz)).to eq("/opt/homebrew/bin/dot")
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
      expect(wrapper).to receive(:system)
        .with(/neato/)
        .and_return(true)

      wrapper.render("input.dot", "output.png", :png, engine: "neato")
    end

    it "uses specified DPI" do
      expect(wrapper).to receive(:system)
        .with(/dpi=150/)
        .and_return(true)

      wrapper.render("input.dot", "output.png", :png, dpi: 150)
    end

    # Every other example in this describe block stubs #system with no
    # argument matcher (or a matcher on one substring), so nothing ever
    # checks the FULL command build_command produces: which flags, in what
    # order, joined how, or what happens when no dpi: option is given at
    # all. Mutant found this -- default dpi=96, the -o flag, the join
    # separator, and the input file argument all mutate freely with every
    # spec here staying green. Pin the whole string once instead of one
    # substring at a time.
    it "uses the default DPI and builds the exact command line" do
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
      captured_cmd = nil
      allow(wrapper).to receive(:system) do |cmd|
        captured_cmd = cmd
        true
      end

      wrapper.render("input.dot", "output.png", :png)

      expect(captured_cmd).to eq("/usr/bin/dot -Kdot -Tpng -Gdpi=96 -ooutput.png input.dot")
    end

    it "omits the -o flag when no output file is given" do
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
      captured_cmd = nil
      allow(wrapper).to receive(:system) do |cmd|
        captured_cmd = cmd
        true
      end

      wrapper.render("input.dot", nil, :png)

      expect(captured_cmd).to eq("/usr/bin/dot -Kdot -Tpng -Gdpi=96 input.dot")
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

    # Both format examples pass a Symbol, which is already what
    # SUPPORTED_FORMATS holds, so `format.to_sym` is a no-op for them and
    # mutating it away to bare `format` stays invisible. A String format
    # tells them apart -- callers of this public method may reasonably pass
    # either.
    it "accepts a format given as a string by converting it with to_sym" do
      expect(wrapper).to receive(:system).with(/-Tpng/).and_return(true)

      wrapper.render("input.dot", "output.png", "png")
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

    it "names the exact missing file in the error message" do
      allow(File).to receive(:exist?).with("missing.dot").and_return(false)

      expect do
        wrapper.render("missing.dot", "output.png", :png)
      end.to raise_error(ArgumentError, "Input file not found: missing.dot")
    end

    it "raises error when command fails" do
      allow(wrapper).to receive(:system).and_return(false)

      expect do
        wrapper.render("input.dot", "output.png", :png)
      end.to raise_error(Elkrb::GraphvizWrapper::GraphvizNotFoundError,
                         /command failed/)
    end

    # No example anywhere in this file checks #render's own return value --
    # every success case stubs #system and stops there. Mutant found this:
    # #execute_command's `success` result can be replaced with nil, or
    # dropped entirely, with the whole suite staying green.
    it "returns the underlying system call's success value" do
      allow(wrapper).to receive(:system).and_return(true)

      expect(wrapper.render("input.dot", "output.png", :png)).to be true
    end

    it "names the exact failing command in the error message" do
      allow(wrapper).to receive(:system).and_return(false)

      expect do
        wrapper.render("input.dot", "output.png", :png)
      end.to raise_error(Elkrb::GraphvizWrapper::GraphvizNotFoundError,
                         /-Tpng.*-ooutput\.png input\.dot/)
    end

    # "uses specified engine" and "raises error for unsupported engine" both
    # pass a String, so `engine.to_s` can be swapped for `engine.to_str` or
    # for bare `engine` and every example stays green -- String responds to
    # all three identically. A Symbol tells them apart: it responds to
    # #to_s but not #to_str, and is never #== to the String elements
    # SUPPORTED_ENGINES actually holds.
    it "accepts an engine given as a symbol by converting it with to_s" do
      expect(wrapper).to receive(:system).with(/-Kdot/).and_return(true)

      wrapper.render("input.dot", "output.png", :png, engine: :dot)
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

    # The one example above uses a single space and lowercase "version", so
    # `\s+` can shrink to `\s` and the `i` flag can be dropped without
    # anything noticing. And nothing ever shells out to the ACTUAL @dot_path
    # -- `#{@dot_path}` in the backtick command can be replaced with `#{nil}`
    # and every example stays green, since `allow(wrapper).to receive(:\`)`
    # matches any argument.
    it "shells out to the wrapper's own dot path, not a stale reference" do
      allow(wrapper).to receive(:available?).and_return(true)
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")

      expect(wrapper).to receive(:`)
        .with("/usr/bin/dot -V 2>&1")
        .and_return("dot - graphviz version 2.44.1 (20200629.0846)")

      expect(wrapper.version).to eq("2.44.1")
    end

    it "matches one-or-more whitespace characters, case-insensitively" do
      allow(wrapper).to receive(:available?).and_return(true)
      allow(wrapper).to receive(:`).and_return("dot - graphviz VERSION  2.44.1 (2020)")

      expect(wrapper.version).to eq("2.44.1")
    end

    it "returns nil, rather than raising, when the output has no version to parse" do
      allow(wrapper).to receive(:available?).and_return(true)
      allow(wrapper).to receive(:`).and_return("dot: command not found")

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
