# frozen_string_literal: true

require "spec_helper"
require "English"
require "json"
require "rbconfig"
require "stringio"
require "tmpdir"
require "support/sirena_provenance"

# capture.rb needs sirena, which elkrb does not depend on, so every
# example here runs it in a subprocess against a stub gem on -I. The
# subprocess is the point for the entry-point example: "does requiring
# this file kill my process" cannot be asked from inside the process
# doing the asking.
RSpec.describe "spec/fixtures/consumers/sirena/capture.rb" do
  fixture_dir = File.expand_path("../../fixtures/consumers/sirena", __dir__)
  script = File.join(fixture_dir, "capture.rb")
  captured = %w[
    c4_nested class_flat er flowchart_lr flowchart_td sequence
    state user_journey
  ]

  # A stub sirena whose transform raises on the Nth call, so a failure
  # part-way through a capture can be driven from an example.
  stub_gem = <<~RUBY
    module Sirena
      module DiagramRegistry
        class Parser
          def parse(text) = text
        end

        class Transform
          @@calls = 0
          FAIL_ON = ENV.fetch("STUB_FAIL_ON", "0").to_i

          def to_graph(diagram)
            @@calls += 1
            raise "transform failed" if @@calls == FAIL_ON

            { "id" => diagram.to_s.strip[0, 20] }
          end
        end

        def self.get(_type) = { parser: Parser, transform: Transform }
      end
    end
  RUBY

  around do |example|
    Dir.mktmpdir("sirena-capture") do |tmp|
      @tmp = tmp
      @stub_dir = File.join(tmp, "stub")
      @out_dir = File.join(tmp, "out")
      Dir.mkdir(@stub_dir)
      File.write(File.join(@stub_dir, "sirena.rb"), stub_gem)
      example.run
    end
  end

  # Runs `body` in a child ruby that can see the stub sirena, and returns
  # its combined output and exit status.
  def run_ruby(body, fail_on: 0)
    script_file = File.join(@tmp, "runner.rb")
    File.write(script_file, body)
    out = IO.popen(
      { "STUB_FAIL_ON" => fail_on.to_s },
      [RbConfig.ruby, "-I", @stub_dir, script_file],
      err: %i[child out], &:read
    )
    [out, $CHILD_STATUS.exitstatus]
  end

  def written
    Dir.children(@out_dir).sort
  rescue Errno::ENOENT
    []
  end

  describe "the entry-point guard" do
    it "lets a caller that requires it keep running" do
      out, status = run_ruby(<<~RUBY)
        require #{script.inspect}
        puts "CALLER SURVIVED"
      RUBY

      expect(status).to eq(0)
      expect(out).to include("CALLER SURVIVED")
    end

    it "still reports usage when run as a script with no arguments" do
      out, status = run_ruby(<<~RUBY)
        $PROGRAM_NAME = #{script.inspect}
        load #{script.inspect}
      RUBY

      expect(status).to eq(1)
      expect(out).to include("usage: ruby capture.rb")
    end
  end

  describe "publishing" do
    it "writes every fixture when all eight transforms succeed" do
      _out, status = run_ruby(<<~RUBY)
        require #{script.inspect}
        SirenaCapture.capture(#{fixture_dir.inspect}, #{@out_dir.inspect})
      RUBY

      expect(status).to eq(0)
      expect(written).to eq(captured.map { |n| "#{n}.json" }.sort)
    end

    it "writes nothing at all when a later transform fails" do
      out, status = run_ruby(<<~RUBY, fail_on: 2)
        require #{script.inspect}
        SirenaCapture.capture(#{fixture_dir.inspect}, #{@out_dir.inspect})
      RUBY

      expect(status).not_to eq(0)
      expect(out).to include("transform failed")
      # Not "no .json" -- NOTHING, so a staged temp file cannot be left
      # behind either.
      expect(written).to eq([])
    end

    it "leaves fixtures already in the directory untouched on failure" do
      Dir.mkdir(@out_dir)
      existing = File.join(@out_dir, "c4_nested.json")
      File.write(existing, %({"id":"the previous capture"}\n))

      _out, status = run_ruby(<<~RUBY, fail_on: 2)
        require #{script.inspect}
        SirenaCapture.capture(#{fixture_dir.inspect}, #{@out_dir.inspect})
      RUBY

      expect(status).not_to eq(0)
      expect(File.read(existing)).to eq(%({"id":"the previous capture"}\n))
      expect(written).to eq(["c4_nested.json"])
    end

    # The two below drive `publish` directly, because they are about what
    # happens AFTER every transform has succeeded -- the transform stub
    # cannot reach that far.
    it "leaves no temp file behind when a graph cannot be serialized" do
      out, status = run_ruby(<<~RUBY)
        require #{script.inspect}
        unserializable = Object.new
        def unserializable.to_json(*) = raise("cannot serialize")
        SirenaCapture.publish([["a", { "ok" => 1 }],
                               ["b", { "x" => unserializable }]],
                              #{@out_dir.inspect})
      RUBY

      expect(status).not_to eq(0)
      expect(out).to include("cannot serialize")
      expect(written).to eq([])
    end

    it "publishes nothing when one target cannot be replaced" do
      Dir.mkdir(@out_dir)
      # A directory where "b.json" belongs. Renaming one file at a time,
      # "a.json" was replaced before this raised EISDIR.
      Dir.mkdir(File.join(@out_dir, "b.json"))
      File.write(File.join(@out_dir, "a.json"), "PREVIOUS")

      out, status = run_ruby(<<~RUBY)
        require #{script.inspect}
        SirenaCapture.publish([["a", { "v" => "new" }], ["b", { "v" => "new" }]],
                              #{@out_dir.inspect})
      RUBY

      expect(status).not_to eq(0)
      expect(out).to include("is not a regular file")
      expect(File.read(File.join(@out_dir, "a.json"))).to eq("PREVIOUS")
      expect(written).to eq(["a.json", "b.json"])
    end

    it "refuses a staging path that already exists as a symlink" do
      Dir.mkdir(@out_dir)
      victim = File.join(@tmp, "victim.txt")
      File.write(victim, "PRECIOUS")
      # The staging name is predictable, so a link can be waiting there.
      # `CREAT|TRUNC` wrote the capture straight through it and then
      # installed the link as a.json.
      out, status = run_ruby(<<~RUBY)
        require #{script.inspect}
        link = File.join(#{@out_dir.inspect}, ".a.json.\#{Process.pid}.tmp")
        File.symlink(#{victim.inspect}, link)
        SirenaCapture.publish([["a", { "v" => "attacker" }]],
                              #{@out_dir.inspect})
      RUBY

      expect(status).not_to eq(0)
      expect(out).to include("File exists")
      expect(File.read(victim)).to eq("PRECIOUS")
      expect(File.exist?(File.join(@out_dir, "a.json"))).to be(false)
    end

    it "rolls back when the publish is INTERRUPTED, not only on an errno" do
      Dir.mkdir(@out_dir)
      %w[a b].each do |n|
        File.write(File.join(@out_dir, "#{n}.json"), "OLD-#{n}")
      end

      out, status = run_ruby(<<~RUBY)
        require #{script.inspect}
        # Interrupt is what Ctrl-C raises, and it is NOT a SystemCallError.
        File.singleton_class.prepend(Module.new do
          define_method(:rename) do |from, to|
            raise Interrupt if to.end_with?("/b.json") && from.end_with?(".tmp")

            super(from, to)
          end
        end)
        SirenaCapture.publish([["a", { "v" => "new" }], ["b", { "v" => "new" }]],
                              #{@out_dir.inspect})
      RUBY

      expect(status).not_to eq(0)
      expect(out).to include("Interrupt")
      expect(File.read(File.join(@out_dir, "a.json"))).to eq("OLD-a")
      expect(File.read(File.join(@out_dir, "b.json"))).to eq("OLD-b")
      expect(written).to eq(["a.json", "b.json"])
    end

    it "restores a DANGLING symlink target rather than deleting it" do
      Dir.mkdir(@out_dir)
      # `File.exist?` follows a link, so a dangling one read as "nothing
      # here" and rollback removed it instead of putting it back.
      File.symlink(File.join(@tmp, "gone"), File.join(@out_dir, "a.json"))
      File.write(File.join(@out_dir, "b.json"), "OLD-b")

      _out, status = run_ruby(<<~RUBY)
        require #{script.inspect}
        File.singleton_class.prepend(Module.new do
          define_method(:rename) do |from, to|
            publishing_b = to.end_with?("/b.json") && from.end_with?(".tmp")
            raise Errno::EXDEV, to if publishing_b

            super(from, to)
          end
        end)
        SirenaCapture.publish([["a", { "v" => "new" }], ["b", { "v" => "new" }]],
                              #{@out_dir.inspect})
      RUBY

      expect(status).not_to eq(0)
      expect(File.symlink?(File.join(@out_dir, "a.json"))).to be(true)
      expect(File.read(File.join(@out_dir, "b.json"))).to eq("OLD-b")
      expect(written).to eq(["a.json", "b.json"])
    end

    it "restores every target it had already replaced when a rename fails" do
      Dir.mkdir(@out_dir)
      %w[a b].each do |n|
        File.write(File.join(@out_dir, "#{n}.json"), "OLD-#{n}")
      end

      out, status = run_ruby(<<~RUBY)
        require #{script.inspect}
        # Let the first rename through, then fail the second -- the shape
        # `refuse_unpublishable!` cannot see, so only the undo log saves it.
        File.singleton_class.prepend(Module.new do
          define_method(:rename) do |from, to|
            publishing_b = to.end_with?("/b.json") && from.end_with?(".tmp")
            raise Errno::EXDEV, to if publishing_b

            super(from, to)
          end
        end)
        SirenaCapture.publish([["a", { "v" => "new" }], ["b", { "v" => "new" }]],
                              #{@out_dir.inspect})
      RUBY

      expect(status).not_to eq(0)
      expect(out).to include("Errno::EXDEV")
      expect(File.read(File.join(@out_dir, "a.json"))).to eq("OLD-a")
      expect(File.read(File.join(@out_dir, "b.json"))).to eq("OLD-b")
      expect(written).to eq(["a.json", "b.json"])
    end
  end
end

RSpec.describe SirenaProvenance do
  fixture_dir = File.expand_path("../../fixtures/consumers/sirena", __dir__)
  readme = File.join(fixture_dir, "README.md")
  # Read, never hardcoded: the README's table is the one place the
  # expected commit is written down, and a copy here would have to be
  # edited in lockstep with it on every legitimate re-capture.
  recorded = SirenaProvenance.expected_sha(readme)
  other = "deadbeef" * 5

  describe ".expected_sha" do
    it "reads the sha out of a provenance table" do
      # A synthetic table, so this asserts the PARSE rather than agreeing
      # with itself about which sha the real README happens to hold.
      Dir.mktmpdir("readme") do |dir|
        path = File.join(dir, "README.md")
        File.write(path, <<~MD)
          | | |
          |---|---|
          | sirena commit | `#{other}` |
          | sirena branch | `plan/architecture-update` |
        MD

        expect(described_class.expected_sha(path)).to eq(other)
      end
    end

    it "refuses a README with no provenance row" do
      Dir.mktmpdir("readme") do |dir|
        path = File.join(dir, "README.md")
        File.write(path, "no table here\n")

        expect { described_class.expected_sha(path) }
          .to raise_error(SirenaProvenance::Mismatch, /no `sirena commit` row/)
      end
    end
  end

  describe ".check!" do
    it "accepts a clean checkout sitting on the recorded sha" do
      expect(
        described_class.check!(sha: recorded, status: "", expected: recorded),
      ).to eq(recorded)
    end

    it "refuses a dirty checkout even on the recorded sha" do
      expect do
        described_class.check!(sha: recorded, status: " M lib/sirena.rb",
                               expected: recorded)
      end.to raise_error(SirenaProvenance::Mismatch,
                         %r{dirty.*M lib/sirena\.rb}m)
    end

    it "refuses a clean checkout on a different sha" do
      expect do
        described_class.check!(sha: other, status: "", expected: recorded)
      end.to raise_error(
        SirenaProvenance::Mismatch,
        /is at #{other}, but the fixtures record #{recorded}/,
      )
    end

    it "accepts a different sha when the caller names it" do
      expect(
        described_class.check!(sha: other, status: "", expected: other),
      ).to eq(other)
    end
  end

  describe ".assert!" do
    # The pure `check!` examples above decide the policy; these prove the
    # sha and the status each reach it from a real checkout. TWO examples,
    # not one: a dirty tree short-circuits before the sha is compared, so
    # a single dirty example passes even with `rev-parse` and `status`
    # wired to the wrong arguments.
    let(:log) { StringIO.new }

    def fake_checkout(dir)
      system("git", "init", "-q", dir)
      system("git", "-C", dir, "config", "user.email", "t@example.com")
      system("git", "-C", dir, "config", "user.name", "t")
      File.write(File.join(dir, "lib.rb"), "x")
      system("git", "-C", dir, "add", "lib.rb")
      system("git", "-C", dir, "commit", "-qm", "init", out: File::NULL)
      `git -C #{dir} rev-parse HEAD`.strip
    end

    it "refuses a real checkout whose working tree is dirty" do
      Dir.mktmpdir("fake-sirena") do |dir|
        fake_checkout(dir)
        File.write(File.join(dir, "lib.rb"), "dirty")

        expect do
          described_class.assert!(sirena_dir: dir, fixture_dir: fixture_dir,
                                  io: log)
        end.to raise_error(SirenaProvenance::Mismatch, /dirty/)
      end
    end

    it "refuses a real CLEAN checkout that is on the wrong sha" do
      Dir.mktmpdir("fake-sirena") do |dir|
        head = fake_checkout(dir)

        expect do
          described_class.assert!(sirena_dir: dir, fixture_dir: fixture_dir,
                                  io: log)
        end.to raise_error(SirenaProvenance::Mismatch,
                           /is at #{head}, but the fixtures record #{recorded}/)
      end
    end

    it "accepts a real clean checkout when SIRENA_SHA names its head" do
      Dir.mktmpdir("fake-sirena") do |dir|
        head = fake_checkout(dir)

        expect(
          described_class.assert!(sirena_dir: dir, fixture_dir: fixture_dir,
                                  expected: head, io: log),
        ).to eq(head)
      end
    end

    # `present` is the one place the blank-env rule lives, because the two
    # callers got it wrong in two different ways: SIRENA_SHA="" overrode the
    # README with an empty sha, and OUT_DIR="" published the fixtures into
    # Dir.pwd, since File.expand_path("") is the working directory. The
    # values below are what ENV.fetch actually hands back, not invented ones.
    describe ".present" do
      it "keeps a value that names something" do
        expect(described_class.present("abc123")).to eq("abc123")
        expect(described_class.present("  abc123  ")).to eq("abc123")
      end

      it "reads every blank ENV shape as not given" do
        # "" is ENV.fetch(k, nil) for `K=`; " " is `K=" "`; nil is absent.
        expect(described_class.present("")).to be_nil
        expect(described_class.present("   ")).to be_nil
        expect(described_class.present(nil)).to be_nil
      end
    end

    # The Rakefile used to write `File.expand_path(ENV.fetch("OUT_DIR", dir))`.
    # ENV.fetch's default only fires when the key is ABSENT, so `OUT_DIR=`
    # reached expand_path as "" -- and File.expand_path("") is Dir.pwd, which
    # would publish the fixtures into whatever directory rake was run from.
    describe ".out_dir" do
      it "falls back to the default for every blank shape" do
        ["", "   ", nil].each do |blank|
          expect(described_class.out_dir(blank, default: "/d"))
            .to eq(File.expand_path("/d")), "blank #{blank.inspect} leaked"
        end
      end

      it "honours a directory that was actually named" do
        expect(described_class.out_dir("/tmp/elsewhere", default: "/d"))
          .to eq(File.expand_path("/tmp/elsewhere"))
      end

      # The specific regression: a blank must not resolve to the cwd.
      it "never resolves a blank to the working directory" do
        expect(described_class.out_dir("", default: "/d")).not_to eq(Dir.pwd)
      end
    end

    # `SIRENA_SHA= rake ...` -- the variable set but empty, which is what an
    # unset shell variable expands to in CI -- reaches assert! as "" via
    # ENV.fetch, and "" is truthy. Before the blank normalisation it replaced
    # the README sha with an empty one: a guaranteed Mismatch on a checkout
    # that is actually correct, reported against "the SIRENA_SHA override".
    # A blank override names no sha, so it must fall back to the table.
    it "treats a blank SIRENA_SHA as no override at all" do
      Dir.mktmpdir("fake-sirena") do |dir|
        head = fake_checkout(dir)

        expect do
          described_class.assert!(sirena_dir: dir, fixture_dir: fixture_dir,
                                  expected: "", io: log)
        end.to raise_error(SirenaProvenance::Mismatch,
                           /is at #{head}, but the fixtures record #{recorded}/)
      end
    end

    # The confirmation has to name the thing actually checked. It used to
    # say "matches the provenance table" on every accepted run, including
    # one where SIRENA_SHA had replaced that table.
    it "says the override, not the table, when SIRENA_SHA decided it" do
      Dir.mktmpdir("fake-sirena") do |dir|
        head = fake_checkout(dir)
        described_class.assert!(sirena_dir: dir, fixture_dir: fixture_dir,
                                expected: head, io: log)

        expect(log.string).to eq(
          "sirena is at #{head}, clean, and matches the SIRENA_SHA override.\n",
        )
      end
    end

    it "says the provenance table when the README's own sha decided it" do
      Dir.mktmpdir("fake-sirena") do |dir|
        head = fake_checkout(dir)
        Dir.mktmpdir("fake-fixtures") do |fixtures|
          File.write(File.join(fixtures, "README.md"),
                     "| sirena commit | `#{head}` |\n")
          described_class.assert!(sirena_dir: dir, fixture_dir: fixtures,
                                  io: log)
        end

        expect(log.string).to eq(
          "sirena is at #{head}, clean, and matches the provenance table.\n",
        )
      end
    end

    # git writes to stderr for reasons nobody chose -- a repository
    # format hint, a redirect notice, GIT_TRACE. Merged into stdout, that
    # text became part of the value read back as the status, and a clean
    # checkout was reported dirty. GIT_TRACE is simply the cheapest way
    # to make git talk on a run that succeeds.
    it "ignores what git writes to stderr on a successful command" do
      Dir.mktmpdir("fake-sirena") do |dir|
        head = fake_checkout(dir)
        previous = ENV.fetch("GIT_TRACE", nil)
        ENV["GIT_TRACE"] = "1"

        begin
          expect(
            described_class.assert!(sirena_dir: dir, fixture_dir: fixture_dir,
                                    expected: head, io: log),
          ).to eq(head)
        ensure
          ENV["GIT_TRACE"] = previous
        end
      end
    end
  end
end
