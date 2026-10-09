# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe "elkrb.gemspec" do
  let(:root) { File.expand_path("..", __dir__) }
  let(:packaged) do
    %w[
      lib/elkrb/version.rb
      exe/elkrb
      README.adoc
      LICENSE
      CHANGELOG.adoc
    ]
  end

  it "packages only the whitelisted paths, even with docs/ in the checkout" do
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(root, "elkrb.gemspec"), dir)
      # An empty version.rb: spec_helper has already loaded Elkrb::VERSION.
      (packaged + ["docs/handoff/notes.md"]).each do |path|
        FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
        File.write(File.join(dir, path), "")
      end

      files = Gem::Specification.load(File.join(dir, "elkrb.gemspec")).files

      expect(files).to match_array(packaged)
    end
  end
end
