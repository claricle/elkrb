# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"

# Runs every script in examples/ the way a reader would, from a directory
# that is not the checkout. A script that stops running, or writes into its
# working directory instead of a temp path, fails here.
RSpec.describe "examples/*.rb" do
  root = File.expand_path("..", __dir__)

  Dir[File.join(root, "examples", "*.rb")].each do |script|
    it "#{File.basename(script)} exits 0" do
      Dir.mktmpdir do |dir|
        env = { "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
                "TMPDIR" => dir }
        _out, err, status = Open3.capture3(
          env, RbConfig.ruby, "-I", File.join(root, "lib"), script,
          chdir: dir
        )

        expect(status.exitstatus).to eq(0), err
        expect(Dir.children(dir)).to all(eq("output_graph.dot"))
      end
    end
  end
end
