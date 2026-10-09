# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"

# Runs each README example that states its output and compares what it
# prints with the listing beside it. Edit a printed value in README.adoc,
# or change a layout, and the example fails.
RSpec.describe "README.adoc examples" do
  extend ReadmeExamples

  root = File.expand_path("..", __dir__)
  readme = File.join(root, "README.adoc")

  examples = readme_examples(readme)

  it "finds the examples to run" do
    expect(examples.size).to be >= 6
  end

  examples.each do |example|
    it "prints what README.adoc line #{example.line} says" do
      Dir.mktmpdir do |dir|
        script = File.join(dir, "example.rb")
        File.write(script, example.code)
        env = { "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
                "TMPDIR" => dir }
        out, err, status = Open3.capture3(
          env, RbConfig.ruby, "-I", File.join(root, "lib"), script,
          chdir: dir
        )

        expect(status.exitstatus).to eq(0), err
        expect(out).to eq(example.printed)
      end
    end
  end
end
