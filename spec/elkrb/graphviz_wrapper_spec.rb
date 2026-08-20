# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "support/fake_dot"
require_relative "../../lib/elkrb/graphviz_wrapper"

RSpec.describe Elkrb::GraphvizWrapper do
  include FakeDot

  let(:wrapper) { described_class.new }

  def with_path_only(dir)
    original_path = ENV.fetch("PATH", nil)
    original_elkrb_dot = ENV.fetch("ELKRB_DOT", nil)
    ENV["PATH"] = dir
    ENV.delete("ELKRB_DOT")
    yield
  ensure
    ENV["PATH"] = original_path
    ENV["ELKRB_DOT"] = original_elkrb_dot
  end

  def with_empty_path
    Dir.mktmpdir("empty_path") { |dir| with_path_only(dir) { yield } }
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

  describe "#available?" do
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

    it "does not treat an executable directory named dot as the executable" do
      Dir.mktmpdir do |dir|
        dot_dir = File.join(dir, "dot")
        FileUtils.mkdir_p(dot_dir)
        FileUtils.chmod(0o755, dot_dir)

        with_path_only(dir) do
          expect(described_class.new.available?).to be false
        end
      end
    end
  end

  describe "#render" do
    it "runs Graphviz via argv, with no shell involved" do
      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)
          output = File.join(dir, "output.png")

          wrapper.render(input, output, :png)

          expect(logged_argv(log_path)).to eq(
            ["-Kdot", "-Tpng", "-Gdpi=96", "-o", output, input]
          )
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
      with_fake_dot do |log_path|
        Dir.mktmpdir do |dir|
          input = write_fake_input(dir)
          malicious_output = File.join(dir, "a;touch PWNED;.png")

          # Confines any accidental shell execution to `dir`, which
          # Dir.mktmpdir cleans up regardless — under the vulnerable
          # string-form implementation "touch PWNED" would otherwise run
          # with the process's real cwd, not `dir`.
          Dir.chdir(dir) do
            wrapper.render(input, malicious_output, :png)
          end

          expect(logged_argv(log_path)).to include(malicious_output)
          expect(File.exist?(File.join(dir, "PWNED"))).to be(false)
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

  describe "#version" do
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
end
