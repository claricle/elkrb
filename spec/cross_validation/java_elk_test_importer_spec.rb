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

  # `rel` may name a subdirectory, so each file's own parent is created
  # rather than only the repo root.
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
    Dir.mktmpdir do |tmp|
      stub_const("#{described_class}::TEST_MODELS_PATH",
                 models_repo(tmp, "models*", %w[mine.elkt]))
      models_repo(tmp, "models2", %w[foreign.elkt])

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error).to be_nil
      expect(written_ids(tmp)).to eq(["java_elk_mine"])
    end
  end

  # The id was the file's BASENAME, so every model called `same.elkt` in a
  # different directory produced the same id -- and the corpus runner then
  # wrote them all to one dump file. The relative path is what makes them
  # distinct.
  it "keeps equal basenames in different directories distinct" do
    Dir.mktmpdir do |tmp|
      stub_const(
        "#{described_class}::TEST_MODELS_PATH",
        models_repo(tmp, "models", %w[a/same.elkt b/same.elkt]),
      )

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error).to be_nil
      # contain_exactly, not eq: Dir.glob's enumeration order is not a
      # language guarantee, and order is not the property under test here.
      expect(written_ids(tmp))
        .to contain_exactly("java_elk_a%2Fsame", "java_elk_b%2Fsame")
    end
  end

  # Encoding the separator is only safe if it cannot collide with an id a
  # literal filename could already produce. The encoder escapes `%` as `%25`
  # too, so `a/same` and `a%2Fsame` stay two ids. A bare `%2F` substitution
  # maps BOTH to "a%2Fsame" -- measured, and it is what this example kills.
  it "does not collide a slash with a literal percent escape" do
    Dir.mktmpdir do |tmp|
      stub_const(
        "#{described_class}::TEST_MODELS_PATH",
        models_repo(tmp, "models", %w[a/same.elkt a%2Fsame.elkt]),
      )

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error).to be_nil
      expect(written_ids(tmp)).to contain_exactly(
        "java_elk_a%2Fsame",
        "java_elk_a%252Fsame",
      )
    end
  end

  # The importer's comment rules out `encode_www_form_component` because it
  # maps a space to "+", a URL-query semantic a filename does not have. That
  # sentence was true and unpinned: swapping the encoder left all the other
  # examples green, because no fixture name contained a space. This one names
  # a space so the choice of encoder is asserted rather than only explained.
  it "percent-encodes a space rather than turning it into a plus" do
    Dir.mktmpdir do |tmp|
      stub_const(
        "#{described_class}::TEST_MODELS_PATH",
        models_repo(tmp, "models", ["a b.elkt"]),
      )

      error = Dir.chdir(tmp) { import(described_class.new) }

      expect(error).to be_nil
      expect(written_ids(tmp)).to eq(["java_elk_a%20b"])
    end
  end

  # Percent-encoding EXPANDS, so escaping a name that was already near the
  # filesystem's per-component limit pushes the dump file past it. "界" is
  # 3 bytes and encodes to 9: a 242-byte source name imported and dumped fine
  # as a 251-byte "<id>.json" before this branch, and reached 725 bytes after
  # -- Errno::ENAMETOOLONG, raised by the corpus runner after it had already
  # claimed the output directory.
  #
  # The assertion is on the DUMP FILENAME's byte size, not on the id's, since
  # the limit applies to the name the runner actually writes.
  it "bounds the dump filename for a long name that encoding expands" do
    Dir.mktmpdir do |tmp|
      name = "界" * 79
      stub_const(
        "#{described_class}::TEST_MODELS_PATH",
        models_repo(tmp, "models", ["#{name}.elkt"]),
      )

      error = Dir.chdir(tmp) { import(described_class.new) }
      id = written_ids(tmp).first

      expect(error).to be_nil
      expect("#{id}.json".bytesize).to be <= 255
      # Readable head, so the dump is still identifiable, and every escape in
      # it is whole -- truncating the ENCODED text instead of the source would
      # leave a half escape like "%E7%95".
      expect(id).to start_with("java_elk_%E7%95%8C")
      expect(id.scan(/%.{0,2}/)).to all(match(/\A%[0-9A-F]{2}\z/))
    end
  end

  # The bound must not collapse two names into one dump file. Both of these
  # exceed the budget and share every byte of the readable prefix, so the
  # prefix alone cannot tell them apart -- only a digest over the WHOLE name
  # can. A truncating fix with no digest passes every other example here.
  it "keeps two over-long names that share a prefix distinct" do
    Dir.mktmpdir do |tmp|
      head = "界" * 79
      stub_const(
        "#{described_class}::TEST_MODELS_PATH",
        models_repo(tmp, "models", ["#{head}A.elkt", "#{head}B.elkt"]),
      )

      error = Dir.chdir(tmp) { import(described_class.new) }
      ids = written_ids(tmp)

      expect(error).to be_nil
      expect(ids.uniq.size).to eq(2)
    end
  end
end
