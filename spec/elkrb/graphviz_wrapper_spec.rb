# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "pathname"
require_relative "../../lib/elkrb/graphviz_wrapper"

RSpec.describe Elkrb::GraphvizWrapper do
  let(:wrapper) { described_class.new }

  if Gem.win_platform?
    windows_skip_reason = "these examples install a shebang script, which " \
                          "Windows will not execute from PATH"
  end

  # Pure-Ruby PATH search. `system("which true ...")` would itself invoke a
  # shell -- the very thing this file exists to prove we no longer do -- and
  # would skip the test on any environment that has `true` but not `which`.
  let(:true_binary) do
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).reject(&:empty?)
      .map { |dir| File.join(dir, "true") }
      .find { |candidate| File.file?(candidate) && File.executable?(candidate) }
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

    # A PATH entry need not be valid UTF-8; exec walks past a malformed entry
    # rather than dying. Pin the encoding `ENV.fetch("PATH", "")` returns
    # (rather than inheriting the ambient locale) so this means the same
    # thing everywhere, and keep the `have_received` assertion -- it is what
    # proves the pinned string is the one production code reads, not the
    # real `ENV["PATH"]`. Build `raw` from bytes, not interpolation, so a
    # non-ASCII TMPDIR under a US-ASCII locale cannot raise
    # Encoding::CompatibilityError.
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

  # Every example above stubs CANDIDATES to isolate the resolution logic
  # from whatever Graphviz install (if any) sits on this machine, so none
  # of them ever reads the real list `.new` uses in production. Pin its
  # content directly: a bare "dot" first (so a plain PATH hit wins) and the
  # known package-manager install locations after it.
  describe "::CANDIDATES" do
    it "lists the bare command before its known absolute install paths" do
      candidates = described_class.const_get(:CANDIDATES)

      expect(candidates).to eq(
        [
          "dot",
          "/usr/bin/dot",
          "/usr/local/bin/dot",
          "/opt/homebrew/bin/dot",
          "/opt/local/bin/dot",
        ],
      )
    end
  end

  # CommandResolver's platform-conditional behaviour (PATHEXT/`dot.exe`
  # fan-out, `~` expansion) does not depend on which OS the suite runs
  # under -- it depends on what `Gem.win_platform?` and `ENV["HOME"]` say.
  # Stubbing those lets these examples run, and assert something, on every
  # CI platform, unlike the `#available?` group above which genuinely
  # requires a real shebang-executable file and so cannot run on Windows.
  # `Elkrb.private_constant :CommandResolver` is the only line making this
  # module internal; every other example reaches it via `Elkrb.const_get`
  # specifically because plain constant lookup no longer works. Assert
  # that directly, or a revert of the `private_constant` call would leave
  # every other example green while re-exposing the module.
  it "keeps CommandResolver off the public constant table" do
    expect { Elkrb::CommandResolver }.to raise_error(NameError)
  end

  describe "CommandResolver platform behaviour" do
    let(:resolver) { Elkrb.const_get(:CommandResolver) }

    around do |example|
      original_path = ENV.fetch("PATH", nil)
      original_home = ENV.fetch("HOME", nil) # rubocop:disable Style/EnvHome -- restoring the raw var, not reading a home dir
      original_pathext = ENV.fetch("PATHEXT", nil)
      example.run
    ensure
      ENV["PATH"] = original_path
      ENV["HOME"] = original_home
      ENV["PATHEXT"] = original_pathext
    end

    def in_sandbox
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { yield dir }
      end
    end

    def write_executable(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "")
      FileUtils.chmod(0o755, path)
    end

    context "on Windows (Gem.win_platform? stubbed true)" do
      before { allow(Gem).to receive(:win_platform?).and_return(true) }

      it "finds dot.exe via PATHEXT for a bare candidate name" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "bin", "dot.exe"))
          ENV["PATH"] = File.join(dir, "bin")
          ENV["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end

      # `File::ALT_SEPARATOR` is nil on POSIX, so a candidate containing only
      # a backslash (no `File::SEPARATOR`) only counts as separator-bearing
      # -- and so is used as written rather than walked along PATH -- once
      # BOTH the platform and the constant agree it is a real separator.
      # Stub the constant so this arm is reachable under this suite's
      # stubbed `windows?` on any host, not only on a real Windows checkout.
      # The file lives flat in the sandbox: on a POSIX filesystem a
      # backslash is an ordinary filename character, not a path component,
      # so "bin\\dot.exe" both is the literal filename AND is the only
      # candidate string containing no `File::SEPARATOR`.
      it "treats a backslash as a separator once File::ALT_SEPARATOR is set" do
        in_sandbox do
          stub_const("File::ALT_SEPARATOR", "\\")
          candidate = "bin\\dot.exe"
          File.write(candidate, "")
          FileUtils.chmod(0o755, candidate)
          ENV["PATH"] = "/nonexistent-bin"
          ENV["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"

          expect(resolver.resolve([candidate])).to eq(candidate)
        end
      end

      # A PATHEXT entry missing its leading dot (e.g. "EXE" instead of
      # ".EXE") must still match, because `File.extname` always includes
      # the dot -- without normalisation `pathext.include?(".EXE")` would
      # be false for a "dot.exe" candidate and this would silently refuse
      # to fan out at all, on a real filesystem, for that entry.
      it "matches a PATHEXT entry that is missing its leading dot" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "bin", "dot.exe"))
          ENV["PATH"] = File.join(dir, "bin")
          ENV["PATHEXT"] = "COM;EXE;BAT;CMD"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end

      # `pathext_candidates` returns the raw array (no filesystem involved),
      # so this pins the case-fold property directly rather than through a
      # macOS/Windows filesystem that resolves both cases to the same file
      # regardless of what the code does.
      it "returns both extension cases from pathext_candidates" do
        candidates = resolver.send(:pathext_candidates, "dot")

        expect(candidates).to include("dot.EXE", "dot.exe")
      end

      # A stray/duplicate separator in PATHEXT (plausible from hand-edited
      # config) must not silently produce an empty-string extension: that
      # would make `File.extname("dot") == ""` match `pathext.include?("")`
      # and wrongly skip the fan-out for every extensionless candidate.
      it "still fans out a bare candidate when PATHEXT has a stray separator" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "bin", "dot.exe"))
          ENV["PATH"] = File.join(dir, "bin")
          ENV["PATHEXT"] = ".COM;.EXE;;.BAT"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end

      # A whitespace-only PATHEXT entry (e.g. from "   ;.EXE") must not
      # survive as a dotted blob of spaces (".   ") that can never match a
      # real filename, and must not silently swallow the fan-out either.
      it "drops a whitespace-only PATHEXT entry rather than dotting it" do
        ENV["PATHEXT"] = "   ;.EXE"

        expect(resolver.send(:pathext)).to eq([".EXE"])
      end

      it "does not find a bare candidate with no PATHEXT-listed extension present" do
        in_sandbox do |dir|
          FileUtils.mkdir_p(File.join(dir, "bin"))
          ENV["PATH"] = File.join(dir, "bin")
          ENV["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"

          expect(resolver.resolve(["dot"])).to be_nil
        end
      end

      it "uses an extensioned candidate as written, without PATHEXT fan-out" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "bin", "dot.exe"))
          ENV["PATH"] = File.join(dir, "bin")
          ENV["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"

          expect(resolver.resolve(["dot.exe"])).to eq("dot.exe")
        end
      end
    end

    context "off Windows (Gem.win_platform? stubbed false)" do
      before { allow(Gem).to receive(:win_platform?).and_return(false) }

      it "does not apply PATHEXT fan-out to a bare candidate" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "bin", "dot.exe"))
          ENV["PATH"] = File.join(dir, "bin")
          ENV["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"

          expect(resolver.resolve(["dot"])).to be_nil
        end
      end
    end

    describe "PATH entries starting with ~" do
      it "expands a bare ~ PATH entry against HOME" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "dot"))
          ENV["HOME"] = dir
          ENV["PATH"] = "~"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end

      it "expands a ~/subdir PATH entry against HOME" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "bin", "dot"))
          ENV["HOME"] = dir
          ENV["PATH"] = "~/bin"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end

      it "refuses a ~ PATH entry when HOME does not contain the candidate" do
        in_sandbox do |dir|
          ENV["HOME"] = dir
          ENV["PATH"] = "~/bin"

          expect(resolver.resolve(["dot"])).to be_nil
        end
      end

      # Puts `dot` directly at HOME's root (not under a subdirectory named
      # "someoneelse"), so a resolve HERE could only succeed by silently
      # expanding "~someoneelse" to $HOME -- the exact wrong guess this
      # method exists to avoid. A setup where `dot` sits under a real
      # "someoneelse" directory could not tell "left unexpanded" apart from
      # "wrongly expanded to HOME", since both would fail to resolve.
      it "leaves a ~user entry unexpanded rather than guessing" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "dot"))
          ENV["HOME"] = dir
          ENV["PATH"] = "~someoneelse"

          expect(resolver.resolve(["dot"])).to be_nil
        end
      end

      # `tilde_rest` itself, not through `resolve`: a `resolve`-level check
      # of "~user" can pass for the WRONG reason (a smashed, still-missing
      # path happens to resolve to nothing either way -- see the comment
      # above), so this pins the return value directly. `nil` is the "not a
      # `~`/`~/...` entry" signal `expand_tilde` relies on to skip
      # expansion entirely.
      it "returns nil from tilde_rest for a ~user entry, not the username" do
        expect(resolver.send(:tilde_rest, "~someoneelse")).to be_nil
      end

      it "returns the empty string from tilde_rest for a bare ~" do
        expect(resolver.send(:tilde_rest, "~")).to eq("")
      end

      # `home_directory` swallows only `Dir.home`'s ArgumentError (raised
      # when no home directory can be determined), turning it into `nil` so
      # `expand_tilde` falls back to leaving the field as written instead of
      # raising out of PATH resolution entirely.
      it "returns nil from home_directory when Dir.home has none to report" do
        allow(Dir).to receive(:home).and_raise(ArgumentError)

        expect(resolver.send(:home_directory)).to be_nil
      end

      # `tilde_expansion` must refuse to expand against a blank home rather
      # than building a path from nothing (`""` plus the rest), which would
      # look like a real, resolvable root-relative path.
      it "does not expand when home_directory reports an empty string" do
        allow(resolver).to receive(:home_directory).and_return("")

        expect(resolver.send(:tilde_expansion, "~/bin")).to be_nil
      end

      # A single-byte PATH entry that is not "~" must be walked as a literal
      # directory name, not treated as tilde-shaped. `field[1..]` on a
      # one-byte field is `""`, the same value a bare `~` produces, so this
      # is the case that distinguishes "starts with ~" from "empty rest".
      it "walks a single-character non-~ PATH entry literally" do
        in_sandbox do
          write_executable(File.join("x", "dot"))
          ENV["HOME"] = "/should-not-be-consulted"
          ENV["PATH"] = "x"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end
    end
  end

  describe "#render" do
    before do
      allow(wrapper).to receive(:available?).and_return(true)
      allow(File).to receive(:exist?).and_return(true)
      # Pin the binary. Left to `CommandResolver` this comes off the real
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

    # Every other example in this describe block stubs #system with no
    # argument matcher (or a matcher on one substring), so nothing ever
    # checks the FULL command build_command produces: which flags, in what
    # order, and what happens when no dpi: option is given at all. Mutant
    # found this -- default dpi=96, the -o flag, and the input file argument
    # all mutate freely with every spec here staying green. Pin the whole
    # array once instead of one substring at a time. Command is an array
    # (not a joined string) because #execute_command calls `system(*cmd)`
    # without a shell -- see "does not execute a shell metacharacter..."
    # below for why that matters.
    it "uses the default DPI and builds the exact command line" do
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
      captured_cmd = nil
      allow(wrapper).to receive(:system) do |*command|
        captured_cmd = command
        true
      end

      wrapper.render("input.dot", "output.png", :png)

      expect(captured_cmd).to eq(
        ["/usr/bin/dot", "-Kdot", "-Tpng", "-Gdpi=96", "-ooutput.png", "input.dot"],
      )
    end

    it "omits the -o flag when no output file is given" do
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
      captured_cmd = nil
      allow(wrapper).to receive(:system) do |*command|
        captured_cmd = command
        true
      end

      wrapper.render("input.dot", nil, :png)

      expect(captured_cmd).to eq(
        ["/usr/bin/dot", "-Kdot", "-Tpng", "-Gdpi=96", "input.dot"],
      )
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

    # Both format examples pass a Symbol, which is already what
    # SUPPORTED_FORMATS holds, so `format.to_sym` is a no-op for them and
    # mutating it away to bare `format` stays invisible. A String format
    # tells them apart -- callers of this public method may reasonably pass
    # either.
    it "accepts a format given as a string by converting it with to_sym" do
      expect(wrapper).to receive(:system) do |*args|
        expect(args).to include("-Tpng")
        true
      end

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
                         /"-Tpng".*"-ooutput\.png".*"input\.dot"/)
    end

    # "uses specified engine" and "raises error for unsupported engine" both
    # pass a String, so `engine.to_s` can be swapped for `engine.to_str` or
    # for bare `engine` and every example stays green -- String responds to
    # all three identically. A Symbol tells them apart: it responds to
    # #to_s but not #to_str, and is never #== to the String elements
    # SUPPORTED_ENGINES actually holds.
    it "accepts an engine given as a symbol by converting it with to_s" do
      expect(wrapper).to receive(:system) do |*args|
        expect(args).to include("-Kdot")
        true
      end

      wrapper.render("input.dot", "output.png", :png, engine: :dot)
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

    # The one example above uses a single space and lowercase "version", so
    # `\s+` can shrink to `\s` and the `i` flag can be dropped without
    # anything noticing. Pinning the exact dot_path in the #popen expectation
    # above already proves #version shells out to the wrapper's own
    # @dot_path, not a stale reference.
    it "matches one-or-more whitespace characters, case-insensitively" do
      allow(wrapper).to receive(:available?).and_return(true)
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
      allow(IO).to receive(:popen).and_return("dot - graphviz VERSION  2.44.1 (2020)")

      expect(wrapper.version).to eq("2.44.1")
    end

    it "returns nil, rather than raising, when the output has no version to parse" do
      allow(wrapper).to receive(:available?).and_return(true)
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
      allow(IO).to receive(:popen).and_return("dot: command not found")

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
