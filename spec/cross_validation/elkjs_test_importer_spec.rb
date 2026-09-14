# frozen_string_literal: true

require "spec_helper"
require "support/filename_probe"
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
  include FilenameProbe

  # Returns the ImportError import_all raised, or nil when it ran to the
  # end. import_all used to call `exit` itself, which killed any Ruby
  # caller instead of handing back an error; only the script entry point
  # turns the error into an exit status now. Progress chatter is captured
  # so it does not reach the suite's own output.
  def import(importer)
    stdout = $stdout
    $stdout = StringIO.new
    begin
      importer.import_all
      nil
    rescue described_class::ImportError => e
      e
    end
  ensure
    $stdout = stdout
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

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error.message).to include("refusing to overwrite")
      expect(written_ids(tmp)).to be_nil
    end
  end

  it "refuses to overwrite the fixture when the checkout holds no tests" do
    Dir.mktmpdir do |tmp|
      stub_checkout(checkout(tmp, "elkjs", []))

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error.message).to include("refusing to overwrite")
      expect(written_ids(tmp)).to be_nil
    end
  end

  # TEST_PATH is built from ELKJS_DIR, so the checkout path a caller chose
  # reaches the bug-file glob. Joining it into the pattern let a `*` in it
  # match a sibling checkout too, and the foreign case landed in the
  # committed fixture.
  it "does not import a bug file from a sibling checkout" do
    name = "elkjs*"
    skip_unless_creatable(name)

    Dir.mktmpdir do |tmp|
      stub_checkout(checkout(tmp, name, %w[test-bug-mine.js]))
      checkout(tmp, "elkjs2", %w[test-bug-foreign.js])

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error).to be_nil
      expect(written_ids(tmp)).to eq(["elkjs_bug-mine"])
    end
  end

  # `[` and `]` are legal in a Win32 filename, so this example runs on the
  # Windows leg where the `elkjs*` one above is skipped. Without it the
  # importer's only escape guarantee would have zero coverage there.
  it "does not import a bug file when the checkout name holds a bracket" do
    Dir.mktmpdir do |tmp|
      stub_checkout(checkout(tmp, "elkjs[x]", %w[test-bug-mine.js]))
      checkout(tmp, "elkjsx", %w[test-bug-foreign.js])

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error).to be_nil
      expect(written_ids(tmp)).to eq(["elkjs_bug-mine"])
    end
  end
end
