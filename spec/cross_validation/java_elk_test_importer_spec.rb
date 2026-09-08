# frozen_string_literal: true

require "spec_helper"
require "support/filename_probe"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "java_elk_test_importer"

RSpec.describe JavaElkTestImporter do
  include FilenameProbe

  def committed_fixture
    path = File.expand_path("fixtures/java_elk/imported_tests.json", __dir__)
    File.read(path)
  end

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

  def models_repo(parent, name, files)
    dir = File.join(parent, name)
    FileUtils.mkdir_p(dir)
    files.each { |rel| File.write(File.join(dir, rel), "") }
    dir
  end

  def written_ids(cwd)
    path = File.join(cwd, described_class::OUTPUT_PATH, "imported_tests.json")
    return nil unless File.exist?(path)

    JSON.parse(File.read(path)).map { |kase| kase["id"] }
  end

  # save_test_cases rewrites imported_tests.json wholesale, so anything
  # hand-added to that file is gone after the next
  # `rake validate:import_java_elk` -- including the "expect": "error"
  # markers the corpus reads to tell a tracked bug from a fresh regression.
  # Holding the committed file to what a regeneration produces is the only
  # thing that stops the two drifting apart silently.
  #
  # The generator is called directly rather than through import_all, which
  # would write over the tracked fixture from a test run.
  it "generates the committed fixture byte for byte" do
    generated = JSON.pretty_generate(described_class.new.sample_test_cases)

    expect(generated).to eq(committed_fixture)
  end

  it "marks the two SPOrE cases as expected errors" do
    cases = described_class.new.sample_test_cases
    by_id = cases.to_h { |kase| [kase[:id], kase] }

    expect(by_id["java_elk_sporeOverlap"][:expect]).to eq("error")
    expect(by_id["java_elk_sporeCompaction"][:expect]).to eq("error")
    expect(by_id["java_elk_layered"]).not_to have_key(:expect)
  end

  # A models checkout that exists but yields nothing -- an interrupted
  # clone, a sparse checkout, a `mkdir -p` ahead of cloning -- used to
  # write an empty array over the tracked 17-case fixture. No
  # metacharacter needed; an ordinary path did it.
  it "refuses to overwrite the fixture when the models repo holds no models" do
    Dir.mktmpdir do |tmp|
      stub_const("#{described_class}::TEST_MODELS_PATH",
                 models_repo(tmp, "elk-models", []))

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error.message).to include("refusing to overwrite")
      expect(written_ids(tmp)).to be_nil
    end
  end

  # Joining TEST_MODELS_PATH into the pattern let a glob metacharacter in
  # the checkout path be interpreted rather than matched, so a sibling
  # checkout's models were written into the committed fixture.
  it "does not import a model from a sibling checkout" do
    name = "models*"
    skip_unless_creatable(name)

    Dir.mktmpdir do |tmp|
      stub_const("#{described_class}::TEST_MODELS_PATH",
                 models_repo(tmp, name, %w[mine.elkt]))
      models_repo(tmp, "models2", %w[foreign.elkt])

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error).to be_nil
      expect(written_ids(tmp)).to eq(["java_elk_mine"])
    end
  end

  # `[` and `]` are legal in a Win32 filename, so this example runs on the
  # Windows leg where the `models*` one above is skipped. Without it the
  # importer's only escape guarantee would have zero coverage there.
  it "does not import a model when the checkout name holds a bracket" do
    Dir.mktmpdir do |tmp|
      stub_const("#{described_class}::TEST_MODELS_PATH",
                 models_repo(tmp, "models[x]", %w[mine.elkt]))
      models_repo(tmp, "modelsx", %w[foreign.elkt])

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error).to be_nil
      expect(written_ids(tmp)).to eq(["java_elk_mine"])
    end
  end
end
