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

  describe ".check_manifest_drift" do
    # The hash-driven examples above vary `elkjs` alone (with `cases` held
    # identical on both sides as `[]`), so `%w[elkjs cases].reject { ... }`'s
    # `cases` arm was never independently exercised -- a regression that
    # broke case-list comparison specifically (a typo'd key, comparing the
    # wrong field) would not have been caught. This holds `elkjs` IDENTICAL
    # and varies only `cases`, and asserts the message names `cases` (not
    # just "something drifted").
    it "names cases specifically when only the case list drifted" do
      Dir.mktmpdir do |tmp|
        fresh = File.join(tmp, "fresh")
        Dir.mkdir(fresh)
        File.write(File.join(fresh, "MANIFEST.json"),
                   JSON.generate("elkjs" => "0.11.0", "cases" => %w[a b]))
        File.write(File.join(tmp, "MANIFEST.json"),
                   JSON.generate("elkjs" => "0.11.0", "cases" => %w[a]))

        out, status = probe(root, <<~RUBY)
          begin
            GoldenFixtures.check_against(#{fresh.inspect}, #{tmp.inspect})
          rescue GoldenFixtures::Failed => e
            puts "RAISED: \#{e.message}"
          end
        RUBY

        expect(status).to eq(0)
        expect(out).to include("RAISED: MANIFEST.json drift in cases")
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
          # Matches only the swap-IN of the new manifest: destination is the
          # live MANIFEST.json path (not a `.previous` backup) AND source is
          # NOT a `.previous` backup either -- the keep-aside rename (`to`
          # ends in ".previous") and the RESTORE rename this failure itself
          # triggers (`from` ends in ".previous", same `to`) both have to be
          # excluded, or the mock also intercepts rollback's own attempt to
          # put the backup back and the example proves nothing about the
          # code it means to test.
          File.singleton_class.prepend(Module.new do
            define_method(:rename) do |from, to|
              if to.end_with?("/MANIFEST.json") && !to.end_with?(".previous") &&
                 !from.end_with?(".previous")
                raise Errno::EXDEV, to
              end

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

    # `restore`'s nil-aside branch used to do nothing at all, on the
    # reasoning that nothing existed at `path` before so there was
    # nothing to undo. That reasoning breaks the moment THIS run's own
    # swap rename for `path` already succeeded before a LATER rename
    # failed: something new (this run's own tree) is now at `path`, and
    # true rollback means removing it, not leaving it -- measured with
    # `expected/` absent beforehand.
    it "removes the newly installed tree when it did not exist before " \
       "and the manifest rename then fails" do
      Dir.mktmpdir do |tmp|
        golden = File.join(tmp, "golden")
        Dir.mkdir(golden)
        File.write(File.join(golden, "MANIFEST.json"), "OLD-MANIFEST")

        out, status = probe(root, <<~RUBY)
          # Same "swap-IN, not keep-aside, not the rollback restore" match
          # as the example above.
          File.singleton_class.prepend(Module.new do
            define_method(:rename) do |from, to|
              if to.end_with?("/MANIFEST.json") && !to.end_with?(".previous") &&
                 !from.end_with?(".previous")
                raise Errno::EXDEV, to
              end

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
        expect(File.exist?(File.join(golden, "expected"))).to be(false)
        expect(File.read(File.join(golden, "MANIFEST.json")))
          .to eq("OLD-MANIFEST")
        expect(Dir.children(golden)).to eq(%w[MANIFEST.json])
      end
    end

    # The staging/backup names used to be predictable
    # (`.expected.<pid>.staged`/`.previous`), sitting in `golden_dir` itself
    # -- a directory this run does not own alone. A crashed earlier run at
    # a since-reused pid could leave a file at exactly that path, and
    # `cp_r`/`rename` would either collide with it or silently read it back
    # as this run's own. `publish_into` itself runs in the PROBED CHILD
    # process, not this example's own process, so the stale file has to be
    # seeded using the CHILD's own `Process.pid` (written to a marker file
    # first) -- seeding it with this example's pid would never collide
    # with either the old or the new code, since the two processes' pids
    # differ, and would make this example pass vacuously regardless of
    # which naming scheme `publish_into` uses. Mutation-verified: reverting
    # `publish_into`/`swap_into_place` to the pid-named scheme makes this
    # example, and only this one, go red (the pre-seeded file is a plain
    # FILE where `cp_r` expects to write a directory, so the old code
    # raises `Errno::EEXIST` on the collision instead of publishing --
    # measured directly: `FileUtils.cp_r` into a path already occupied by
    # a plain file raises "File exists @ dir_s_mkdir", not ENOTDIR).
    it "does not collide with a stale predictable-name file left by an " \
       "earlier crashed run" do
      Dir.mktmpdir do |tmp|
        golden = golden_dir_with(tmp, expected_body: "OLD",
                                      manifest_body: "OLD-MANIFEST")
        marker = File.join(tmp, "child-pid")

        out, status = probe(root, <<~RUBY)
          File.write(#{marker.inspect}, Process.pid.to_s)
          stale = File.join(#{golden.inspect},
                             ".expected.\#{Process.pid}.staged")
          File.write(stale, "STALE-COLLISION")
          GoldenFixtures.publish_into(#{generated(tmp).inspect},
                                      #{golden.inspect})
        RUBY

        expect([out, status]).to eq(["CALLER SURVIVED\n", 0])
        stale = File.join(golden, ".expected.#{File.read(marker)}.staged")
        expect(File.read(File.join(golden, "expected", "box3.json")))
          .to eq("NEW")
        expect(File.read(File.join(golden, "MANIFEST.json")))
          .to eq("NEW-MANIFEST")
        expect(File.read(stale)).to eq("STALE-COLLISION")
      end
    end

    # `work` (the private staging/backup directory) used to be created with
    # the BLOCK form of `Dir.mktmpdir`, which removes it on any exit from
    # the block -- including one where rollback itself failed to restore
    # a backup. That destroyed the only remaining copy of the original
    # `expected/` tree instead of merely leaving it un-restored --
    # measured by forcing BOTH the forward manifest rename (triggering
    # rollback) AND the restore-side rename of `expected` to fail.
    # `expected` itself ends up genuinely absent from `golden_dir` (its
    # restore rename never succeeded), which is why the fix's job is only
    # to keep `work` alive and name its path -- not to claim a full
    # recovery it cannot make. Same fix as
    # `spec/fixtures/consumers/sirena/capture.rb#settle`.
    it "keeps the un-restorable backup instead of deleting it when " \
       "rollback itself fails" do
      Dir.mktmpdir do |tmp|
        golden = golden_dir_with(tmp, expected_body: "OLD",
                                      manifest_body: "OLD-MANIFEST")
        out, status = probe(root, <<~RUBY)
          File.singleton_class.prepend(Module.new do
            define_method(:rename) do |from, to|
              if to.end_with?("/MANIFEST.json") && !to.end_with?(".previous") &&
                 !from.end_with?(".previous")
                raise Errno::EXDEV, to
              end
              if to.end_with?("/expected") && !to.end_with?(".previous") &&
                 from.end_with?("expected.previous")
                raise Errno::EACCES, to
              end

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
        expect(out)
          .to match(/could not restore .*expected.* -- the originals are in/)

        work_dir = Dir.children(golden).find { |e| e.start_with?(".golden") }
        expect(work_dir).not_to be_nil
        backup = File.join(golden, work_dir, "expected.previous",
                           "box3.json")
        expect(File.read(backup)).to eq("OLD")
        # The manifest's own restore was unaffected by `expected`'s
        # failure -- each restoration is attempted independently.
        expect(File.read(File.join(golden, "MANIFEST.json")))
          .to eq("OLD-MANIFEST")
      end
    end

    # `File.exist?` follows a symlink, so a dangling one at MANIFEST.json
    # used to read as "nothing there": `keep_aside` left it untouched
    # (believing there was nothing to move aside) and `restore`'s
    # `aside.nil?` branch then deleted it outright on rollback, reading the
    # untouched original link as if it were this run's own new content.
    # Mutation-verified: reverting `present?`/`keep_aside`/`restore` to a
    # plain `File.exist?` check makes this example, and only this one, go
    # red (the dangling symlink comes back deleted instead of restored).
    it "restores a dangling symlink at MANIFEST.json rather than " \
       "deleting it on rollback" do
      Dir.mktmpdir do |tmp|
        golden = File.join(tmp, "golden")
        Dir.mkdir(golden)
        Dir.mkdir(File.join(golden, "expected"))
        File.write(File.join(golden, "expected", "box3.json"), "OLD")
        dangling_target = File.join(tmp, "nonexistent-target")
        File.symlink(dangling_target, File.join(golden, "MANIFEST.json"))

        out, status = probe(root, <<~RUBY)
          File.singleton_class.prepend(Module.new do
            define_method(:rename) do |from, to|
              if to.end_with?("/MANIFEST.json") &&
                 !to.end_with?(".previous") && !from.end_with?(".previous")
                raise Errno::EXDEV, to
              end

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
        manifest_path = File.join(golden, "MANIFEST.json")
        expect(File.symlink?(manifest_path)).to be(true)
        expect(File.readlink(manifest_path)).to eq(dangling_target)
        # The old tree survives untouched too -- this is a full rollback,
        # not a partial one.
        expect(File.read(File.join(golden, "expected", "box3.json")))
          .to eq("OLD")
      end
    end
  end

  describe ".with_directory_lock" do
    # Two `rake golden:generate` runs pointed at one golden_dir used to
    # interleave: one run's rollback silently undid the other's
    # already-reported-successful publish -- measured with a two-process
    # probe. Same assertion style as
    # `spec/cross_validation/corpus_spec.rb`'s "holds an exclusive lock"
    # example: flock on a second descriptor is refused even inside one
    # process, so this proves the real lock rather than trusting that the
    # code merely calls flock somewhere. Locks the SIBLING `lock_path`,
    # not `golden` itself (see `with_directory_lock`'s comment for why:
    # opening a directory read-only to lock it raises EISDIR on Windows).
    it "holds an exclusive lock on the golden directory while it works" do
      Dir.mktmpdir do |golden|
        out, status = probe(root, <<~RUBY)
          lock_path = GoldenFixtures.send(:lock_path, #{golden.inspect})
          inside = GoldenFixtures.send(:with_directory_lock,
                                       #{golden.inspect}) do
            File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |f|
              if f.flock(File::LOCK_EX | File::LOCK_NB)
                f.flock(File::LOCK_UN)
                true
              else
                false
              end
            end
          end
          puts "INSIDE=\#{inside}"
        RUBY

        expect(status).to eq(0)
        expect(out).to include("INSIDE=false")
      end
    end

    # `lock_path` must never resolve to a path INSIDE `golden_dir` -- that
    # would put an untracked file where `publish_into`/`check_against`
    # only ever expect `expected/` and `MANIFEST.json`, and a trailing
    # separator on `golden_dir` is exactly what turns naive concatenation
    # into "golden/.lock" (`File.dirname`/`File.basename` avoid it; plain
    # `+`/`File.join(golden_dir, ...)` would not). Covers both a bare path
    # and one with a trailing "/".
    it "builds the lock path beside golden_dir, never inside it" do
      out, status = probe(root, <<~RUBY)
        %w[/tmp/golden /tmp/golden/].each do |golden_dir|
          puts GoldenFixtures.send(:lock_path, golden_dir)
        end
      RUBY

      expect(status).to eq(0)
      expect(out.lines.map(&:chomp).first(2))
        .to eq(["/tmp/golden.lock", "/tmp/golden.lock"])
    end
  end
end
