# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "pathname"
require_relative "../../lib/elkrb/graphviz_wrapper"

# Helpers for the PATH-resolution examples below. A `let` cannot take a block
# or an argument -- `let(:x) { |a| a }` yields the RSpec example, not the
# argument -- so these have to be methods. They live in a module included into
# the example group rather than as bare `def`s in this file, because a bare
# `def` here becomes a private method on Object and is then reachable from
# every other spec in the suite.
module GraphvizPathHelpers
  DOT_CANDIDATES = [
    "dot",
    "/usr/bin/dot",
    "/usr/local/bin/dot",
    "/opt/homebrew/bin/dot",
    "/opt/local/bin/dot",
  ].freeze

  # Every Kernel route that can hand a string to a shell or start a child,
  # intersected with what Kernel actually defines so a typo cannot silently
  # empty the list.
  SHELL_ROUTES = (%i[system spawn exec fork `] &
                  Kernel.private_instance_methods(false)).freeze

  # Make every candidate `find_graphviz` probes directly look absent, so an
  # example can prove what the PATH walk alone does.
  def stub_candidates_missing
    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:executable?).and_call_original
    DOT_CANDIDATES.each { |candidate| stub_executable(candidate, false) }
  end

  def stub_executable(path, present)
    allow(File).to receive(:file?).with(path).and_return(present)
    allow(File).to receive(:executable?).with(path).and_return(present)
  end

  # REMOVES the capability rather than watching for it: a subclass whose every
  # shell route raises. An implementation that shells out fails loudly here
  # instead of passing unnoticed, and the expectation stays POSITIVE -- the
  # honest PATH walk still finds the binary.
  def shell_free_subclass
    raise "no shell routes derived from Kernel" if SHELL_ROUTES.empty?

    routes = SHELL_ROUTES
    Class.new(Elkrb::GraphvizWrapper) do
      routes.each do |route|
        define_method(route) { |*| raise "spawned a child through ##{route}" }
      end
    end
  end

  # `ENV.fetch("PATH", "")` cannot tell unset from empty, so capture the raw
  # value and delete the key again if that is what was there.
  def with_path(dir)
    original = ENV.fetch("PATH", nil)
    ENV["PATH"] = dir
    yield
  ensure
    if original.nil?
      ENV.delete("PATH")
    else
      ENV["PATH"] = original
    end
  end
end

RSpec.describe Elkrb::GraphvizWrapper do
  include GraphvizPathHelpers

  let(:wrapper) { described_class.new }

  describe "#available?" do
    it "returns true when Graphviz is found" do
      allow(File).to receive(:file?).and_return(true)
      allow(File).to receive(:executable?).and_return(true)

      expect(described_class.new.available?).to be true
    end

    # `File.executable?` on its own is true for a DIRECTORY, and exec is not.
    it "does not accept a directory named dot as the binary" do
      allow(File).to receive(:file?).and_return(false)
      allow(File).to receive(:executable?).and_return(true)

      expect(described_class.new.available?).to be false
    end

    # Deleting the `File.executable?` fast path would make every absolute
    # candidate unreachable, since a path with a separator is not walked.
    it "finds an absolute candidate that is not on PATH" do
      stub_candidates_missing
      stub_executable("/usr/local/bin/dot", true)

      with_path("/nonexistent") do
        expect(described_class.new.available?).to be true
      end
    end

    # An empty PATH element must be DROPPED, not walked: File.join("", "dot")
    # is "/dot", so walking it would probe the root directory. The separator
    # is taken from `File::PATH_SEPARATOR` rather than hard-coded ":" -- it is
    # ";" on Windows, where a literal ":" would build no empty element at all
    # and this example would pass without asserting anything.
    it "does not probe the root directory for an empty PATH entry" do
      stub_candidates_missing
      stub_executable("/dot", true)

      with_path("#{File::PATH_SEPARATOR}/nonexistent") do
        expect(described_class.new.available?).to be false
      end
    end

    it "returns false when Graphviz is not found" do
      allow(File).to receive(:executable?).and_return(false)

      expect(described_class.new.available?).to be false
    end

    # Without the `File::SEPARATOR` guard in `executable_candidate?`, an
    # absolute candidate would be joined onto every PATH entry --
    # File.join("/some/dir", "/usr/bin/dot") is "/some/dir/usr/bin/dot" -- and
    # an unrelated file sitting there would be reported as Graphviz. execvp
    # does not PATH-search a name containing a slash, and neither do we.
    it "does not PATH-search a candidate that is already a path" do
      Dir.mktmpdir do |dir|
        decoy = File.join(dir, "usr", "bin", "dot")
        FileUtils.mkdir_p(File.dirname(decoy))
        File.write(decoy, "")
        File.chmod(0o755, decoy)

        stub_candidates_missing

        with_path(dir) do
          expect(described_class.new.available?).to be false
        end
      end
    end

    # `find_graphviz` used to resolve the bare name "dot" by shelling out to
    # `which`. Two halves matter and they need separate proof: that the
    # replacement still FINDS the binary, and that it finds it without
    # spawning anything. `available? == true` alone proves only the first --
    # an implementation running `system("command -v #{path}")` passes it.
    it "resolves a bare 'dot' on PATH" do
      Dir.mktmpdir do |dir|
        fake_dot = File.join(dir, "dot")
        File.write(fake_dot, "")
        File.chmod(0o755, fake_dot)

        stub_candidates_missing

        with_path(dir) do
          expect(described_class.new.available?).to be true
        end
      end
    end

    it "resolves it without spawning a child process" do
      Dir.mktmpdir do |dir|
        fake_dot = File.join(dir, "dot")
        File.write(fake_dot, "")
        File.chmod(0o755, fake_dot)

        stub_candidates_missing

        with_path(dir) do
          expect(shell_free_subclass.new.available?).to be true
        end
      end
    end
  end

  describe "#render" do
    before do
      allow(wrapper).to receive(:available?).and_return(true)
      allow(File).to receive(:exist?).and_return(true)
      # Pin the binary. Left to `find_graphviz` this comes off the real
      # filesystem, so argv[0] is nil on a host without graphviz and every
      # exact-argv assertion below turns into a host-dependent failure.
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
    end

    it "renders DOT file to PNG" do
      expect(wrapper).to receive(:system).and_return(true)

      wrapper.render("input.dot", "output.png", :png)
    end

    # `system(*argv)` falls back to SHELL semantics when argv has exactly one
    # element, so the whole no-shell guarantee rests on this argv being long.
    # Keep this: it is the only assertion on the command's EXACT shape, and it
    # becomes the only check on argument ORDER the moment the coercion
    # examples below stop pinning positions.
    it "passes dot a multi-element argv, never a single command string" do
      expect(wrapper).to receive(:system) do |*command|
        expect(command).to eq(
          ["/usr/bin/dot", "-Kdot", "-Tpng", "-Gdpi=96", "-ooutput.png",
           "input.dot"],
        )
        true
      end

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

    # This is the assertion that CARRIES the property, because it cannot skip
    # and needs no binary: a metacharacter stays one argv element. The
    # end-to-end example below is a supplement, and it is unavailable on
    # Windows, where a chmod +x shebang script is not executable.
    it "keeps a shell metacharacter in the output path as one argv element" do
      malicious_output = "out.png; touch PWNED"

      expect(wrapper).to receive(:system) do |*command|
        expect(command.size).to be > 1
        expect(command).to include("-o#{malicious_output}")
        expect(command).to all(be_a(String))
        true
      end

      wrapper.render("input.dot", malicious_output, :png)
    end

    it "does not execute a shell metacharacter embedded in the output path" do
      skip "a chmod +x shebang script is not executable" if Gem.win_platform?

      Dir.mktmpdir do |dir|
        marker = File.join(dir, "PWNED")
        dot_file = File.join(dir, "in.dot")
        File.write(dot_file, "digraph{a->b}")
        malicious_output = File.join(dir, "out.png; touch #{marker}")

        # The stand-in for `dot` is WRITTEN here rather than looked up. A
        # lookup would skip on any host missing the binary it looked for, and
        # a skipped example is invisible in a green run.
        no_op = File.join(dir, "no-op")
        File.write(no_op, "#!#{RbConfig.ruby}\nexit 0\n")
        File.chmod(0o755, no_op)

        # No system stub here: this runs the real execute_command against a
        # real (harmless, always-succeeding) command, so a shell would
        # actually have to be invoked for the metacharacter to fire. The two
        # and_call_original lines below undo the file-level `before` block's
        # blanket stubs so this example touches the real filesystem; measured,
        # it passes without them, so they buy honesty here, not coverage.
        wrapper.instance_variable_set(:@dot_path, no_op)
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

    # Same reachable set as the input path, and not even narrowed by
    # `validate_file_exists!`. Uncoerced, dot was handed "#<Object:0x...>" as
    # the -o value, wrote a file by that name, and reported success.
    it "coerces a to_path output file to its real path" do
      custom_path = Object.new
      def custom_path.to_path = "output.png"

      expect(wrapper).to receive(:system) do |*command|
        expect(command).to include("-ooutput.png")
        expect(command).to all(be_a(String))
        true
      end

      wrapper.render("input.dot", custom_path, :png)
    end

    # Removing the shell closes command injection, not ARGUMENT injection: dot
    # reads a bare positional beginning with "-" as an option, so an input file
    # named "-ovictim.txt" became a second -o. Measured against graphviz
    # 15.1.1, "--" is rejected ("dot: option -- unrecognized") and "./" works.
    it "keeps a dash-leading input file from being read as a dot option" do
      expect(wrapper).to receive(:system) do |*command|
        expect(command.last).to eq("./-ovictim.txt")
        true
      end

      wrapper.render("-ovictim.txt", "output.png", :png)
    end

    it "coerces a Pathname input file to a String" do
      expect(wrapper).to receive(:system) do |*command|
        expect(command).to include("input.dot")
        expect(command).to all(be_a(String))
        true
      end

      wrapper.render(Pathname.new("input.dot"), "output.png", :png)
    end

    # The reachable input set for this coercion is exactly what
    # `validate_file_exists!` lets through -- a String, or an object with
    # `#to_path`. A `#to_s`-only object cannot get here at all: `File.exist?`
    # raises TypeError on it first. So `#to_path` is the case that generalises
    # past Pathname, and it is the one `#to_s` would silently get wrong.
    it "coerces a non-Pathname to_path object to its real path" do
      custom_path = Object.new
      def custom_path.to_path = "input.dot"

      expect(wrapper).to receive(:system) do |*command|
        expect(command).to include("input.dot")
        expect(command).to all(be_a(String))
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
    # Runs a REAL stand-in binary rather than a stub, so `&:read` and
    # `err: %i[child out]` are both load-bearing: without the block `version`
    # calls `match` on an IO, and without `err:` the version line -- which dot
    # writes to stderr -- never arrives.
    it "reads the version from the binary's own stderr" do
      Dir.mktmpdir do |dir|
        stand_in = File.join(dir, "dot")
        File.write(stand_in,
                   "#!#{RbConfig.ruby}\n" \
                   "$stderr.puts 'dot - graphviz version 2.44.1 (20200629.0846)'\n")
        File.chmod(0o755, stand_in)

        allow(wrapper).to receive(:available?).and_return(true)
        wrapper.instance_variable_set(:@dot_path, stand_in)

        expect(wrapper.version).to eq("2.44.1")
      end
    end

    # `available?` only proves a path looked executable once. The backticks
    # this replaced always returned a String, because /bin/sh absorbed the
    # failure; `IO.popen` execs directly and raises.
    it "returns nil when the recorded path can no longer be executed" do
      allow(wrapper).to receive(:available?).and_return(true)
      wrapper.instance_variable_set(:@dot_path, "/nonexistent/dot")

      expect(wrapper.version).to be_nil
    end

    it "returns Graphviz version when available" do
      allow(wrapper).to receive(:available?).and_return(true)
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
      # argv array, not a command string: `#version` must not shell out either.
      expect(IO).to receive(:popen)
        .with(["/usr/bin/dot", "-V"], err: %i[child out])
        .and_return("dot - graphviz version 2.44.1 (20200629.0846)")

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
