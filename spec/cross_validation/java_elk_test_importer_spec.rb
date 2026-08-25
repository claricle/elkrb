# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "java_elk_test_importer"

RSpec.describe JavaElkTestImporter do
  def committed_fixture
    File.read(File.expand_path("fixtures/java_elk/imported_tests.json", __dir__))
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

  it "marks the algorithms the registry cannot resolve as expected errors" do
    by_id = described_class.new.sample_test_cases.to_h { |kase| [kase[:id], kase] }

    expect(by_id["java_elk_sporeOverlap"][:expect]).to eq("error")
    expect(by_id["java_elk_sporeCompaction"][:expect]).to eq("error")
    expect(by_id["java_elk_layered"]).not_to have_key(:expect)
  end
end
