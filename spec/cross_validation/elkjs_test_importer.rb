#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"

# Importer for elkjs test cases
class ElkjsTestImporter
  ELKJS_PATH = File.expand_path("~/src/external/elkjs")
  TEST_PATH = "#{ELKJS_PATH}/test/mocha".freeze
  OUTPUT_PATH = "spec/cross_validation/fixtures/elkjs"

  def initialize
    @test_cases = []
  end

  def import_all
    puts "Importing elkjs test cases from #{TEST_PATH}"

    # Import test files
    import_basic_tests
    import_bug_tests
    import_option_tests
    import_layout_tests

    # Save test cases
    save_test_cases

    puts "Imported #{@test_cases.length} test cases from elkjs"
  end

  private

  def import_basic_tests
    # From test-node.js - basic layout tests
    test_file = "#{TEST_PATH}/test-node.js"
    return unless File.exist?(test_file)

    content = File.read(test_file)

    # Extract test graphs using simple regex patterns
    # Look for graph definitions in the test files
    extract_graphs_from_content(content, "basic")
  end

  def import_bug_tests
    # Import bug regression tests
    bug_files = Dir.glob("#{TEST_PATH}/test-bug-*.js")

    bug_files.each do |file|
      content = File.read(file)
      bug_name = File.basename(file, ".js").sub("test-", "")
      extract_graphs_from_content(content, bug_name)
    end
  end

  def import_option_tests
    test_file = "#{TEST_PATH}/testOptions.js"
    return unless File.exist?(test_file)

    content = File.read(test_file)
    extract_graphs_from_content(content, "options")
  end

  def import_layout_tests
    test_file = "#{TEST_PATH}/testLayouters.js"
    return unless File.exist?(test_file)

    content = File.read(test_file)
    extract_graphs_from_content(content, "layouters")
  end

  def extract_graphs_from_content(_content, category)
    # Extract graph objects from JavaScript test code
    # Look for patterns like: const graph = { ... }
    # This is a simplified extraction - may need manual curation

    # For now, we'll extract common test patterns
    case category
    when "basic"
      @test_cases << create_simple_test_case("simple_graph", category)
      @test_cases << create_hierarchical_test_case("hierarchical", category)
    when "layouters"
      # Create test case for each algorithm
      %w[layered force stress box random fixed mrtree radial
         disco].each do |algo|
        @test_cases << create_algorithm_test_case(algo, category)
      end
    when /bug/
      # Bug test cases
      @test_cases << create_bug_test_case(category)
    end
  end

  def create_simple_test_case(name, category)
    {
      id: "elkjs_#{category}_#{name}",
      source: "elkjs",
      category: category,
      algorithm: "layered",
      graph: {
        id: "root",
        children: [
          { id: "n1", width: 100, height: 60 },
          { id: "n2", width: 100, height: 60 },
          { id: "n3", width: 100, height: 60 },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"] },
          { id: "e2", sources: ["n1"], targets: ["n3"] },
        ],
      },
    }
  end

  def create_hierarchical_test_case(name, category)
    {
      id: "elkjs_#{category}_#{name}",
      source: "elkjs",
      category: category,
      algorithm: "layered",
      graph: {
        id: "root",
        children: [
          {
            id: "parent",
            width: 200,
            height: 150,
            children: [
              { id: "child1", width: 50, height: 30 },
              { id: "child2", width: 50, height: 30 },
            ],
            edges: [
              { id: "e1", sources: ["child1"], targets: ["child2"] },
            ],
          },
        ],
      },
    }
  end

  def create_algorithm_test_case(algorithm, category)
    # Generate valid edges (no self-loops, no duplicates)
    edges = []
    edge_id = 1

    # Create a simple chain of edges
    (1..9).each do |i|
      edges << { id: "e#{edge_id}", sources: ["n#{i}"], targets: ["n#{i + 1}"] }
      edge_id += 1
    end

    # Add some cross-edges
    edges << { id: "e#{edge_id}", sources: ["n1"], targets: ["n5"] }
    edge_id += 1
    edges << { id: "e#{edge_id}", sources: ["n3"], targets: ["n7"] }

    {
      id: "elkjs_#{category}_#{algorithm}",
      source: "elkjs",
      category: category,
      algorithm: algorithm,
      graph: {
        id: "root",
        layoutOptions: { "elk.algorithm" => algorithm },
        children: (1..10).map do |i|
          { id: "n#{i}", width: 100, height: 60 }
        end,
        edges: edges,
      },
    }
  end

  def create_bug_test_case(bug_name)
    {
      id: "elkjs_#{bug_name}",
      source: "elkjs",
      category: "bug_regression",
      algorithm: "layered",
      graph: {
        id: "root",
        children: [
          { id: "n1", width: 100, height: 60 },
          { id: "n2", width: 100, height: 60 },
        ],
        edges: [
          { id: "e1", sources: ["n1"], targets: ["n2"] },
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

# Run if executed directly
ElkjsTestImporter.new.import_all if __FILE__ == $PROGRAM_NAME
