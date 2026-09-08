#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "pathname"
require "uri"

# Importer for Java ELK test cases
class JavaElkTestImporter
  # Raised instead of calling `exit`. `import_all` is a plain Ruby method,
  # so a caller that requires this file gets an error it can rescue rather
  # than having its whole process killed. Only the script entry point at
  # the bottom of this file turns it into an exit status.
  class ImportError < StandardError; end

  ELK_PATH = File.expand_path("~/src/external/elk")
  TEST_MODELS_PATH = "#{ELK_PATH}/../elk-models".freeze
  OUTPUT_PATH = "spec/cross_validation/fixtures/java_elk"

  # Both SPOrE algorithms resolve fine -- AlgorithmRegistry.normalize_name
  # folds camelCase, so "sporeOverlap" reaches SporeOverlap -- and then
  # crash inside the algorithm itself on nil arithmetic. The marker has to
  # be generated here, not just hand-added to the committed fixture,
  # because save_test_cases overwrites that file wholesale: otherwise the
  # next regeneration reclassifies a tracked bug as a fresh regression and
  # the corpus dump starts exiting non-zero for it. It comes out when the
  # two algorithms stop crashing, not when the registry changes.
  EXPECTED_ERROR_ALGORITHMS = %w[sporeOverlap sporeCompaction].freeze

  # An id becomes a filename, so it is BOUNDED, not merely escaped.
  # Percent-encoding EXPANDS: "界" is 3 bytes and encodes to 9, so a
  # 242-byte source name that used to dump as a 251-byte "<id>.json" reached
  # 725 bytes and the write raised Errno::ENAMETOOLONG -- after the corpus
  # runner had already claimed the output directory.
  #
  # The budget is NOT 255 minus the dump name's own decoration. The name that
  # has to fit is the TEMPORARY one: CorpusRunner#write_file writes
  # ".#{basename}.#{Process.pid}.tmp" and renames it over the target, so the
  # longest name the filesystem ever sees is 6 bytes plus the pid's width
  # longer than the dump's -- the leading ".", the "." before the pid, and
  # ".tmp". Measured: ".x.json.12345.tmp".bytesize - "x.json".bytesize is 11.
  # Budgeting for the dump alone let a 247-byte
  # "java_elk_<id>.json" produce a 258-byte temp name and raise
  # Errno::ENAMETOOLONG anyway -- measured, and it is what these constants
  # exist to prevent.
  NAME_MAX_BYTES = 255
  ID_PREFIX = "java_elk_"
  DUMP_SUFFIX = ".json"
  # A fixed reservation, never Process.pid.to_s.bytesize. The ids are written
  # into imported_tests.json and read back by later runs, so a budget that
  # moved with the pid would give the same source name two different ids on
  # two different days. Ten digits covers any 32-bit pid, well past Linux's
  # highest configurable pid_max of 4194304.
  MAX_PID_DIGITS = 10
  # ".", then the dump name, then ".", the pid, and ".tmp".
  TEMP_NAME_OVERHEAD = 1 + 1 + MAX_PID_DIGITS + ".tmp".bytesize
  MAX_ID_BYTES = NAME_MAX_BYTES - ID_PREFIX.bytesize -
    DUMP_SUFFIX.bytesize - TEMP_NAME_OVERHEAD
  # Long enough that two different names colliding is not a real risk, short
  # enough to leave the readable prefix most of the budget. A collision would
  # not lose data in any case: CorpusRunner#refuse_duplicate_ids! raises on
  # two equal ids before anything is written.
  DIGEST_CHARS = 16
  # The separator between the readable prefix and the digest, and it must be
  # a byte the encoder can NEVER emit, or a shortened id collides with an
  # ordinary one. Measured: URI.encode_uri_component passes through exactly
  # `*-.0-9A-Z_a-z` and otherwise emits "%" plus two hex digits. `-` is in
  # that set, so with a `-` separator the ordinary source name
  # "界" * 24 + "-45445a6f319910a2" encoded to the SAME id as "界" * 79
  # shortened -- no SHA collision needed, and the corpus runner then refused
  # the whole corpus as duplicate. "+" is escaped to "%2B", so a literal "+"
  # in a source name can never reach the id as a bare "+".
  DIGEST_SEPARATOR = "+"

  SAMPLE_ALGORITHMS = %w[layered force stress box random fixed mrtree radial
                         rectpacking disco sporeOverlap sporeCompaction].freeze

  def initialize
    @test_cases = []
  end

  def import_all
    puts "Importing Java ELK test cases"

    # Check if elk-models repository exists
    if Dir.exist?(TEST_MODELS_PATH)
      import_from_models_repo
    else
      puts "elk-models repository not found at #{TEST_MODELS_PATH}"
      puts "Creating sample test cases based on Java ELK patterns"
      @test_cases.concat(sample_test_cases)
    end

    if @test_cases.empty?
      raise ImportError,
            "Java ELK import found 0 test cases - refusing to overwrite " \
            "#{OUTPUT_PATH}/imported_tests.json"
    end

    save_test_cases

    puts "Imported #{@test_cases.length} test cases from Java ELK"
  end

  # The fallback corpus used when the elk-models checkout is missing, which
  # is also exactly what is committed under fixtures/java_elk. Pure and
  # filesystem-free so a spec can hold the committed file to it without
  # letting a test run write into spec/.
  def sample_test_cases
    SAMPLE_ALGORITHMS.map { |algorithm| create_algorithm_test(algorithm) } +
      [create_hierarchical_test, create_port_test, create_label_test,
       create_self_loop_test, create_compound_test]
  end

  private

  # `base:` scopes the glob to TEST_MODELS_PATH, which is taken literally.
  # Joining it into the pattern let a glob metacharacter in the checkout
  # path be interpreted rather than matched, so a sibling checkout's models
  # were imported into the committed fixture.
  def import_from_models_repo
    names = Dir.glob("**/*.elkt", base: TEST_MODELS_PATH)
    elkt_files = names.map { |name| File.join(TEST_MODELS_PATH, name) }

    elkt_files.each do |file|
      parse_elkt_file(file)
    end
  end

  def parse_elkt_file(file)
    # Parse .elkt (ELK Text) format and convert to JSON
    # This is a simplified parser - full implementation would be more complex

    content = File.read(file)
    relative = Pathname(file).relative_path_from(Pathname(TEST_MODELS_PATH))
    test_name = relative.sub_ext("").each_filename.to_a.join("/")

    # For now, create a placeholder test case
    @test_cases << {
      # Keep the relative path so two models with the same basename remain
      # distinct. Percent-encoding turns separators into filename-safe text
      # and escapes `%` itself, so `a/same` cannot collide with a literal
      # `a%2Fsame` name. Not the www-form encoder: that maps a space to "+",
      # a URL-query semantic this is not.
      id: "java_elk_#{bounded_id(test_name)}",
      source: "java_elk",
      category: "elkt_import",
      algorithm: "layered",
      graph: parse_elkt_content(content),
    }
  end

  # The encoded name when it fits, and a readable prefix plus a digest of the
  # WHOLE name when it does not -- so two long names sharing a prefix stay
  # distinct.
  def bounded_id(test_name)
    encoded = URI.encode_uri_component(test_name)
    return encoded if encoded.bytesize <= MAX_ID_BYTES

    digest = Digest::SHA256.hexdigest(test_name)[0, DIGEST_CHARS]
    budget = MAX_ID_BYTES - digest.bytesize - DIGEST_SEPARATOR.bytesize
    "#{encoded_prefix(test_name, budget)}#{DIGEST_SEPARATOR}#{digest}"
  end

  # Encodes one CHARACTER at a time and stops before the budget is exceeded,
  # rather than truncating the already-encoded string: cutting "%E7%95%8C" at
  # a byte boundary yields "%E7%95", a different and invalid escape sequence.
  def encoded_prefix(test_name, budget)
    prefix = +""
    test_name.each_char do |char|
      piece = URI.encode_uri_component(char)
      break if prefix.bytesize + piece.bytesize > budget

      prefix << piece
    end
    prefix
  end

  def parse_elkt_content(_content)
    # Simplified ELKT parser
    # Real implementation would parse the full ELKT syntax
    {
      id: "root",
      children: [],
      edges: [],
    }
  end

  def create_algorithm_test(algorithm)
    # Generate valid edges (no self-loops, no duplicates)
    edges = []
    edge_id = 1

    # Create a simple chain of edges
    (1..19).each do |i|
      edges << { id: "e#{edge_id}", sources: ["n#{i}"], targets: ["n#{i + 1}"] }
      edge_id += 1
    end

    # Add some cross-edges for more complexity
    edges << { id: "e#{edge_id}", sources: ["n1"], targets: ["n10"] }
    edge_id += 1
    edges << { id: "e#{edge_id}", sources: ["n5"], targets: ["n15"] }
    edge_id += 1
    edges << { id: "e#{edge_id}", sources: ["n2"], targets: ["n12"] }

    {
      id: "java_elk_#{algorithm}",
      source: "java_elk",
      category: "algorithm",
      algorithm: algorithm,
      **expectation_for(algorithm),
      graph: {
        id: "root",
        layoutOptions: { "elk.algorithm" => algorithm },
        children: (1..20).map do |i|
          { id: "n#{i}", width: 100, height: 60 }
        end,
        edges: edges,
      },
    }
  end

  def expectation_for(algorithm)
    return {} unless EXPECTED_ERROR_ALGORITHMS.include?(algorithm)

    { expect: "error" }
  end

  def create_hierarchical_test
    {
      id: "java_elk_hierarchical",
      source: "java_elk",
      category: "hierarchical",
      algorithm: "layered",
      graph: {
        id: "root",
        children: [
          {
            id: "p1",
            width: 300,
            height: 200,
            children: [
              { id: "c1", width: 80, height: 50 },
              { id: "c2", width: 80, height: 50 },
            ],
            edges: [
              { id: "e1", sources: ["c1"], targets: ["c2"] },
            ],
          },
        ],
      },
    }
  end

  def create_port_test
    {
      id: "java_elk_ports",
      source: "java_elk",
      category: "ports",
      algorithm: "layered",
      graph: {
        id: "root",
        children: [
          {
            id: "n1",
            width: 100,
            height: 60,
            ports: [
              { id: "p1", x: 100, y: 30 },
              { id: "p2", x: 0, y: 30 },
            ],
          },
          {
            id: "n2",
            width: 100,
            height: 60,
            ports: [
              { id: "p3", x: 0, y: 30 },
            ],
          },
        ],
        edges: [
          { id: "e1", sources: ["p2"], targets: ["p3"] },
        ],
      },
    }
  end

  def create_label_test
    {
      id: "java_elk_labels",
      source: "java_elk",
      category: "labels",
      algorithm: "layered",
      graph: {
        id: "root",
        children: [
          {
            id: "n1",
            width: 100,
            height: 60,
            labels: [
              { id: "l1", text: "Node 1", width: 50, height: 15 },
            ],
          },
        ],
      },
    }
  end

  def create_self_loop_test
    {
      id: "java_elk_self_loops",
      source: "java_elk",
      category: "self_loops",
      algorithm: "layered",
      graph: {
        id: "root",
        children: [
          { id: "n1", width: 100, height: 60 },
          { id: "n2", width: 100, height: 60 },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n1"] },
          { id: "e2", sources: ["n1"], targets: ["n2"] },
        ],
      },
    }
  end

  def create_compound_test
    {
      id: "java_elk_compound",
      source: "java_elk",
      category: "compound",
      algorithm: "layered",
      graph: {
        id: "root",
        children: [
          {
            id: "p1",
            width: 400,
            height: 300,
            children: [
              {
                id: "p2",
                width: 150,
                height: 120,
                children: [
                  { id: "c1", width: 60, height: 40 },
                  { id: "c2", width: 60, height: 40 },
                ],
                edges: [
                  { id: "e1", sources: ["c1"], targets: ["c2"] },
                ],
              },
              { id: "n1", width: 80, height: 50 },
            ],
          },
        ],
      },
    }
  end

  def save_test_cases
    FileUtils.mkdir_p(OUTPUT_PATH)

    File.write(
      "#{OUTPUT_PATH}/imported_tests.json",
      JSON.pretty_generate(@test_cases),
    )
  end
end

# Run if executed directly. This is the ONLY place that decides an exit
# status: the importer raises, so `rake validate:import_java_elk` still
# fails loudly while a Ruby caller keeps control of its own process.
if __FILE__ == $PROGRAM_NAME
  begin
    JavaElkTestImporter.new.import_all
  rescue JavaElkTestImporter::ImportError => e
    warn e.message
    exit 1
  end
end
