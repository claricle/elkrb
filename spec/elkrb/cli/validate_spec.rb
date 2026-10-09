# frozen_string_literal: true

require "spec_helper"
require "support/cli_runner"
require "json"
require "tmpdir"

RSpec.describe "elkrb validate S20" do
  include CliRunner

  def validate_document(document, *options)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "graph.json")
      File.write(path, JSON.generate(document))
      return run_elkrb("validate", path, *options)
    end
  end

  it "accepts strict edges that reference ports" do
    path = File.join(CliRunner::ROOT,
                     "spec/fixtures/elkjs_bug7_complex.json")

    stdout, stderr, status = run_elkrb("validate", path, "--strict")

    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("is valid")
    expect(stderr).to eq("")
  end

  it "rejects the corpus graph when node IDs are duplicated" do
    fixture = File.join(CliRunner::ROOT,
                        "spec/fixtures/corpus/duplicate_ids.json")
    graph = JSON.parse(File.read(fixture)).fetch("graph")

    stdout, stderr, status = validate_document(graph)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to eq("")
    expect(stderr).to include("duplicate id: a")
  end

  it "detects duplicate IDs across nodes, ports, and edges" do
    graph = {
      id: "root",
      children: [{ id: "shared", ports: [{ id: "shared" }] }],
      edges: [{ id: "shared", sources: ["shared"], targets: ["shared"] }],
    }

    _stdout, stderr, status = validate_document(graph)

    expect(status.exitstatus).to eq(1)
    expect(stderr.scan("duplicate id: shared").length).to eq(2)
  end

  it "rejects a dangling endpoint on an edge nested in a compound node" do
    graph = {
      id: "root",
      children: [
        {
          id: "a", width: 50, height: 30,
          children: [{ id: "a1", width: 20, height: 20 }],
          edges: [{ id: "nested", sources: ["a1"], targets: ["missing"] }]
        },
      ],
      edges: [],
    }

    _stdout, stderr, status = validate_document(graph)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include(
      "children[0].edges[0]: Edge 'nested' references unknown target " \
      "node or port 'missing'",
    )
  end

  it "checks dangling endpoints without --strict" do
    graph = {
      id: "root",
      children: [{ id: "a", width: 10, height: 10 }],
      edges: [{ id: "e", sources: ["a"], targets: ["missing"] }],
    }

    _stdout, stderr, status = validate_document(graph)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("unknown target node or port 'missing'")
  end

  it "validates 10,000 nodes and 20,000 edges in under two seconds" do
    node_count = 10_000
    graph = {
      id: "root",
      children: Array.new(node_count) do |index|
        { id: "n#{index}", width: 1, height: 1 }
      end,
      edges: Array.new(20_000) do |index|
        {
          id: "e#{index}",
          sources: ["n#{index % node_count}"],
          targets: ["n#{((index * 7) + 1) % node_count}"],
        }
      end,
    }

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _stdout, stderr, status = validate_document(graph)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    expect(status.exitstatus).to eq(0), stderr
    expect(elapsed).to be < 2
  end

  {
    "Graph must be a Hash" => [],
    "children[0]: Node must be a Hash" =>
      { id: "root", children: [false], edges: [] },
    "edges[0]: Edge must be a Hash" =>
      { id: "root", children: [], edges: [false] },
    "children[0].ports[0]: Port must be a Hash" => {
      id: "root", children: [{ id: "a", ports: [false] }], edges: []
    },
  }.each do |message, document|
    it "reports #{message}" do
      stdout, stderr, status = validate_document(document)

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq("")
      expect(stderr).to include(message)
    end
  end

  it "reports scalar endpoint collections without coercing them" do
    graph = {
      id: "root", children: [],
      edges: [{ id: "e", sources: "a", targets: "b" }]
    }

    _stdout, stderr, status = validate_document(graph)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include(
      "Edge 'e' sources must be an array",
      "Edge 'e' targets must be an array",
    )
  end

  it "reports a non-Hash layoutOptions value in strict mode" do
    graph = { id: "root", children: [], edges: [], layoutOptions: "layered" }

    _stdout, stderr, status = validate_document(graph, "--strict")

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("layoutOptions must be a Hash")
  end

  it "validates the raw document without coercing invalid dimensions" do
    graph = {
      id: "root",
      children: [{ id: "a", width: "wide", height: 10 }],
      edges: [],
    }

    _stdout, stderr, status = validate_document(graph, "--strict")

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("invalid width: wide")
    expect(stderr).not_to include("invalid width: 0.0")
  end
end
