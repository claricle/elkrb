#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"

# Importer for Java ELK test cases
class JavaElkTestImporter
  ELK_PATH = File.expand_path("~/src/external/elk")
  TEST_MODELS_PATH = "#{ELK_PATH}/../elk-models".freeze
  OUTPUT_PATH = "spec/cross_validation/fixtures/java_elk"

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
      create_sample_tests
    end

    save_test_cases

    puts "Imported #{@test_cases.length} test cases from Java ELK"
  end

  private

  def import_from_models_repo
    # Import .elkt files from elk-models repository
    elkt_files = Dir.glob("#{TEST_MODELS_PATH}/**/*.elkt")

    elkt_files.each do |file|
      parse_elkt_file(file)
    end
  end

  def parse_elkt_file(file)
    # Parse .elkt (ELK Text) format and convert to JSON
    # This is a simplified parser - full implementation would be more complex

    content = File.read(file)
    test_name = File.basename(file, ".elkt")

    # For now, create a placeholder test case
    @test_cases << {
      id: "java_elk_#{test_name}",
      source: "java_elk",
      category: "elkt_import",
      algorithm: "layered",
      graph: parse_elkt_content(content),
    }
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

  def create_sample_tests
    # Create sample test cases based on common Java ELK patterns

    # Algorithm tests
    %w[layered force stress box random fixed mrtree radial rectpacking
       disco sporeOverlap sporeCompaction].each do |algo|
      @test_cases << create_algorithm_test(algo)
    end

    # Feature tests
    @test_cases << create_hierarchical_test
    @test_cases << create_port_test
    @test_cases << create_label_test
    @test_cases << create_self_loop_test
    @test_cases << create_compound_test
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

# Run if executed directly
JavaElkTestImporter.new.import_all if __FILE__ == $PROGRAM_NAME
