# frozen_string_literal: true

require "spec_helper"
require "json"
require "logger"
require "stringio"

RSpec.describe "Layout constraints through Elkrb.layout" do
  include ConstraintGraphs

  let(:log) { StringIO.new }

  around do |example|
    previous = Elkrb.logger
    Elkrb.logger = Logger.new(log, level: Logger::WARN)
    example.run
  ensure
    Elkrb.logger = previous
  end

  describe "layer constraints" do
    let(:chain) do
      { id: "r",
        children: [node("a", layer: 2), node("b", layer: 0)],
        edges: [edge("e", "a", "b")] }
    end

    it "orders nodes by their constrained layer, against the edge" do
      nodes = by_id(laid_out(chain, "layered"))

      expect(nodes["a"].x).to be > nodes["b"].x
    end

    {
      "FIRST" => ->(n) { n["c"].x < n["b"].x },
      "FIRST_SEPARATE" => ->(n) { n["c"].x < n["a"].x },
      "LAST" => ->(n) { n["c"].x > n["a"].x },
      "LAST_SEPARATE" => ->(n) { n["c"].x > n["b"].x },
    }.each do |kind, expectation|
      it "honours layerConstraint #{kind} against the edges" do
        graph = {
          id: "r",
          children: [node("a"), node("b"), node_with_layer_kind("c", kind)],
          edges: [edge("e1", "a", "b"),
                  if kind.start_with?("FIRST")
                    edge("e2", "b",
                         "c")
                  else
                    edge("e2", "c", "a")
                  end],
        }

        expect(expectation.call(by_id(laid_out(graph, "layered")))).to be true
      end
    end

    it "keeps FIRST at the smallest and LAST at the largest layer coordinate" do
      # c has no edge: with components separated it would be packed beside
      # the others instead of taking the last layer.
      graph = {
        id: "r",
        layoutOptions: { "elk.separateConnectedComponents" => false },
        children: [
          node("a"), node("b"),
          node_with_layer_kind("c", "LAST"),
          node_with_layer_kind("d", "FIRST")
        ],
        edges: [edge("e1", "a", "b"), edge("e2", "d", "a"),
                edge("e3", "b", "d")],
      }
      xs = by_id(laid_out(graph, "layered")).transform_values(&:x)

      expect(xs["d"]).to eq(xs.values.min)
      expect(xs["c"]).to eq(xs.values.max)
    end
  end

  describe "scratch state" do
    it "writes no _constraint_ or _assigned_layer key into the output" do
      graph = {
        id: "r",
        children: [
          node("a", fixedPosition: true).merge(x: 500, y: 100),
          node("b", layer: 1),
          node("c", alignGroup: "g", alignDirection: "vertical"),
          node("d", alignGroup: "g", alignDirection: "vertical"),
        ],
        edges: [edge("e1", "a", "b")],
      }
      json = laid_out(graph, "layered").to_json

      expect(json).not_to match(/_constraint_|_assigned_layer/)
    end

    it "releases a fixed node when fixedPosition is false on re-fed output" do
      graph = { id: "r",
                children: [node("a", fixedPosition: true).merge(x: 500, y: 100),
                           node("b")] }
      fixed = by_id(laid_out(graph, "layered"))["a"]
      expect([fixed.x, fixed.y]).to eq([500, 100])

      graph[:children][0][:constraints] = { fixedPosition: false }
      released = by_id(laid_out(graph, "layered"))["a"]

      expect([released.x, released.y]).not_to eq([500, 100])
    end
  end

  describe "alignment" do
    it "keeps two aligned same-layer siblings from overlapping" do
      graph = {
        id: "r",
        children: [
          node("a"),
          node("b", alignGroup: "g", alignDirection: "vertical"),
          node("c", alignGroup: "g", alignDirection: "vertical"),
        ],
        edges: [edge("e1", "a", "b"), edge("e2", "a", "c")],
      }
      nodes = by_id(laid_out(graph, "layered"))

      expect(nodes["b"].x).to eq(nodes["c"].x)
      expect((nodes["b"].y - nodes["c"].y).abs).to be >= 60
    end

    it "averages only nodes that have a coordinate" do
      constraint = Elkrb::Layout::Constraints::AlignmentConstraint.new
      graph = Elkrb::Graph::Graph.new(id: "r")
      aligned = { align_group: "g", align_direction: "horizontal" }
      placed = Elkrb::Graph::Node.new(
        id: "p", width: 10, height: 10, x: 0, y: 40,
        constraints: Elkrb::Graph::NodeConstraints.new(**aligned)
      )
      unplaced = Elkrb::Graph::Node.new(
        id: "u", width: 10, height: 10,
        constraints: Elkrb::Graph::NodeConstraints.new(**aligned)
      )
      graph.children = [placed, unplaced]

      constraint.apply(graph)

      expect([placed.y, unplaced.y]).to eq([40.0, nil])
    end
  end

  describe "relative position" do
    let(:chain) do
      offset = { x: 0, y: 100 }
      { id: "r",
        children: [
          node("a"),
          node("c", relativeTo: "b", relativeOffset: offset),
          node("b", relativeTo: "a", relativeOffset: offset),
        ] }
    end

    it "resolves a chain in dependency order whatever the child order" do
      nodes = by_id(laid_out(chain, "box"))

      expect(nodes["b"].y).to eq(nodes["a"].y + 100)
      expect(nodes["c"].y).to eq(nodes["a"].y + 200)
      expect(log.string).not_to include("violation")
    end

    it "logs a dangling relativeTo exactly once, through Elkrb.logger" do
      graph = { id: "r",
                children: [node("a"),
                           node("b", relativeTo: "ghost",
                                     relativeOffset: { x: 10, y: 0 })] }

      expect { laid_out(graph, "box") }.not_to output.to_stderr
      expect(log.string.lines.grep(/ghost/).length).to eq(1)
    end
  end
end
