# frozen_string_literal: true

require "spec_helper"
require "English"
require "json"
require "rbconfig"
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
  end
end

RSpec.describe SirenaProvenance do
  fixture_dir = File.expand_path("../../fixtures/consumers/sirena", __dir__)
  readme = File.join(fixture_dir, "README.md")
  recorded = "c3820364551b3f107b6177bba8d1e2c0c6d3940b"
  other = "deadbeef" * 5

  describe ".expected_sha" do
    it "reads the sha out of the README's provenance table" do
      expect(described_class.expected_sha(readme)).to eq(recorded)
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
    # The pure `check!` examples above decide the policy; this one proves
    # the sha and status actually reach it from a real checkout.
    it "refuses a real checkout that is dirty and on the wrong sha" do
      Dir.mktmpdir("fake-sirena") do |dir|
        system("git", "init", "-q", dir)
        system("git", "-C", dir, "config", "user.email", "t@example.com")
        system("git", "-C", dir, "config", "user.name", "t")
        File.write(File.join(dir, "lib.rb"), "x")
        system("git", "-C", dir, "add", "lib.rb")
        system("git", "-C", dir, "commit", "-qm", "init", out: File::NULL)
        File.write(File.join(dir, "lib.rb"), "dirty")

        expect do
          described_class.assert!(sirena_dir: dir, fixture_dir: fixture_dir)
        end.to raise_error(SirenaProvenance::Mismatch, /dirty/)
      end
    end
  end
end
