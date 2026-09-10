# frozen_string_literal: true

require "English"
require "fileutils"
require "json"
require "rbconfig"
require "tmpdir"

# GoldenFixtures lives in the Rakefile, and its methods are public module
# methods any Ruby caller can reach -- as are the tasks, through
# `Rake::Task["golden:generate"].invoke`. Each example drives one in a
# SUBPROCESS, because "does calling this terminate my process" cannot be
# asked from inside the process asking it: a rescue in the same process
# catches SystemExit and hides exactly the defect being checked.
RSpec.describe "GoldenFixtures (Rakefile)" do
  root = File.expand_path("../..", __dir__)

  # Loads the Rakefile in a child ruby at the repo root and runs `body`.
  # Returns the combined output and the child's exit status.
  def probe(root, body)
    Dir.mktmpdir("golden-fixtures") do |tmp|
      file = File.join(tmp, "probe.rb")
      File.write(file, <<~RUBY)
        require "rake"
        load "Rakefile"
        #{body}
        puts "CALLER SURVIVED"
      RUBY
      out = IO.popen([RbConfig.ruby, file], chdir: root,
                                            err: %i[child out], &:read)
      [out, $CHILD_STATUS.exitstatus]
    end
  end

  describe "raising rather than terminating its caller" do
    # Each of the former `abort` sites, driven through the arm that
    # reaches it. All of them used to take the caller down with
    # SystemExit 1 instead of raising something a caller can handle.
    {
      "elkjs is not installed" => <<~RUBY,
        GoldenFixtures.send(:remove_const, :ELKJS_NODE_MODULES)
        GoldenFixtures.const_set(:ELKJS_NODE_MODULES, "/no/such/elkjs")
        begin
          GoldenFixtures.generate_into("/tmp/unused")
        rescue GoldenFixtures::Failed => e
          puts "RAISED: \#{e.message}"
        end
      RUBY
      "node is not on PATH" => <<~RUBY,
        GoldenFixtures.define_singleton_method(:run_generator) do |_dir|
          raise Errno::ENOENT, "node"
        end
        begin
          GoldenFixtures.generate_into("/tmp/unused")
        rescue GoldenFixtures::Failed => e
          puts "RAISED: \#{e.message}"
        end
      RUBY
      "generate.js exits non-zero" => <<~RUBY,
        GoldenFixtures.define_singleton_method(:run_generator) do |_dir|
          raise "Command failed with exit 3"
        end
        begin
          GoldenFixtures.generate_into("/tmp/unused")
        rescue GoldenFixtures::Failed => e
          puts "RAISED: \#{e.message}"
        end
      RUBY
      "the committed MANIFEST.json is missing" => <<~RUBY,
        require "tmpdir"
        Dir.mktmpdir do |empty|
          begin
            GoldenFixtures.check_against(empty, empty)
          rescue GoldenFixtures::Failed => e
            puts "RAISED: \#{e.message}"
          end
        end
      RUBY
      "the manifest has drifted" => <<~RUBY,
        require "tmpdir"
        require "json"
        Dir.mktmpdir do |dir|
          fresh = File.join(dir, "fresh")
          Dir.mkdir(fresh)
          File.write(File.join(fresh, "MANIFEST.json"),
                     JSON.generate("elkjs" => "9.9.9", "cases" => []))
          File.write(File.join(dir, "MANIFEST.json"),
                     JSON.generate("elkjs" => "0.0.1", "cases" => []))
          begin
            GoldenFixtures.check_against(fresh, dir)
          rescue GoldenFixtures::Failed => e
            puts "RAISED: \#{e.message}"
          end
        end
      RUBY
      # A whole TASK, not just a module method -- `Rake::Task[...].invoke`
      # is an ordinary Ruby call and used to exit the caller outright.
      "a rake task itself fails" => <<~RUBY,
        GoldenFixtures.send(:remove_const, :ELKJS_NODE_MODULES)
        GoldenFixtures.const_set(:ELKJS_NODE_MODULES, "/no/such/elkjs")
        begin
          Rake::Task["golden:generate"].invoke
        rescue GoldenFixtures::Failed => e
          puts "RAISED: \#{e.message}"
        end
      RUBY
    }.each do |reason, body|
      it "raises instead of terminating its caller when #{reason}" do
        out, status = probe(root, body)

        expect(status).to eq(0)
        expect(out).to include("RAISED:")
        expect(out).to include("CALLER SURVIVED")
      end
    end
  end

  describe ".publish_into" do
    # The committed tree used to be deleted with `rm_rf` BEFORE its
    # replacement was copied in, so a copy that failed part-way -- a full
    # disk, an interruption -- destroyed the fixtures outright and left
    # the previous MANIFEST.json sitting beside nothing.
    def golden_dir_with(tmp, expected_body:, manifest_body:)
      golden = File.join(tmp, "golden")
      Dir.mkdir(golden)
      Dir.mkdir(File.join(golden, "expected"))
      File.write(File.join(golden, "expected", "box3.json"), expected_body)
      File.write(File.join(golden, "MANIFEST.json"), manifest_body)
      golden
    end

    def generated(tmp)
      source = File.join(tmp, "fresh")
      Dir.mkdir(source)
      File.write(File.join(source, "box3.json"), "NEW")
      File.write(File.join(source, "MANIFEST.json"), "NEW-MANIFEST")
      source
    end

    it "replaces both the expected tree and the manifest" do
      Dir.mktmpdir do |tmp|
        golden = golden_dir_with(tmp, expected_body: "OLD",
                                      manifest_body: "OLD-MANIFEST")
        out, status = probe(root, <<~RUBY)
          GoldenFixtures.publish_into(#{generated(tmp).inspect},
                                      #{golden.inspect})
        RUBY

        expect([out, status]).to eq(["CALLER SURVIVED\n", 0])
        expect(File.read(File.join(golden, "expected", "box3.json")))
          .to eq("NEW")
        expect(File.read(File.join(golden, "MANIFEST.json")))
          .to eq("NEW-MANIFEST")
        expect(Dir.children(golden).sort).to eq(%w[MANIFEST.json expected])
      end
    end

    it "leaves the committed tree intact when the copy fails" do
      Dir.mktmpdir do |tmp|
        golden = golden_dir_with(tmp, expected_body: "OLD",
                                      manifest_body: "OLD-MANIFEST")
        out, status = probe(root, <<~RUBY)
          FileUtils.singleton_class.prepend(Module.new do
            define_method(:cp_r) { |*| raise Errno::ENOSPC }
          end)
          begin
            GoldenFixtures.publish_into(#{generated(tmp).inspect},
                                        #{golden.inspect})
          rescue Errno::ENOSPC
            puts "RAISED ENOSPC"
          end
        RUBY

        expect(status).to eq(0)
        expect(out).to include("RAISED ENOSPC")
        expect(File.read(File.join(golden, "expected", "box3.json")))
          .to eq("OLD")
        expect(File.read(File.join(golden, "MANIFEST.json")))
          .to eq("OLD-MANIFEST")
        expect(Dir.children(golden).sort).to eq(%w[MANIFEST.json expected])
      end
    end

    # The undo used to start only after both live paths had been moved
    # aside, so a failure on the SECOND keep-aside left `expected/` sitting
    # under `.previous` with the old manifest still live and nothing to
    # put it back. The injection point is that rename, not the ones the
    # example below covers.
    it "puts the old tree back when moving the manifest ASIDE fails" do
      Dir.mktmpdir do |tmp|
        golden = golden_dir_with(tmp, expected_body: "OLD",
                                      manifest_body: "OLD-MANIFEST")
        out, status = probe(root, <<~RUBY)
          File.singleton_class.prepend(Module.new do
            define_method(:rename) do |from, to|
              raise Errno::ENOSPC, to if from.end_with?("/MANIFEST.json") &&
                                         to.end_with?(".previous")

              super(from, to)
            end
          end)
          begin
            GoldenFixtures.publish_into(#{generated(tmp).inspect},
                                        #{golden.inspect})
          rescue Errno::ENOSPC
            puts "RAISED ENOSPC"
          end
        RUBY

        expect(status).to eq(0)
        expect(out).to include("RAISED ENOSPC")
        expect(File.read(File.join(golden, "expected", "box3.json")))
          .to eq("OLD")
        expect(File.read(File.join(golden, "MANIFEST.json")))
          .to eq("OLD-MANIFEST")
        # No `.previous` left over: the tree is BACK, not merely survived.
        expect(Dir.children(golden).sort).to eq(%w[MANIFEST.json expected])
      end
    end

    it "puts the old tree back when only the manifest rename fails" do
      Dir.mktmpdir do |tmp|
        golden = golden_dir_with(tmp, expected_body: "OLD",
                                      manifest_body: "OLD-MANIFEST")
        out, status = probe(root, <<~RUBY)
          File.singleton_class.prepend(Module.new do
            define_method(:rename) do |from, to|
              raise Errno::EXDEV, to if to.end_with?("/MANIFEST.json") &&
                                        from.include?(".staged")

              super(from, to)
            end
          end)
          begin
            GoldenFixtures.publish_into(#{generated(tmp).inspect},
                                        #{golden.inspect})
          rescue Errno::EXDEV
            puts "RAISED EXDEV"
          end
        RUBY

        expect(status).to eq(0)
        expect(out).to include("RAISED EXDEV")
        # Both, or the directory holds a new tree beside an old manifest.
        expect(File.read(File.join(golden, "expected", "box3.json")))
          .to eq("OLD")
        expect(File.read(File.join(golden, "MANIFEST.json")))
          .to eq("OLD-MANIFEST")
        expect(Dir.children(golden).sort).to eq(%w[MANIFEST.json expected])
      end
    end
  end
end
