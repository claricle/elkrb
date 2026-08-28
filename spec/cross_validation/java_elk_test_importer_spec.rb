# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "java_elk_test_importer"

RSpec.describe JavaElkTestImporter do
  def committed_fixture
    path = File.expand_path("fixtures/java_elk/imported_tests.json", __dir__)
    File.read(path)
  end

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

      status, stderr = Dir.chdir(tmp) { import(described_class.new) }

      expect(status).to eq(1)
      expect(stderr).to include("refusing to overwrite")
      expect(written_ids(tmp)).to be_nil
    end
  end

  # Joining TEST_MODELS_PATH into the pattern let a glob metacharacter in
  # the checkout path be interpreted rather than matched, so a sibling
  # checkout's models were written into the committed fixture.
  it "does not import a model from a sibling checkout" do
    Dir.mktmpdir do |tmp|
      stub_const("#{described_class}::TEST_MODELS_PATH",
                 models_repo(tmp, "models*", %w[mine.elkt]))
      models_repo(tmp, "models2", %w[foreign.elkt])

      status, = Dir.chdir(tmp) { import(described_class.new) }

      expect(status).to be_nil
      expect(written_ids(tmp)).to eq(["java_elk_mine"])
    end
  end
end
