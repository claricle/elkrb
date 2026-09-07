# frozen_string_literal: true

require "English"
require "rbconfig"
require "tmpdir"

# GoldenFixtures lives in the Rakefile, and its methods are public module
# methods any Ruby caller can reach. Each example drives one in a
# SUBPROCESS, because "does calling this terminate my process" cannot be
# asked from inside the process asking it -- a rescue in the same process
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

  # Each of the three former `abort` sites, driven through the arm that
  # reaches it. All three used to take the caller down with SystemExit 1.
  {
    "elkjs is not installed" => <<~RUBY,
      GoldenFixtures.send(:remove_const, :ELKJS_NODE_MODULES)
      GoldenFixtures.const_set(:ELKJS_NODE_MODULES, "/no/such/elkjs")
      begin
        GoldenFixtures.generate_into("/tmp/unused")
      rescue GoldenFixtures::GenerationFailed => e
        puts "RAISED: \#{e.message}"
      end
    RUBY
    "node is not on PATH" => <<~RUBY,
      GoldenFixtures.define_singleton_method(:run_generator) do |_dir|
        raise Errno::ENOENT, "node"
      end
      begin
        GoldenFixtures.generate_into("/tmp/unused")
      rescue GoldenFixtures::GenerationFailed => e
        puts "RAISED: \#{e.message}"
      end
    RUBY
    "generate.js exits non-zero" => <<~RUBY,
      GoldenFixtures.define_singleton_method(:run_generator) do |_dir|
        raise "Command failed with exit 3"
      end
      begin
        GoldenFixtures.generate_into("/tmp/unused")
      rescue GoldenFixtures::GenerationFailed => e
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
