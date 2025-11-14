#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

# Generates test graphs for benchmarking
class TestGraphGenerator
  def generate_all
    graphs = {
      small_simple: generate_small_simple,
      medium_hierarchical: generate_medium_hierarchical,
      large_complex: generate_large_complex,
      dense_network: generate_dense_network,
    }

    File.write("benchmarks/fixtures/graphs.json", JSON.pretty_generate(graphs))
    puts "Generated test graphs: benchmarks/fixtures/graphs.json"
  end

  private

  def generate_small_simple
    {
      description: "Small graph: 10 nodes, 15 edges",
      graph: {
        id: "small_simple",
        children: (1..10).map do |i|
          {
            id: "n#{i}",
            width: 100,
            height: 60,
          }
        end,
        edges: generate_random_edges(10, 15, "small_simple"),
      },
    }
  end

  def generate_medium_hierarchical
    []
    []
    node_id = 1

    # Level 1: Root container
    "container_0"
    root_children = []

    # Level 2: 5 containers, each with 10 nodes
    5.times do |i|
      container_id = "container_#{i + 1}"
      container_children = []

      10.times do |_j|
        node = {
          id: "n#{node_id}",
          width: 80,
          height: 50,
        }
        container_children << node
        node_id += 1
      end

      root_children << {
        id: container_id,
        children: container_children,
      }
    end

    # Generate edges between nodes
    edges = generate_random_edges(50, 75, "medium_hierarchical")

    {
      description: "Medium hierarchical: 50 nodes, 75 edges, 3 levels",
      graph: {
        id: "medium_hierarchical",
        children: root_children,
        edges: edges,
      },
    }
  end

  def generate_large_complex
    nodes = (1..200).map do |i|
      {
        id: "n#{i}",
        width: 100,
        height: 60,
      }
    end

    edges = generate_random_edges(200, 400, "large_complex")

    {
      description: "Large complex: 200 nodes, 400 edges",
      graph: {
        id: "large_complex",
        children: nodes,
        edges: edges,
      },
    }
  end

  def generate_dense_network
    nodes = (1..100).map do |i|
      {
        id: "n#{i}",
        width: 80,
        height: 50,
      }
    end

    edges = generate_random_edges(100, 500, "dense_network")

    {
      description: "Dense network: 100 nodes, 500 edges",
      graph: {
        id: "dense_network",
        children: nodes,
        edges: edges,
      },
    }
  end

  def generate_random_edges(node_count, edge_count, prefix)
    edges = []
    used_pairs = Set.new

    edge_count.times do |i|
      loop do
        source = "n#{rand(1..node_count)}"
        target = "n#{rand(1..node_count)}"
        pair = "#{source}-#{target}"

        next if source == target
        next if used_pairs.include?(pair)

        used_pairs.add(pair)
        edges << {
          id: "#{prefix}_e#{i + 1}",
          sources: [source],
          targets: [target],
        }
        break
      end
    end

    edges
  end
end

# Generate graphs when run directly
if __FILE__ == $PROGRAM_NAME
  TestGraphGenerator.new.generate_all
end
