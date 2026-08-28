# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "elkjs_test_importer"

# `import_all` rewrites fixtures/elkjs/imported_tests.json wholesale, so
# whatever it collects is the whole committed corpus. Two things decide
# what it collects: the guards that refuse to write an empty import, and
# the glob that finds the bug files.
#
# Every example runs with the cwd inside a Dir.mktmpdir, because OUTPUT_PATH
# is relative -- a spec that got this wrong would overwrite the tracked
# fixture from a test run.
RSpec.describe ElkjsTestImporter do
  # import_all is a script entry point: it warns on stderr and calls exit
  # rather than raising. Both streams are captured so the progress chatter
  # does not reach the suite's own output.
  def import(importer)
    stdout = $stdout
    stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    status = exit_status { importer.import_all }
    [status, $stderr.string]
  ensure
    $stdout = stdout
    $stderr = stderr
  end

  # nil when the importer ran to completion instead of exiting.
  def exit_status
    yield
    nil
  rescue SystemExit => e
    e.status
  end

  def checkout(parent, name, files)
    dir = File.join(parent, name)
    files.each do |rel|
      path = File.join(dir, "test/mocha", rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "// test")
    end
    dir
  end

  def stub_checkout(dir)
    stub_const("#{described_class}::ELKJS_PATH", dir)
    stub_const("#{described_class}::TEST_PATH", File.join(dir, "test/mocha"))
  end

  def written_ids(cwd)
    path = File.join(cwd, described_class::OUTPUT_PATH, "imported_tests.json")
    return nil unless File.exist?(path)

    JSON.parse(File.read(path)).map { |kase| kase["id"] }
  end

  it "refuses to overwrite the fixture when the checkout is missing" do
    Dir.mktmpdir do |tmp|
      stub_checkout(File.join(tmp, "absent"))

      status, stderr = Dir.chdir(tmp) { import(described_class.new) }

      expect(status).to eq(1)
      expect(stderr).to include("refusing to overwrite")
      expect(written_ids(tmp)).to be_nil
    end
  end

  it "refuses to overwrite the fixture when the checkout holds no tests" do
    Dir.mktmpdir do |tmp|
      stub_checkout(checkout(tmp, "elkjs", []))

      status, stderr = Dir.chdir(tmp) { import(described_class.new) }

      expect(status).to eq(1)
      expect(stderr).to include("refusing to overwrite")
      expect(written_ids(tmp)).to be_nil
    end
  end

  # TEST_PATH is built from ELKJS_DIR, so the checkout path a caller chose
  # reaches the bug-file glob. Joining it into the pattern let a `*` in it
  # match a sibling checkout too, and the foreign case landed in the
  # committed fixture.
  it "does not import a bug file from a sibling checkout" do
    Dir.mktmpdir do |tmp|
      stub_checkout(checkout(tmp, "elkjs*", %w[test-bug-mine.js]))
      checkout(tmp, "elkjs2", %w[test-bug-foreign.js])

      status, = Dir.chdir(tmp) { import(described_class.new) }

      expect(status).to be_nil
      expect(written_ids(tmp)).to eq(["elkjs_bug-mine"])
    end
  end
end
