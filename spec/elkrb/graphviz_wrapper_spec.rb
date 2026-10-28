# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "pathname"
require "tmpdir"
require "support/fake_dot"
require_relative "../../lib/elkrb/graphviz_wrapper"

RSpec.describe Elkrb::GraphvizWrapper do
  include FakeDot

  let(:wrapper) { described_class.new }

  if Gem.win_platform?
    windows_skip_reason = "these examples install a shebang script, which " \
                          "Windows will not execute from PATH"
  end

  # The fallback locations are absolute paths on the real machine, so an
  # example that means "PATH holds only this dir" has to blank them too, or
  # it turns on whether the developer happens to have Homebrew's Graphviz.
  # Stubs CANDIDATES rather than a separate fallback constant: the merged
  # implementation folds "dot" (PATH-walked) and the absolute fallback
  # locations into that one array, with no other stubbable seam.
  def with_path_only(dir, fallbacks: [])
    stub_const("#{described_class}::CANDIDATES", ["dot", *fallbacks].freeze)
    original_path = ENV.fetch("PATH", nil)
    original_elkrb_dot = ENV.fetch("ELKRB_DOT", nil)
    ENV["PATH"] = dir
    ENV.delete("ELKRB_DOT")
    yield
  ensure
    ENV["PATH"] = original_path
    ENV["ELKRB_DOT"] = original_elkrb_dot
  end

  def with_empty_path(fallbacks: [], &)
    Dir.mktmpdir("empty_path") do |dir|
      with_path_only(dir, fallbacks: fallbacks, &)
    end
  end

  def write_fake_dot(dir, body)
    path = File.join(dir, "dot")
    File.write(path, "#!/bin/sh\n#{body}\n")
    FileUtils.chmod(0o755, path)
    path
  end

  def fake_dot_executable(log_path)
    File.join(File.dirname(log_path), "dot")
  end

  def logged_argv(log_path)
    File.readlines(log_path).first.chomp.split("\0")
  end

  def write_fake_input(dir)
    input = File.join(dir, "input.dot")
    File.write(input, "digraph{a->b}")
    input
  end

  # Builds `dir/work/link -> ../real`, and returns `dir/work`. From there
  # the OS reads "link/../x" as `dir/x`, because it follows the link before
  # it applies the "..". A lexical collapse names `dir/work/x` instead, so
  # the two disagree about which file is meant.
  # @return [String] the working directory the caller must chdir into
  def with_updir_symlink(dir)
    work = File.join(dir, "work")
    FileUtils.mkdir_p([work, File.join(dir, "real")])
    File.symlink("../real", File.join(work, "link"))
    work
  end

  # Every example in this group installs a real, executable shebang script
  # somewhere on PATH or at an absolute location -- CommandResolver's own
  # PATHEXT fan-out means a bare extensionless "dot" is never found on
  # Windows regardless of execute bits, so the whole group is unreachable
  # there rather than merely unable to run what it finds.
  describe "#available?", skip: windows_skip_reason do
    it "returns true when dot is on PATH" do
      with_fake_dot do
        expect(described_class.new.available?).to be true
      end
    end

    it "returns false when dot is nowhere on PATH" do
      with_empty_path do
        expect(described_class.new.available?).to be false
      end
    end

    it "returns true when ELKRB_DOT points at an executable, overriding whatever else is on PATH" do
      with_fake_dot do |log_path|
        Dir.mktmpdir("decoy_dot") do |decoy_dir|
          decoy_dot = File.join(decoy_dir, "dot")
          File.write(decoy_dot, "#!/bin/sh\necho 'dot - graphviz version 9.9.9 (decoy)'\n")
          FileUtils.chmod(0o755, decoy_dot)

          original_path = ENV.fetch("PATH", nil)
          # The decoy goes first on PATH: if ELKRB_DOT were ignored, a
          # plain PATH scan would find the decoy (9.9.9) before the real
          # fake (2.44.1), so the version assertion below would catch it.
          ENV["PATH"] = [decoy_dir, original_path].compact.join(File::PATH_SEPARATOR)
          begin
            ENV["ELKRB_DOT"] = fake_dot_executable(log_path)
            wrapper = described_class.new

            expect(wrapper.available?).to be true
            expect(wrapper.version).to eq("2.44.1")
          ensure
            ENV["PATH"] = original_path
          end
        end
      end
    end

    it "does not fall back to PATH when ELKRB_DOT is set but invalid" do
      with_fake_dot do
        ENV["ELKRB_DOT"] = "/nonexistent/path/to/dot"
        expect(described_class.new.available?).to be false
      end
    end

    it "treats an empty ELKRB_DOT as unset and falls back to PATH" do
      with_fake_dot do
        ENV["ELKRB_DOT"] = ""
        expect(described_class.new.available?).to be true
      end
    end

    it "runs the ELKRB_DOT it validated when the override names no directory" do
      with_fake_dot do
        Dir.mktmpdir("cwd_dot") do |dir|
          # A bare name is what File.file? resolves against the working
          # directory but what the OS resolves through PATH, so before the
          # anchor the wrapper validated this script and ran the one on PATH
          # (2.44.1) instead.
          write_fake_dot(dir, "echo 'dot - graphviz version 9.9.9'")

          Dir.chdir(dir) do
            ENV["ELKRB_DOT"] = "dot"
            wrapper = described_class.new

            expect(wrapper.available?).to be true
            expect(wrapper.version).to eq("9.9.9")
          end
        end
      end
    end

    it "runs the ELKRB_DOT the OS reaches when the override crosses a symlink" do
      with_fake_dot do
        Dir.mktmpdir("symlinked_dot") do |dir|
          write_fake_dot(dir, "echo 'dot - graphviz version 9.9.9'")
          work = with_updir_symlink(dir)

          Dir.chdir(work) do
            ENV["ELKRB_DOT"] = File.join("link", "..", "dot")
            wrapper = described_class.new

            expect(wrapper.available?).to be true
            expect(wrapper.version).to eq("9.9.9")
          end
        end
      end
    end

    it "finds dot in a fallback location when PATH holds none" do
      Dir.mktmpdir do |dir|
        fallback = write_fake_dot(dir, "exit 0")

        with_empty_path(fallbacks: [fallback]) do
          expect(described_class.new.available?).to be true
        end
      end
    end

    it "prefers a dot on PATH over one in a fallback location" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          fallback = write_fake_dot(dir, "echo 'dot - graphviz version 9.9.9'")
          stub_const("#{described_class}::CANDIDATES", ["dot", fallback].freeze)

          expect(described_class.new.version).to eq("2.44.1")
        end
      end
    end

    # `available?` must agree with the command `render` actually runs. Ruby
    # execs the string `build_command` builds and searches PATH for it, while
    # `File.executable?("dot")` answers about the working directory, so the
    # two can disagree.
    #
    # CANDIDATES is stubbed throughout because this machine may have a real
    # Graphviz at one of the absolute candidates, which would answer an
    # example for reasons the example did not set up.
    context "the CANDIDATES list, walking PATH" do
      # Every example below sets ENV["PATH"] directly (an empty string, a
      # nonexistent directory, a deleted key) with no restore of its own --
      # measured: without this hook, one example's broken PATH survives it
      # and corrupts every later example in the whole file, in or out of
      # this context, depending on random order.
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

      # Writes whatever `-o` names, so a successful render is observable
      # rather than merely unraised, and the content identifies which fake
      # ran. `build_command` emits `-o` and the path as two separate argv
      # elements, never `-opath` -- matching only the suffix form here made
      # every real render silently write to a file named "" (the empty
      # string left after stripping "-o" off the bare "-o" token), which
      # `render_outcome` reported as :ran_without_output.
      def install_dot(path, tag = "dot")
        script = 'prev=""; for a in "$@"; do case "$prev" in -o) echo TAG > "$a";; ' \
                 'esac; prev="$a"; done; exit 0'
        File.write(path, "#!/bin/sh\n#{script.sub('TAG', tag)}\n")
        FileUtils.chmod(0o755, path)
      end

      # The pair asserted by every example. On the false arm the second
      # element is measured INDEPENDENTLY of `available?`: `render` raises
      # the installation message before any validation, so a `:refused`
      # outcome is entailed by `available? == false` and would assert
      # nothing on its own.
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

      # A PATH entry need not be valid UTF-8; exec walks past a malformed
      # entry rather than dying. Pin the encoding `ENV.fetch("PATH", "")`
      # returns (rather than inheriting the ambient locale) so this means
      # the same thing everywhere, and keep the `have_received` assertion --
      # it is what proves the pinned string is the one production code
      # reads, not the real `ENV["PATH"]`. Build `raw` from bytes, not
      # interpolation, so a non-ASCII TMPDIR under a US-ASCII locale cannot
      # raise Encoding::CompatibilityError.
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

      # An unset PATH sends exec to libruby's own default search, which ENDS
      # in the working directory rather than starting there. Two
      # consequences, and both are load-bearing here. The tag is pinned,
      # because otherwise a host carrying a dot in any directory ahead of
      # the working one answers the bare name and `verdict` alone stays
      # green with the wrong binary. And the candidate's name is
      # deliberately unusual, for that same reason.
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
      # test is `include?(File::SEPARATOR)`, which "abs/dot" satisfies, and
      # a relative candidate cannot inherit a space from TMPDIR the way an
      # absolute one built from the sandbox does -- `build_command` passes
      # argv to `system(*argv)` without a shell, so a spaced `@dot_path`
      # would only matter if a joined string were built, which it is not.
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

      # The inverted mirror of the example above, and the same candidate
      # shape production ships: a bare "dot" first, a path-bearing one
      # after it. Here the bare one cannot resolve, so the SECOND must be
      # what runs.
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

    def write_dot(directory)
      name = Gem.win_platform? ? "dot.exe" : "dot"
      ENV["PATHEXT"] = ".EXE" if Gem.win_platform?
      write_executable(File.join(directory, name))
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

      # #resolved_path exists so `File.realpath` never sees a bare name --
      # returning the extensionless "dot" here (the one candidate guaranteed
      # NOT to exist on disk) would make `realpath` resolve against the cwd
      # exactly as a bare name does, defeating the whole point of this
      # method. It must return the actual matched candidate, "dot.exe".
      # Written with the exact case `pathext_candidates` tries first
      # (uppercase, matching PATHEXT's own casing) so the assertion holds on
      # a case-insensitive filesystem too, where "dot.exe" would equally
      # satisfy a lookup for "dot.EXE".
      it "resolves a bare PATHEXT match to the matched candidate, not the " \
         "extensionless name" do
        in_sandbox do |dir|
          write_executable(File.join(dir, "bin", "dot.EXE"))
          ENV["PATH"] = File.join(dir, "bin")
          ENV["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"

          expect(resolver.resolved_path("dot"))
            .to eq(File.join(dir, "bin", "dot.EXE"))
        end
      end

      # The separator-form branch (`return matched_candidate(path) if
      # separator_form?(path)`) never walks PATH at all, so this takes a
      # different route through `resolved_path` than the bare-name example
      # above: the candidate itself carries a separator (`bin/dot`), PATH is
      # pointed at a directory with nothing in it, and the only match
      # possible is the PATHEXT fan-out applied to the given path itself.
      # Reverting the branch to `return path if separator_form?(path)` would
      # hand back the extensionless "bin/dot" here -- the one candidate
      # guaranteed not to exist on disk -- so this pins the matched
      # candidate, not just a truthy return.
      it "resolves a separator-bearing path to its matched PATHEXT " \
         "candidate" do
        in_sandbox do
          write_executable("bin/dot.EXE")
          ENV["PATH"] = "/nonexistent-bin"
          ENV["PATHEXT"] = ".COM;.EXE;.BAT;.CMD"

          expect(resolver.resolved_path("bin/dot")).to eq("bin/dot.EXE")
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
          FileUtils.mkdir_p("bin")
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
          write_dot(dir)
          allow(Dir).to receive(:home).and_return(dir)
          ENV["HOME"] = dir
          ENV["PATH"] = "~"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end

      it "expands a ~/subdir PATH entry against HOME" do
        in_sandbox do |dir|
          write_dot(File.join(dir, "bin"))
          allow(Dir).to receive(:home).and_return(dir)
          ENV["HOME"] = dir
          ENV["PATH"] = "~/bin"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end

      it "refuses a ~ PATH entry when HOME does not contain the candidate" do
        in_sandbox do |dir|
          allow(Dir).to receive(:home).and_return(dir)
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
          write_dot(dir)
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
          write_dot("x")
          ENV["HOME"] = "/should-not-be-consulted"
          ENV["PATH"] = "x"

          expect(resolver.resolve(["dot"])).to eq("dot")
        end
      end
    end
  end

  describe "#render", skip: windows_skip_reason do
    it "runs Graphviz via argv, with no shell involved" do
      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)
          output = File.join(dir, "output.png")

          wrapper.render(input, output, :png)

          argv = logged_argv(log_path)
          expect(argv.values_at(0, 1, 2, 3, 5)).to eq(
            ["-Kdot", "-Tpng", "-Gdpi=96", "-o", input],
          )
          expect(File.dirname(argv[4])).to eq(dir)
          expect(File.read(output)).to eq("rendered")
        end
      end
    end

    it "passes the requested engine" do
      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)
          output = File.join(dir, "output.png")

          wrapper.render(input, output, :png, engine: "neato")

          expect(logged_argv(log_path)).to include("-Kneato")
        end
      end
    end

    it "passes the requested DPI" do
      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)
          output = File.join(dir, "output.png")

          wrapper.render(input, output, :png, dpi: 150)

          expect(logged_argv(log_path)).to include("-Gdpi=150")
        end
      end
    end

    it "never lets shell metacharacters in the output path execute" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)
          # Escapes naive per-argument quoting. A bare `a;touch PWNED;`
          # does not, and stays green against a shell-string build.
          malicious_output = File.join(dir, "a'; touch PWNED; echo '.png")

          # Confines any accidental shell execution to `dir`, which
          # Dir.mktmpdir cleans up regardless — under the vulnerable
          # string-form implementation "touch PWNED" would otherwise run
          # with the process's real cwd, not `dir`.
          Dir.chdir(dir) do
            wrapper.render(input, malicious_output, :png)
          end

          expect(File.read(malicious_output)).to eq("rendered")
          expect(File.exist?(File.join(dir, "PWNED"))).to be(false)
        end
      end
    end

    it "hands dot an input path that cannot be read as an option" do
      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          dash_input = File.join(dir, "-V")
          File.write(dash_input, "digraph{a->b}")
          output = File.join(dir, "output.png")

          Dir.chdir(dir) { wrapper.render("-V", output, :png) }

          # Real graphviz reads a bare "-V" as the version flag: it prints
          # the banner, exits 0 and writes nothing, so the CLI reported a
          # render that never happened.
          argv = logged_argv(log_path)
          expect(argv.last).not_to start_with("-")
          expect(File.identical?(argv.last, dash_input)).to be true
        end
      end
    end

    it "hands dot an output path that cannot be read as an option" do
      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)
          dash_output = File.join(dir, "-Tsvg.png")

          Dir.chdir(dir) { wrapper.render(input, "-Tsvg.png", :png) }

          argv = logged_argv(log_path)
          expect(argv[argv.index("-o") + 1]).not_to start_with("-")
          # The line above is what discriminates. This one only shows the
          # anchored name is still writable: the fake dot touches whatever
          # follows -o unconditionally, where real graphviz given "-o
          # -Tsvg.png" writes nothing at all -- it either rejects the
          # missing argument or swallows the name as another flag.
          expect(File.exist?(dash_output)).to be true
        end
      end
    end

    it "hands dot the input path the OS reaches across a symlink" do
      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          work = with_updir_symlink(dir)
          target = File.join(dir, "graph.dot")
          File.write(target, "digraph{a->b}")
          File.write(File.join(work, "graph.dot"), "digraph{decoy}")

          Dir.chdir(work) do
            wrapper.render(File.join("link", "..", "graph.dot"),
                           "output.png", :png)

            expect(File.identical?(logged_argv(log_path).last, target))
              .to be true
          end
        end
      end
    end

    it "hands dot the output path the OS reaches across a symlink" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          work = with_updir_symlink(dir)
          input = write_fake_input(work)

          Dir.chdir(work) do
            wrapper.render(input, File.join("link", "..", "out.png"), :png)
          end

          expect(File.exist?(File.join(dir, "out.png"))).to be true
          expect(File.exist?(File.join(work, "out.png"))).to be false
        end
      end
    end

    it "raises error when Graphviz is not available" do
      with_empty_path do
        expect do
          described_class.new.render("input.dot", "output.png", :png)
        end.to raise_error(Elkrb::GraphvizWrapper::GraphvizNotFoundError,
                           /Graphviz is required/)
      end
    end

    it "raises error for unsupported format" do
      with_fake_dot do
        expect do
          wrapper.render("input.dot", "output.xyz", :xyz)
        end.to raise_error(ArgumentError, /Unsupported format/)
      end
    end

    it "raises error for unsupported engine" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)

          expect do
            wrapper.render(input, File.join(dir, "output.png"), :png, engine: "invalid")
          end.to raise_error(ArgumentError, /Unsupported engine/)
        end
      end
    end

    it "raises error when input file does not exist" do
      with_fake_dot do
        expect do
          wrapper.render("missing.dot", "output.png", :png)
        end.to raise_error(ArgumentError, /Input file not found/)
      end
    end

    it "names the exact missing file in the error message" do
      with_fake_dot do
        expect do
          wrapper.render("missing.dot", "output.png", :png)
        end.to raise_error(ArgumentError, "Input file not found: missing.dot")
      end
    end

    it "rejects a directory as input instead of reporting a render" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          # File.exist? is true for a directory, and real graphviz handed
          # one exits 0 having written nothing -- so the CLI printed
          # "Rendered" and left no output file behind.
          input_dir = File.join(dir, "adir")
          FileUtils.mkdir_p(input_dir)

          expect do
            wrapper.render(input_dir, File.join(dir, "out.png"), :png)
          end.to raise_error(ArgumentError, /Input file not found/)
        end
      end
    end

    it "raises a clear error instead of crashing when output_file is nil" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)

          expect do
            wrapper.render(input, nil, :png)
          end.to raise_error(ArgumentError, /Output file path is required/)
        end
      end
    end

    # An empty path reaches `dot` as a bare `-o`, which makes it dump its
    # usage banner and fail as GraphvizNotFoundError -- naming a Graphviz
    # that is installed and working. Refused up front instead.
    it "refuses an empty output path with the same error as a nil one" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)

          expect do
            wrapper.render(input, "", :png)
          end.to raise_error(ArgumentError, /Output file path is required/)
        end
      end
    end

    # The other side of that boundary, and the reason `strip` is wrong in
    # validate_output_file!: three spaces is a legal POSIX filename, so it
    # must still render. Keep this -- it is what fails if anyone widens
    # the empty check to a blank one.
    #
    # The path must be RELATIVE and wholly whitespace for that to hold. An
    # absolute File.join(dir, "   ") does not strip to empty, so it sails
    # through a `.strip.empty?` guard and this example would pass against
    # the wrong fix it exists to refuse. Verified: with `.strip.empty?` in
    # place, the absolute form stayed green and this form goes red.
    it "still renders to a path that is only whitespace" do
      with_fake_dot do
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)

          Dir.chdir(dir) do
            wrapper.render(input, "   ", :png)

            expect(File.exist?("   ")).to be(true)
          end
        end
      end
    end

    it "raises error when the render command itself fails, with no system stub" do
      Dir.mktmpdir do |dir|
        failing_dot = File.join(dir, "dot")
        File.write(failing_dot, "#!/bin/sh\nexit 1\n")
        FileUtils.chmod(0o755, failing_dot)
        input = write_fake_input(dir)

        with_path_only(dir) do
          expect do
            described_class.new.render(input, File.join(dir, "output.png"), :png)
          end.to raise_error(Elkrb::GraphvizWrapper::GraphvizNotFoundError, /command failed/)
        end
      end
    end
  end

  # Everything above needs a real, executable `dot` to install on PATH, so
  # the whole group is skipped on Windows. These examples pin the same
  # argv-construction properties without ever executing anything, by
  # stubbing #system directly, so they run -- and can fail -- on every
  # platform including Windows.
  describe "#render argv construction (no real binary required)" do
    before { wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot") }

    let(:successful_system_call) do
      lambda do |*command|
        output = command.fetch(command.index("-o") + 1)
        File.binwrite(output, "rendered")
        true
      end
    end

    # `system(*argv)` falls back to SHELL semantics when argv has exactly one
    # element, so the whole no-shell guarantee rests on this argv being long.
    # This is the assertion that CARRIES the shell-metacharacter property on
    # every platform, because it cannot skip and needs no binary: a
    # metacharacter stays one argv element. "never lets shell metacharacters
    # in the output path execute" above is a supplement that proves nothing
    # actually runs, and it is unavailable on Windows.
    it "keeps the caller's shell metacharacter out of the process argv" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        malicious_output = File.join(dir, "out.png; touch PWNED")

        expect(wrapper).to receive(:system) do |*command|
          expect(command.size).to be > 1
          output = command.fetch(command.index("-o") + 1)
          expect(File.dirname(output)).to eq(dir)
          expect(output).not_to eq(malicious_output)
          expect(command).to all(be_a(String))
          successful_system_call.call(*command)
        end

        wrapper.render(input, malicious_output, :png)
        expect(File.read(malicious_output)).to eq("rendered")
      end
    end

    # No example anywhere in this file checks #render's own return value --
    # every other success case reads the log a fake dot wrote instead.
    # Mutant found this: #execute_command's `success` result can be
    # replaced with nil, or dropped entirely, with the whole suite staying
    # green.
    it "returns the underlying system call's success value" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        allow(wrapper).to receive(:system, &successful_system_call)

        expect(wrapper.render(input, File.join(dir, "output.png"), :png)).to be true
      end
    end

    # Both format examples pass a Symbol, which is already what
    # SUPPORTED_FORMATS holds, so `format.to_sym` is a no-op for them and
    # mutating it away to bare `format` stays invisible. A String format
    # tells them apart -- callers of this public method may reasonably pass
    # either.
    it "accepts a format given as a string by converting it with to_sym" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        expect(wrapper).to receive(:system) do |*command|
          expect(command).to include("-Tpng")
          successful_system_call.call(*command)
        end

        wrapper.render(input, File.join(dir, "output.png"), "png")
      end
    end

    # "accepts a format..." above and "raises error for unsupported engine"
    # in the group above both pass a String, so `engine.to_s` can be
    # swapped for `engine.to_str` or for bare `engine` and every example
    # stays green -- String responds to all three identically. A Symbol
    # tells them apart: it responds to #to_s but not #to_str, and is never
    # #== to the String elements SUPPORTED_ENGINES actually holds.
    it "accepts an engine given as a symbol by converting it with to_s" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        expect(wrapper).to receive(:system) do |*command|
          expect(command).to include("-Kdot")
          successful_system_call.call(*command)
        end

        wrapper.render(input, File.join(dir, "output.png"), :png, engine: :dot)
      end
    end

    it "coerces a Pathname input file to a String" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        expect(wrapper).to receive(:system) do |*command|
          expect(command).to include(input)
          expect(command).to all(be_a(String))
          successful_system_call.call(*command)
        end

        wrapper.render(Pathname.new(input), File.join(dir, "output.png"), :png)
      end
    end

    # The reachable input set for this coercion is exactly what
    # `validate_file_exists!` lets through -- a String, or an object with
    # `#to_path`. A `#to_s`-only object cannot get here at all: `File.file?`
    # raises TypeError on it first. So `#to_path` is the case that
    # generalises past Pathname, and it is the one `#to_s` would silently
    # get wrong.
    it "coerces a non-Pathname to_path object to its real path" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        custom_path = Object.new
        custom_path.define_singleton_method(:to_path) { input }

        expect(wrapper).to receive(:system) do |*command|
          expect(command).to include(input)
          expect(command).to all(be_a(String))
          successful_system_call.call(*command)
        end

        wrapper.render(custom_path, File.join(dir, "output.png"), :png)
      end
    end

    # Same reachable set as the input path. Uncoerced, dot was handed
    # "#<Object:0x...>" as the -o value, wrote a file by that name, and
    # reported success.
    it "coerces a to_path output file to its real path" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        output_path = File.join(dir, "output.png")
        custom_path = Object.new
        custom_path.define_singleton_method(:to_path) { output_path }

        expect(wrapper).to receive(:system) do |*command|
          staged = command.fetch(command.index("-o") + 1)
          expect(File.dirname(staged)).to eq(dir)
          expect(command).to all(be_a(String))
          successful_system_call.call(*command)
        end

        wrapper.render(input, custom_path, :png)
        expect(File.read(output_path)).to eq("rendered")
      end
    end

    it "preserves an existing output when Graphviz writes partially then fails" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        output = File.join(dir, "output.png")
        File.write(output, "original")
        allow(wrapper).to receive(:system) do |*command|
          scratch = command.fetch(command.index("-o") + 1)
          File.binwrite(scratch, "partial")
          false
        end

        expect { wrapper.render(input, output, :png) }
          .to raise_error(described_class::GraphvizNotFoundError,
                          /command failed/)
        expect(File.read(output)).to eq("original")
        expect(Dir.children(dir)).to contain_exactly("input.dot", "output.png")
      end
    end

    it "preserves an existing output when Graphviz produces no bytes" do
      Dir.mktmpdir do |dir|
        input = write_fake_input(dir)
        output = File.join(dir, "output.png")
        File.write(output, "original")
        allow(wrapper).to receive(:system).and_return(true)

        expect { wrapper.render(input, output, :png) }
          .to raise_error(Elkrb::Error, /produced no output/)
        expect(File.read(output)).to eq("original")
        expect(Dir.children(dir)).to contain_exactly("input.dot", "output.png")
      end
    end
  end

  describe "#version", skip: windows_skip_reason do
    it "parses the version dot -V prints" do
      with_fake_dot do |log_path|
        expect(described_class.new.version).to eq("2.44.1")
        expect(logged_argv(log_path)).to eq(["-V"])
      end
    end

    it "returns nil when Graphviz is not available" do
      with_empty_path do
        expect(described_class.new.version).to be_nil
      end
    end

    # Copilot, PR #13 round at 30a06db: `available?` only proves @dot_path
    # resolved at CONSTRUCTION time. Deleting the binary afterward makes the
    # real Open3.capture2e raise Errno::ENOENT instead of honoring this
    # describe block's own "nil when not available" contract.
    it "returns nil, not a raise, when the binary disappears after construction" do
      with_fake_dot do |log_path|
        # ELKRB_DOT, not the bare "dot" a plain PATH hit leaves in @dot_path:
        # a bare name can't be realpath'd from an arbitrary cwd, so
        # find_graphviz keeps it unresolved and Open3 re-walks PATH on every
        # call -- on a machine with a real `dot` installed, deleting only
        # this fake binary would silently fall through to the real one
        # instead of proving the ENOENT rescue.
        ENV["ELKRB_DOT"] = fake_dot_executable(log_path)
        wrapper = described_class.new
        File.delete(fake_dot_executable(log_path))

        expect(wrapper.version).to be_nil
      end
    end

    it "runs dot via Open3, not a shell string (a path containing a space works)" do
      with_fake_dot do |log_path|
        spaced_dir = File.join(File.dirname(log_path), "with space")
        FileUtils.mkdir_p(spaced_dir)
        spaced_dot = File.join(spaced_dir, "dot")
        FileUtils.cp(fake_dot_executable(log_path), spaced_dot)
        FileUtils.chmod(0o755, spaced_dot)

        ENV["ELKRB_DOT"] = spaced_dot
        # Old `` `#{@dot_path} -V 2>&1` `` interpolation would split this
        # path on the space and fail to find `dot` at all; Open3.capture2e
        # passes it as one argv element and succeeds.
        expect(described_class.new.version).to eq("2.44.1")
      end
    end
  end

  # The regex #version parses the binary's output with, pinned without a
  # real dot -- so these run on every platform including Windows.
  describe "#version regex robustness (no real binary required)" do
    before do
      allow(wrapper).to receive(:available?).and_return(true)
      wrapper.instance_variable_set(:@dot_path, "/usr/bin/dot")
    end

    # The example above uses a single space and lowercase "version", so
    # `\s+` can shrink to `\s` and the `i` flag can be dropped without
    # anything noticing.
    it "matches one-or-more whitespace characters, case-insensitively" do
      allow(Open3).to receive(:capture2e)
        .and_return(["dot - graphviz VERSION  2.44.1 (2020)", instance_double(Process::Status)])

      expect(wrapper.version).to eq("2.44.1")
    end

    it "returns nil, rather than raising, when the output has no version to parse" do
      allow(Open3).to receive(:capture2e)
        .and_return(["dot: command not found", instance_double(Process::Status)])

      expect(wrapper.version).to be_nil
    end
  end

  describe "#supported_formats" do
    it "returns list of supported formats" do
      expect(wrapper.supported_formats).to include(:png, :svg, :pdf, :ps, :eps)
    end
  end

  describe "#supported_engines" do
    it "returns list of supported engines" do
      expect(wrapper.supported_engines).to include(
        "dot", "neato", "fdp", "sfdp", "twopi", "circo"
      )
    end
  end

  describe "error messages" do
    it "provides helpful installation instructions" do
      with_empty_path do
        expect do
          described_class.new.render("input.dot", "output.png", :png)
        end.to raise_error(Elkrb::GraphvizWrapper::GraphvizNotFoundError) do |e|
          expect(e.message).to include("brew install graphviz")
          expect(e.message).to include("apt-get install graphviz")
          expect(e.message).to include("elkrb diagram")
          expect(e.message).to include("ELKRB_DOT")
        end
      end
    end
  end

  describe "the executable it settles on", skip: windows_skip_reason do
    # A relative candidate -- a directory-bearing ELKRB_DOT like "bin/dot", or
    # an entry built from a relative PATH component -- used to be recorded as
    # given. A later chdir then silently repointed it: measured, a wrapper
    # that validated "bin/dot" in one directory named a DIFFERENT binary of
    # the same relative name after moving to another. #available? and #render
    # disagreed about which program would run.
    it "records a path that survives a change of working directory" do
      Dir.mktmpdir do |tmp|
        %w[A B].each do |dir|
          FileUtils.mkdir_p(File.join(tmp, dir, "bin"))
          path = File.join(tmp, dir, "bin", "dot")
          File.write(path, "#!/bin/sh\necho #{dir}-DOT\n")
          FileUtils.chmod(0o755, path)
        end

        # I claimed a surrounding hook restored ELKRB_DOT. There is none, and
        # a focused run of this example left it set for every later example.
        # Restored here explicitly.
        previous = ENV.fetch("ELKRB_DOT", nil)
        found =
          begin
            ENV["ELKRB_DOT"] = "bin/dot"
            Dir.chdir(File.join(tmp, "A")) do
              described_class.new.send(:find_graphviz)
            end
          ensure
            if previous.nil?
              ENV.delete("ELKRB_DOT")
            else
              ENV["ELKRB_DOT"] = previous
            end
          end

        # Name the directory, not merely "it is absolute": an absolute path
        # pointing at B would satisfy a weaker assertion.
        expect(found).to eq(File.realpath(File.join(tmp, "A", "bin", "dot")))
      end
    end

    it "resolves a bare PATH match to its PATH directory, not the cwd" do
      # File.realpath("dot") resolves a bare name against the WORKING
      # DIRECTORY, not the PATH entry CommandResolver actually matched --
      # distinct bugs from the one above (that one is about chdir after
      # resolution; this one is about where the bare candidate itself
      # resolves to). Build a real PATH directory and chdir somewhere else
      # entirely so a cwd-relative resolution would both miss and prove the
      # bug by returning the un-anchored bare name itself.
      Dir.mktmpdir do |tmp|
        FileUtils.mkdir_p(File.join(tmp, "path_dir"))
        FileUtils.mkdir_p(File.join(tmp, "elsewhere"))
        dot_path = File.join(tmp, "path_dir", "dot")
        File.write(dot_path, "#!/bin/sh\necho DOT\n")
        FileUtils.chmod(0o755, dot_path)

        previous_path = ENV.fetch("PATH", nil)
        found =
          begin
            ENV["PATH"] = File.join(tmp, "path_dir")
            Dir.chdir(File.join(tmp, "elsewhere")) do
              described_class.new.send(:find_graphviz)
            end
          ensure
            ENV["PATH"] = previous_path
          end

        expect(found).to eq(File.realpath(dot_path))
      end
    end
  end
end
