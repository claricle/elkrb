# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../support/importer_spec_helpers"
require_relative "java_elk_test_importer"

RSpec.describe JavaElkTestImporter do
  include ImporterSpecHelpers

  def committed_fixture
    path = File.expand_path("fixtures/java_elk/imported_tests.json", __dir__)
    File.read(path)
  end

  def models_repo(parent, name, files)
    dir = File.join(parent, name)
    FileUtils.mkdir_p(dir)
    files.each do |rel|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "")
    end
    dir
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

  it "keeps equal basenames in different directories distinct" do
    Dir.mktmpdir do |tmp|
      stub_const(
        "#{described_class}::TEST_MODELS_PATH",
        models_repo(tmp, "models", %w[a/same.elkt b/same.elkt]),
      )

      status, = Dir.chdir(tmp) { import(described_class.new) }

      expect(status).to be_nil
      # contain_exactly, not eq: Dir.glob's enumeration order is not a
      # language guarantee, and order is not the property under test here.
      expect(written_ids(tmp))
        .to contain_exactly("java_elk_a%2Fsame", "java_elk_b%2Fsame")
    end
  end

  it "does not collide a slash with a literal percent escape" do
    Dir.mktmpdir do |tmp|
      stub_const(
        "#{described_class}::TEST_MODELS_PATH",
        models_repo(tmp, "models", %w[a/same.elkt a%2Fsame.elkt]),
      )

      status, = Dir.chdir(tmp) { import(described_class.new) }

      expect(status).to be_nil
      ids = written_ids(tmp)
      expect(ids).to contain_exactly(
        "java_elk_a%2Fsame",
        "java_elk_a%252Fsame",
      )
    end
  end
end
