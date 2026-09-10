# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../lib/elkrb/graphviz_wrapper"

RSpec.describe Elkrb::GraphvizWrapper do
  let(:wrapper) { described_class.new }

  if Gem.win_platform?
    windows_skip_reason = "these examples install a shebang script, which " \
                          "Windows will not execute from PATH"
  end

  # `available?` must agree with the command `render` actually runs. Ruby execs
  # the string `build_command` builds and searches PATH for it, while
  # `File.executable?("dot")` answers about the working directory, so the two
  # can disagree.
  #
  # Every example works on a real filesystem with a fake `dot`, because a stub
  # cannot show that disagreement. `CANDIDATES` is stubbed because this machine
  # may have a real Graphviz at one of the absolute candidates, which would
  # answer an example for reasons the example did not set up.
  describe "#available?", skip: windows_skip_reason do
    around do |example|
      original_path = ENV.fetch("PATH", nil)
      example.run
    ensure
      ENV["PATH"] = original_path
    end

    def in_sandbox
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write("in.dot", "digraph { a -> b }")
          yield dir
        end
      end
    end

    def stub_candidates(paths)
      stub_const("#{described_class}::CANDIDATES", paths.freeze)
    end

    # Writes whatever `-o` names, so a successful render is observable rather
    # than merely unraised, and the content identifies which fake ran.
    def install_dot(path, tag = "dot")
      script = 'for a in "$@"; do case "$a" in -o*) echo TAG > "${a#-o}";; ' \
               "esac; done; exit 0"
      File.write(path, "#!/bin/sh\n#{script.sub('TAG', tag)}\n")
      FileUtils.chmod(0o755, path)
    end

    # The pair asserted by every example. On the false arm the second element
    # is measured INDEPENDENTLY of `available?`: `render` raises the
    # installation message before any validation, so a `:refused` outcome is
    # entailed by `available? == false` and would assert nothing on its own.
    def verdict
      graphviz = described_class.new
      return [true, render_outcome(graphviz)] if graphviz.available?

      [false, any_candidate_executes?]
    end

    def render_outcome(graphviz)
      FileUtils.rm_f("out.png")
      graphviz.render("in.dot", "out.png", :png)
      File.exist?("out.png") ? :rendered : :ran_without_output
    rescue Elkrb::GraphvizWrapper::GraphvizNotFoundError => e
      e.message.include?("Graphviz is required") ? :refused : :failed
    end

    # A candidate counts as executing only if it also writes its output.
    def any_candidate_executes?
      described_class.const_get(:CANDIDATES).each_with_index.any? do |word, index|
        probe = "probe#{index}.png"
        !system("#{word} -Tpng -o#{probe} in.dot").nil? && File.exist?(probe)
      end
    end

    it "refuses an executable dot the PATH cannot reach" do
      in_sandbox do
        stub_candidates(["dot"])
        install_dot("dot")
        ENV["PATH"] = "/nonexistent-bin"

        expect(verdict).to eq([false, false])
      end
    end

    it "accepts a dot reachable only through PATH" do
      in_sandbox do |dir|
        stub_candidates(["dot"])
        FileUtils.mkdir_p("bin")
        install_dot("bin/dot")
        ENV["PATH"] = File.join(dir, "bin")

        expect(verdict).to eq([true, :rendered])
      end
    end

    it "accepts a dot in a PATH directory whose name contains a space" do
      in_sandbox do |dir|
        stub_candidates(["dot"])
        FileUtils.mkdir_p("b in")
        install_dot("b in/dot")
        ENV["PATH"] = File.join(dir, "b in")

        expect(verdict).to eq([true, :rendered])
      end
    end

    it "refuses a directory named dot found while walking PATH" do
      in_sandbox do |dir|
        stub_candidates(["dot"])
        FileUtils.mkdir_p("bin/dot")
        ENV["PATH"] = File.join(dir, "bin")

        expect(verdict).to eq([false, false])
      end
    end

    it "refuses a non-executable file named dot found while walking PATH" do
      in_sandbox do |dir|
        stub_candidates(["dot"])
        FileUtils.mkdir_p("bin")
        install_dot("bin/dot")
        FileUtils.chmod(0o644, "bin/dot")
        ENV["PATH"] = File.join(dir, "bin")

        expect(verdict).to eq([false, false])
      end
    end

    it "reads an empty PATH as the working directory" do
      in_sandbox do
        stub_candidates(["dot"])
        install_dot("dot")
        ENV["PATH"] = ""

        expect(verdict).to eq([true, :rendered])
      end
    end

    it "reads a trailing PATH separator as an empty field" do
      in_sandbox do |dir|
        stub_candidates(["dot"])
        FileUtils.mkdir_p("bin")
        install_dot("dot")
        ENV["PATH"] = File.join(dir, "bin") + File::PATH_SEPARATOR

        expect(verdict).to eq([true, :rendered])
      end
    end

    # A PATH entry need not be valid UTF-8. Splitting as characters raises
    # ArgumentError, so the constructor itself dies -- while exec walks past
    # the malformed entry and runs the dot in the valid one after it.
    #
    # The process environment carries BYTES and `ENV.fetch` tags them with the
    # locale encoding, so the ambient locale decides whether the hazard can
    # exist at all: under a US-ASCII locale Ruby hands back ASCII-8BIT, which
    # has no invalid sequences. Pin the encoding the code reads instead of
    # inheriting it, so this example means the same thing in every locale.
    # Real bytes still go into the real PATH, because exec resolves the fake
    # `dot` from those. The `have_received` is load-bearing, not ceremony: it
    # is what proves the pinned string is the one PRODUCTION read. Should the
    # code stop calling `ENV.fetch("PATH", "")`, the stub would go unused and
    # this example would quietly revert to inheriting the ambient locale, so
    # that has to fail rather than pass.
    #
    # `raw` is assembled from BYTES rather than interpolated. Under a
    # US-ASCII locale `Dir.mktmpdir` returns an ASCII-8BIT path while this
    # file's literals are UTF-8, and joining those two raises
    # Encoding::CompatibilityError whenever TMPDIR is not pure ASCII.
    it "walks past a PATH entry that is not valid UTF-8" do
      in_sandbox do |dir|
        stub_candidates(["dot"])
        FileUtils.mkdir_p("bin")
        install_dot("bin/dot")
        parts = ["/missing\xFF", File::PATH_SEPARATOR, File.join(dir, "bin")]
        raw = parts.map(&:b).join
        ENV["PATH"] = raw
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("PATH", "")
          .and_return(raw.dup.force_encoding(Encoding::UTF_8))

        expect(verdict).to eq([true, :rendered])
        expect(ENV).to have_received(:fetch).with("PATH", "")
      end
    end

    # An unset PATH sends exec to libruby's own default search, which ENDS in
    # the working directory rather than starting there. Two consequences, and
    # both are load-bearing here. The tag is pinned, because otherwise a host
    # carrying a dot in any directory ahead of the working one answers the
    # bare name and `verdict` alone stays green with the wrong binary. And the
    # candidate's name is deliberately unusual, for that same reason.
    it "reads an unset PATH as an empty one" do
      in_sandbox do
        stub_candidates(["elkrb-fixture-dot"])
        install_dot("elkrb-fixture-dot", "CWD")
        ENV.delete("PATH")

        expect(verdict).to eq([true, :rendered])
        expect(File.read("out.png").strip).to eq("CWD")
      end
    end

    # These candidates are RELATIVE on purpose. What selects the arm under
    # test is `include?(File::SEPARATOR)`, which "abs/dot" satisfies, and a
    # relative candidate cannot inherit a space from TMPDIR the way an
    # absolute one built from the sandbox does -- `build_command` joins with
    # " " and `execute_command` runs `system(<string>)`, so a spaced
    # `@dot_path` word-splits and the example fails on the environment
    # rather than on the code.
    it "refuses a candidate with a separator that is a directory" do
      in_sandbox do
        FileUtils.mkdir_p("abs/dot")
        stub_candidates([File.join("abs", "dot")])
        ENV["PATH"] = "/nonexistent-bin"

        expect(verdict).to eq([false, false])
      end
    end

    it "refuses a candidate with a separator that is not executable" do
      in_sandbox do
        FileUtils.mkdir_p("abs")
        install_dot("abs/dot")
        FileUtils.chmod(0o644, "abs/dot")
        stub_candidates([File.join("abs", "dot")])
        ENV["PATH"] = "/nonexistent-bin"

        expect(verdict).to eq([false, false])
      end
    end

    it "accepts a candidate with a separator that is an executable file" do
      in_sandbox do
        FileUtils.mkdir_p("abs")
        install_dot("abs/dot")
        stub_candidates([File.join("abs", "dot")])
        ENV["PATH"] = "/nonexistent-bin"

        expect(verdict).to eq([true, :rendered])
      end
    end

    it "takes the first candidate that resolves, not a later one" do
      in_sandbox do |dir|
        FileUtils.mkdir_p("bin")
        install_dot("bin/dot", "FIRST")
        FileUtils.mkdir_p("abs")
        install_dot("abs/dot", "SECOND")
        stub_candidates(["dot", File.join(dir, "abs", "dot")])
        ENV["PATH"] = File.join(dir, "bin")

        expect(verdict).to eq([true, :rendered])
        expect(File.read("out.png").strip).to eq("FIRST")
      end
    end

    # The inverted mirror of the example above, and the same candidate shape
    # production ships: a bare "dot" first, a path-bearing one after it. Here
    # the bare one cannot resolve, so the SECOND must be what runs.
    #
    # Keep the tag assertion. It becomes the only check against a future
    # mutant that still renders successfully and merely picks the wrong
    # candidate.
    it "falls through to a later candidate when the first cannot resolve" do
      in_sandbox do
        FileUtils.mkdir_p("abs")
        install_dot("abs/dot", "SECOND")
        stub_candidates(["dot", File.join("abs", "dot")])
        ENV["PATH"] = "/nonexistent-bin"

        expect(verdict).to eq([true, :rendered])
        expect(File.read("out.png").strip).to eq("SECOND")
      end
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
