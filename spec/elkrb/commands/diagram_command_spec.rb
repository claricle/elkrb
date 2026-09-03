# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require_relative "../../../lib/elkrb/commands/diagram_command"

RSpec.describe Elkrb::Commands::DiagramCommand do
  let(:temp_dir) { Dir.mktmpdir }
  let(:graph_data) do
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
    it "creates diagram from JSON file" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.dot")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "creates diagram from YAML file" do
      input_file = File.join(temp_dir, "graph.yml")
      output_file = File.join(temp_dir, "output.dot")

      File.write(input_file, graph_data.to_yaml)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "creates diagram from ELKT file" do
      input_file = File.join(temp_dir, "graph.elkt")
      output_file = File.join(temp_dir, "output.dot")

      elkt_content = <<~ELKT
        node n1
        node n2
        edge n1 -> n2
      ELKT

      File.write(input_file, elkt_content)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "applies layout algorithm" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      algorithm: "layered",
                                    })
      command.run

      result = JSON.parse(File.read(output_file))
      expect(result["children"]).to be_an(Array)
    end

    it "outputs to JSON format" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { JSON.parse(content) }.not_to raise_error
    end

    it "outputs to YAML format" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.yml")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "outputs to DOT format" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.dot")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("digraph")
    end

    it "outputs to ELKT format" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.elkt")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("node n1")
      expect(content).to include("edge")
    end

    it "creates output directory if needed" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "subdir", "output.dot")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "raises error for non-existent file" do
      output_file = File.join(temp_dir, "output.dot")

      command = described_class.new("nonexistent.json", { output: output_file })

      expect { command.run }.to raise_error(ArgumentError, /File not found/)
    end

    it "applies spacing option" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      spacing: 100,
                                    })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "applies direction option" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      direction: "DOWN",
                                    })
      command.run

      expect(File.exist?(output_file)).to be true
    end

    it "detects format from explicit option" do
      input_file = File.join(temp_dir, "graph.json")
      output_file = File.join(temp_dir, "output.txt")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, {
                                      output: output_file,
                                      format: "dot",
                                    })
      command.run

      content = File.read(output_file)
      expect(content).to include("digraph")
    end

    it "auto-detects JSON format from extension" do
      input_file = File.join(temp_dir, "input.elkt")
      output_file = File.join(temp_dir, "output.json")

      File.write(input_file, "node n1\nnode n2\nedge n1 -> n2")

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { JSON.parse(content) }.not_to raise_error
    end

    it "auto-detects YAML format from extension" do
      input_file = File.join(temp_dir, "input.json")
      output_file = File.join(temp_dir, "output.yaml")

      File.write(input_file, graph_data.to_json)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect { YAML.safe_load(content) }.not_to raise_error
    end

    it "loads a YAML file with no recognized extension" do
      input_file = File.join(temp_dir, "graph.noext")
      output_file = File.join(temp_dir, "output.dot")
      File.write(input_file, graph_data.to_yaml)

      command = described_class.new(input_file, { output: output_file })
      command.run

      content = File.read(output_file)
      expect(content).to include("n1")
      expect(content).to include("n2")
    end

    it "raises for unparsable content with no recognized extension" do
      input_file = File.join(temp_dir, "graph.noext")
      output_file = File.join(temp_dir, "output.dot")
      File.write(input_file, "this is not a graph, just garbage!!! {{{ ]]] ###")

      command = described_class.new(input_file, { output: output_file })

      expect { command.run }.to raise_error(ArgumentError,
                                            /Unable to parse input file/)
    end
  end
  describe "when staging the DOT fails" do
    # I claimed this was covered and it was not. The existing cleanup
    # examples all run AFTER a successful staging write, so none of them
    # exercised the path where staging itself raises.
    #
    # The image path must never hold DOT. It used to: the DOT was written
    # under `out.svg` and read back, so any failure between those points left
    # a `.svg` beginning `digraph G{`. Cleanup could not be relied on to undo
    # that either -- `FileUtils.rm_f` swallows an unlink failure.
    let(:input_file) do
      File.join(temp_dir, "graph.json").tap do |path|
        File.write(path, graph_data.to_json)
      end
    end
    let(:output_file) { File.join(temp_dir, "out.svg") }

    # Staging is forced to fail by making the DESTINATION unwritable, so the
    # scratch directory cannot be created. The older mechanism -- occupying
    # `out.svg.tmp.dot` -- stopped working once scratch names became
    # unguessable, which is the point.
    #
    # The input file is written BEFORE the lock. Creating it lazily inside
    # the example failed at that write instead of at staging, so the examples
    # passed without the command running at all -- measured, replacing the
    # constructor with an inert object still gave 2 examples, 0 failures.
    before do
      input_file
      FileUtils.chmod(0o500, temp_dir)
    end

    after { FileUtils.chmod(0o700, temp_dir) }

    it "actually reaches the command" do
      # Guards the guard. These examples once passed with the command never
      # running at all: the input file was created lazily inside the example
      # and its write failed first, under the locked directory. If that comes
      # back, this example fails while the others still pass.
      expect(File.exist?(input_file)).to be(true)
      expect { described_class.new(input_file, { output: output_file }).run }
        .to raise_error(StandardError, /Permission denied|Errno::EACCES/)
    end

    it "leaves no image file behind" do
      expect do
        described_class.new(input_file, { output: output_file }).run
      end.to raise_error(StandardError)

      expect(File.exist?(output_file)).to be(false)
    end

    it "refuses a renderer that succeeds without producing an image" do
      # Found by review: the scratch file used to be pre-created to reserve
      # its name, so a renderer exiting 0 without writing left an untouched
      # empty file -- which was then renamed over the caller's content. Data
      # loss, and an invalid image wearing the requested name.
      FileUtils.chmod(0o700, temp_dir)
      File.write(output_file, "ORIGINAL")

      previous = ENV.fetch("ELKRB_DOT", nil)
      begin
        ENV["ELKRB_DOT"] = "/usr/bin/true"
        expect do
          described_class.new(input_file, { output: output_file }).run
        end.to raise_error(StandardError, /produced no image/)
      ensure
        previous.nil? ? ENV.delete("ELKRB_DOT") : ENV["ELKRB_DOT"] = previous
      end

      expect(File.read(output_file)).to eq("ORIGINAL")
    end

    it "does not follow a symlink planted at a scratch name" do
      # Found by review. With a fixed scratch name, a symlink sitting there
      # and pointing back at the requested file sent a failed render's partial
      # output straight onto the caller's content. Two concurrent renders of
      # the same target collided the same way. Unique, exclusively-created
      # scratch names close both.
      FileUtils.chmod(0o700, temp_dir)
      File.write(output_file, "ORIGINAL")
      File.symlink(output_file, "#{output_file}.tmp.svg")
      fake_dot = File.join(temp_dir, "dot")
      File.write(fake_dot, <<~SH)
        #!/bin/sh
        out=""
        while [ $# -gt 0 ]; do case "$1" in -o) shift; out="$1";; esac; shift; done
        printf '<?xml partial' > "$out"
        exit 1
      SH
      FileUtils.chmod(0o755, fake_dot)

      previous = ENV.fetch("ELKRB_DOT", nil)
      begin
        ENV["ELKRB_DOT"] = fake_dot
        expect do
          described_class.new(input_file, { output: output_file }).run
        end.to raise_error(StandardError)
      ensure
        previous.nil? ? ENV.delete("ELKRB_DOT") : ENV["ELKRB_DOT"] = previous
      end

      expect(File.read(output_file)).to eq("ORIGINAL")
    end

    it "does not clobber a file already at the image path" do
      FileUtils.chmod(0o700, temp_dir)
      File.write(output_file, "PRE-EXISTING USER CONTENT")
      FileUtils.chmod(0o500, temp_dir)

      expect do
        described_class.new(input_file, { output: output_file }).run
      end.to raise_error(StandardError)

      # Naming the content, not just "it still exists": the defect wrote DOT
      # over it, and a bare existence check would pass on that.
      expect(File.read(output_file)).to eq("PRE-EXISTING USER CONTENT")
    end
  end

  describe "when the render dies partway" do
    let(:input_file) do
      File.join(temp_dir, "graph.json").tap do |path|
        File.write(path, graph_data.to_json)
      end
    end
    let(:output_file) { File.join(temp_dir, "out.svg") }

    it "leaves the caller's file alone when a render dies partway" do
      # Found by review: guarding cleanup on "did this run create it?" still
      # left a TRUNCATED image under the caller's own filename -- a 1024-byte
      # `<?xml` fragment from a render that died. Rendering to a scratch name
      # and moving it into place is what makes that impossible.
      fake_dot = File.join(temp_dir, "dot")
      File.write(fake_dot, <<~SH)
        #!/bin/sh
        out=""
        while [ $# -gt 0 ]; do case "$1" in -o) shift; out="$1";; esac; shift; done
        printf '<?xml truncated' > "$out"
        exit 1
      SH
      FileUtils.chmod(0o755, fake_dot)
      File.write(output_file, "ORIGINAL USER CONTENT")

      previous = ENV.fetch("ELKRB_DOT", nil)
      begin
        ENV["ELKRB_DOT"] = fake_dot
        expect do
          described_class.new(input_file, { output: output_file }).run
        end.to raise_error(StandardError)
      ensure
        previous.nil? ? ENV.delete("ELKRB_DOT") : ENV["ELKRB_DOT"] = previous
      end

      expect(File.read(output_file)).to eq("ORIGINAL USER CONTENT")
      expect(Dir.children(temp_dir).grep(/tmp\./)).to be_empty
    end
  end
  describe "cleaning up the temporary directory" do
    let(:command) { described_class.allocate }
    let(:target) { File.join(temp_dir, "out.svg") }

    # Cleanup used to check only whether the path named A directory, not
    # whether it named THE directory this run created. Review replaced the
    # entry with a different real directory mid-render and watched the
    # recursive delete take it and its contents.
    it "leaves a different directory that took the same path" do
      scratch, identity = command.send(:scratch_dir, target)

      # The substitute is built at ANOTHER path first and moved into place,
      # so it is guaranteed to be a different live directory. Recreating at
      # the same path and then asking `directory_identity` whether the inode
      # was reused made the production method its own oracle -- review
      # mutated that method to return [0, 0] and the example SKIPPED rather
      # than failing, while the broken code would have deleted the keeper.
      substitute = File.join(temp_dir, "substitute")
      FileUtils.mkdir_p(substitute)
      keeper = File.join(substitute, "someone-elses.txt")
      File.write(keeper, "keep me")
      FileUtils.remove_entry(scratch)
      File.rename(substitute, scratch)

      command.send(:remove_scratch, scratch, identity)

      expect(File.read(File.join(scratch,
                                 "someone-elses.txt"))).to eq("keep me")
    end

    # Pins the property directly, without needing the swap to happen at a
    # particular instant: the cleanup only ever unlinks the two names this
    # code writes, so anything else in the directory keeps it non-empty and
    # `Dir.rmdir` refuses. Replacing this with a recursive remove_entry
    # turns both of these red.
    it "leaves a substitute's contents alone even when identity matches" do
      scratch, identity, token = command.send(:scratch_dir, target)
      keeper = File.join(scratch, "keeper.txt")
      File.write(keeper, "keep me")

      command.send(:remove_scratch, scratch, identity,
                   [[File.join(scratch, "graph-#{token}.dot"), [0, 0]]])

      expect(File.read(keeper)).to eq("keep me")
    end

    # The names inside the scratch directory carry their own token, so a
    # directory substituted at this path cannot hold one of them by guessing.
    # An ordinary "graph.dot" is somebody else's file and stays.
    # The two below pin the naming rule at its source. The examples that
    # pass `entries` by hand cannot: they name the token themselves, so they
    # stay green even with the production name reverted to a fixed one.
    it "hands the renderer a dot file whose name carries the token" do
      seen = nil
      graphviz = instance_double(Elkrb::GraphvizWrapper)
      allow(Elkrb::GraphvizWrapper).to receive(:new).and_return(graphviz)
      allow(graphviz).to receive(:render) do |dot_file, image_file, *|
        seen = [File.basename(dot_file), File.basename(image_file)]
        File.write(image_file, "<svg/>")
      end

      command.send(:render_to_image, "digraph {}", target, "svg")

      expect(seen).to all(match(/-[0-9a-f]{12}\./))
    end

    # A directory whose identity no longer matches is not ours to remove,
    # however empty it is. The first comparison happened several syscalls
    # earlier and does not speak for this one.
    it "refuses to rmdir a directory whose identity no longer matches" do
      scratch, = command.send(:scratch_dir, target)

      command.send(:remove_empty_directory, scratch, [-1, -1])

      expect(File).to exist(scratch)
    end

    # A file whose identity was never recorded is never unlinked, so a step
    # that raises after creating its file would leave the directory
    # non-empty and leak it. Both records are taken in an `ensure` for that
    # reason.
    it "leaves nothing behind when the dot write raises partway" do
      allow(command).to receive(:write_output) do |_content, path|
        File.write(path, "partial")
        raise Elkrb::Error, "died mid-write"
      end

      expect { command.send(:render_to_image, "digraph {}", target, "svg") }
        .to raise_error(Elkrb::Error, "died mid-write")
      expect(Dir.children(File.dirname(target))).to be_empty
    end

    # Same name, different inode. The name is in the `dot` argv and shows up
    # in `ps auxww` -- measured -- so it is not a secret and cannot be the
    # thing that decides a delete.
    it "leaves a file that took our name but is not our file" do
      scratch, identity, token = command.send(:scratch_dir, target)
      dot = File.join(scratch, "graph-#{token}.dot")
      File.write(dot, "ours")
      owned = [[dot, command.send(:file_identity, dot)]]
      File.unlink(dot)
      File.write(dot, "theirs")

      command.send(:remove_scratch, scratch, identity, owned)

      expect(File.read(dot)).to eq("theirs")
    end

    it "leaves a substitute's own graph.dot alone" do
      scratch, identity, token = command.send(:scratch_dir, target)
      victim = File.join(scratch, "graph.dot")
      File.write(victim, "user data")

      command.send(:remove_scratch, scratch, identity,
                   [[File.join(scratch, "graph-#{token}.dot"), [0, 0]]])

      expect(File.read(victim)).to eq("user data")
    end

    it "leaves a substitute alone on the unknown-identity path too" do
      scratch, = command.send(:scratch_dir, target)
      keeper = File.join(scratch, "keeper.txt")
      File.write(keeper, "keep me")

      command.send(:discard_claim, scratch, nil)

      expect(File.read(keeper)).to eq("keep me")
    end

    # A rescue covering the whole method treats a missing DESCENDANT as a
    # missing root and returns with the directory still there. Only one of
    # the two names is ever written when rendering fails partway.
    it "still removes the directory when only one entry was written" do
      scratch, identity, token = command.send(:scratch_dir, target)
      dot = File.join(scratch, "graph-#{token}.dot")
      image = File.join(scratch, "image-#{token}.svg")
      File.write(dot, "digraph {}")
      owned = [[dot, command.send(:file_identity, dot)],
               [image, command.send(:file_identity, image)]]

      command.send(:remove_scratch, scratch, identity, owned)

      expect(File).not_to exist(scratch)
    end

    it "removes the directory it did create" do
      scratch, identity = command.send(:scratch_dir, target)

      command.send(:remove_scratch, scratch, identity)

      expect(File.exist?(scratch)).to be(false)
    end

    # The directory exists before scratch_dir returns, so the caller's ensure
    # cannot cover a failure inside it. A chmod that raised used to leak it.
    # Both things that can fail after the directory exists, because only one
    # of them was covered. When capturing the identity raised, `identity`
    # stayed nil and the cleanup call no-opped -- so the directory leaked
    # while the comment above it claimed the leak was closed.
    it "removes the directory when capturing its identity fails" do
      allow(command).to receive(:directory_identity).and_raise(Errno::EACCES)

      expect { command.send(:scratch_dir, target) }
        .to raise_error(Errno::EACCES)
      expect(Dir.children(temp_dir).grep(/\A\.elkrb-/)).to be_empty
    end

    it "removes the directory when claiming it fails" do
      allow(FileUtils).to receive(:chmod).and_raise(Errno::EACCES)

      expect { command.send(:scratch_dir, target) }
        .to raise_error(Errno::EACCES)
      expect(Dir.children(temp_dir).grep(/\A\.elkrb-/)).to be_empty
    end
  end
end
