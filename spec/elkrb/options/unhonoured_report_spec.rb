# frozen_string_literal: true

require "spec_helper"

# Strict mode raises, and default mode warns, for a key the algorithm laying
# out the element does not read. These examples go through Elkrb.layout, the
# only caller that tells the report which algorithms are registered.
RSpec.describe Elkrb::Options::UnhonouredReport do
  node_node = "elk.spacing.nodeNode"
  # registry_spec ("status agrees with what layout reads") holds these to
  # what layout does and to the registry's readers.
  readers = %w[box layered mrtree random rectpacking topdownpacking vertiflex]
  algorithms = Elkrb::Layout::AlgorithmRegistry.available_algorithms
  unhonoured = /strict mode.*#{Regexp.escape(node_node)} \(partial/

  let(:warnings) { StringIO.new }

  around do |example|
    previous = Elkrb.logger
    Elkrb.logger = Logger.new(warnings, level: Logger::WARN)
    example.run
  ensure
    Elkrb.logger = previous
  end

  describe "elk.spacing.nodeNode, which only some algorithms read" do
    [
      [:root, node_node], [:root, "spacing_node_node"],
      [:call, node_node], [:call, "spacing_node_node"],
      %i[call spacing_node_node], [:compound, node_node]
    ].each do |kind, key|
      algorithms.each do |algorithm|
        reads = readers.include?(algorithm)
        it "#{reads ? 'accepts' : 'refuses'} #{key.inspect} in the #{kind} " \
           "options under #{algorithm}" do
          graph, call = option_carried(kind, key, 30)
          strictly = { algorithm: algorithm, strict: true }.merge(call)

          if reads
            expect { Elkrb.layout(graph, strictly) }.not_to raise_error
          else
            expect { Elkrb.layout(graph, strictly) }
              .to raise_error(Elkrb::Error, unhonoured)
          end
        end
      end
    end
  end

  describe "partial keys" do
    partial_keys = {
      "elk.direction" => ["RIGHT", %w[layered mrtree]],
      "elk.hierarchyHandling" => ["INCLUDE_CHILDREN", []],
    }
    partial_keys.each do |key, (value, key_readers)|
      readers.each do |algorithm|
        reads = key_readers.include?(algorithm)
        it "#{reads ? 'accepts' : 'refuses'} #{key} under #{algorithm}" do
          graph, = option_carried(:root, key, value)

          if reads
            expect do
              Elkrb.layout(graph, algorithm: algorithm, strict: true)
            end.not_to raise_error
          else
            expect { Elkrb.layout(graph, algorithm: algorithm, strict: true) }
              .to raise_error(Elkrb::Error, /#{Regexp.escape(key)} \(partial/)
          end
        end
      end
    end
  end

  describe "the algorithm that lays out the element carrying the key" do
    edge_cases = [
      ["fixed", {}, { "elk.bendPoints" => "(10,20; 30,40)" }],
      ["box", {}, { "elk.edgeRouting" => "ORTHOGONAL" }],
      ["box", { "elk.edgeRouting" => "SPLINES" },
       { "elk.spline.curvature" => 0.9 }],
    ]
    edge_cases.each do |algorithm, root_options, edge_options|
      keys = edge_options.keys.join(", ")

      it "accepts #{keys} on an edge under #{algorithm}" do
        graph = positioned_graph(
          layout_options: root_options,
          edge: { layoutOptions: edge_options },
        )

        expect { Elkrb.layout(graph, algorithm: algorithm, strict: true) }
          .not_to raise_error
      end
    end

    it "accepts self-loop side on an actual loop under box" do
      graph = positioned_graph(
        edge: { layoutOptions: { "elk.selfLoopSide" => "WEST" } },
      )
      graph.edges.first.targets = ["a"]

      expect { Elkrb.layout(graph, algorithm: "box", strict: true) }
        .not_to raise_error
    end

    it "refuses edge routing on an edge under fixed" do
      graph = positioned_graph(
        edge: { layoutOptions: { "elk.edgeRouting" => "ORTHOGONAL" } },
      )

      expect { Elkrb.layout(graph, algorithm: "fixed", strict: true) }
        .to raise_error(Elkrb::Error, /elk\.edgeRouting \(partial/)
    end

    let(:nested_edge_graph) do
      lambda do |own_algorithm, edge_options|
        Elkrb::Graph::Graph.from_json(
          {
            id: "root",
            children: [{
              id: "compound",
              layoutOptions: { "elk.algorithm" => own_algorithm },
              children: positioned_nodes("inner-"),
              edges: [{
                id: "inner-edge", sources: ["inner-a"], targets: ["inner-b"],
                layoutOptions: edge_options
              }],
            }],
          }.to_json,
        )
      end
    end

    [
      ["fixed", "box", { "elk.edgeRouting" => "ORTHOGONAL" }, false],
      ["box", "fixed", { "elk.bendPoints" => "(10,20; 30,40)" }, false],
      ["box", "fixed", { "elk.edgeRouting" => "ORTHOGONAL" }, true],
    ].each do |root, own, options, raises|
      it "judges nested #{options.keys.first} by #{own} under #{root}" do
        graph = nested_edge_graph.call(own, options)
        operation = -> { Elkrb.layout(graph, algorithm: root, strict: true) }

        if raises
          expect(&operation).to raise_error(Elkrb::Error, /partial/)
        else
          expect(&operation).not_to raise_error
        end
      end
    end

    it "also treats a compound as a node routed by its enclosing algorithm" do
      compound = {
        id: "compound",
        layoutOptions: {
          "elk.algorithm" => "fixed", "elk.selfLoopSide" => "WEST"
        },
        children: positioned_nodes("inner-"),
      }
      graph = Elkrb::Graph::Graph.from_json(
        {
          id: "root", children: [compound],
          edges: [{
            id: "loop", sources: ["compound"], targets: ["compound"]
          }]
        }.to_json,
      )

      expect { Elkrb.layout(graph, algorithm: "box", strict: true) }
        .not_to raise_error
    end

    # [root algorithm, the compound's own algorithm, raises?]
    [
      ["force", "layered", false],
      ["layered", "force", true],
      ["layered", nil, false],
      ["force", nil, true],
      ["layered", "Layered", false],
      ["force", "org.eclipse.elk.layered", false],
      ["force", "nonesuch", true],
      ["layered", "nonesuch", :missing_algorithm],
    ].each do |root, own, raises|
      it "#{raises ? 'refuses' : 'accepts'} a compound's key under root " \
         "#{root}, compound #{own.inspect}" do
        compound = { layoutOptions: { node_node => 30 } }
        compound[:layoutOptions]["elk.algorithm"] = own if own
        graph = positioned_graph(compound: compound)
        strictly = { algorithm: root, strict: true }

        if raises == :missing_algorithm
          expect { Elkrb.layout(graph, strictly) }
            .to raise_error(Elkrb::AlgorithmNotFoundError, /nonesuch/)
        elsif raises
          expect { Elkrb.layout(graph, strictly) }
            .to raise_error(Elkrb::Error, unhonoured)
        else
          expect { Elkrb.layout(graph, strictly) }.not_to raise_error
        end
      end
    end

    # [algorithm pinned in the root's layoutOptions, call algorithm, raises?]
    [["force", nil, true], ["layered", "force", false]]
      .each do |pinned, called, raises|
      it "judges a root pinning #{pinned} with call algorithm " \
         "#{called.inspect} by the pin" do
        graph = positioned_graph(
          layout_options: { "elk.algorithm" => pinned, node_node => 30 },
        )
        strictly = { algorithm: called, strict: true }.compact

        if raises
          expect { Elkrb.layout(graph, strictly) }
            .to raise_error(Elkrb::Error, unhonoured)
        else
          expect { Elkrb.layout(graph, strictly) }.not_to raise_error
        end
      end
    end

    %w[algorithm elk.algorithm org.eclipse.elk.algorithm].each do |spelling|
      it "reads a compound's own algorithm spelled #{spelling}" do
        own = { spelling => "layered", node_node => 30 }
        graph = positioned_graph(compound: { layoutOptions: own })

        expect { Elkrb.layout(graph, algorithm: "force", strict: true) }
          .not_to raise_error
      end
    end

    # [root, middle compound, raises?]: the inner compound names no algorithm
    # and carries the key, so it is laid out by the middle one's.
    [["force", "layered", false], ["layered", "force", true]]
      .each do |root, middle, raises|
      it "lays out an inner compound by its parent's, #{root} > #{middle}" do
        inner = { id: "inner", layoutOptions: { node_node => 30 },
                  children: positioned_nodes("in-") }
        mid = { id: "mid", layoutOptions: { "elk.algorithm" => middle },
                children: [inner] }
        graph = Elkrb::Graph::Graph.from_json(
          { id: "root", children: [mid] }.to_json,
        )
        strictly = { algorithm: root, strict: true }

        if raises
          expect { Elkrb.layout(graph, strictly) }
            .to raise_error(Elkrb::Error, unhonoured)
        else
          expect { Elkrb.layout(graph, strictly) }.not_to raise_error
        end
      end
    end

    it "judges a root with no children by the algorithm that lays it out" do
      graph = option_graph({ node_node => 30 })

      expect { Elkrb.layout(graph, algorithm: "layered", strict: true) }
        .not_to raise_error
    end

    # One compound object under two parents is laid out once per parent, by
    # that parent's algorithm, whichever parent comes first.
    [%w[layered force], %w[force layered]].each do |first, second|
      it "refuses a shared compound's key when #{second} lays it out " \
         "beside #{first}" do
        graph = shared_compound_graph(first, second, node_node)

        expect { Elkrb.layout(graph, algorithm: "box", strict: true) }
          .to raise_error(Elkrb::Error, unhonoured)
      end
    end

    it "accepts the root's key under the algorithm spelled any way" do
      %w[Layered org.eclipse.elk.layered].each do |spelled|
        graph, = option_carried(:root, node_node, 30)

        expect { Elkrb.layout(graph, algorithm: spelled, strict: true) }
          .not_to raise_error
      end
    end

    let(:force_strictly) do
      { algorithm: "force", strict: true, node_node => 30 }
    end

    it "accepts a call key when any level's algorithm reads it" do
      graph = positioned_graph(
        compound: { layoutOptions: { "elk.algorithm" => "layered" } },
      )

      expect { Elkrb.layout(graph, force_strictly) }.not_to raise_error
    end

    it "refuses a call key when no level's algorithm reads it" do
      graph = positioned_graph(
        compound: { layoutOptions: { "elk.algorithm" => "stress" } },
      )

      expect { Elkrb.layout(graph, force_strictly) }
        .to raise_error(Elkrb::Error, unhonoured)
    end

    {
      "a node with no children" =>
        { leaf: { layoutOptions: { node_node => 30 } } },
      "an edge" => { edge: { layoutOptions: { node_node => 30 } } },
    }.each do |carrier, attributes|
      it "refuses the key on #{carrier}, which no algorithm lays out" do
        graph = positioned_graph(**attributes)

        expect { Elkrb.layout(graph, algorithm: "layered", strict: true) }
          .to raise_error(Elkrb::Error, unhonoured)
      end
    end
  end

  describe "in default mode" do
    it "stays silent when the algorithm reads the key" do
      graph, = option_carried(:root, node_node, 30)

      Elkrb.layout(graph, algorithm: "layered")

      expect(warnings.string).to eq("")
    end

    it "warns once, naming the readers, when it does not" do
      graph, = option_carried(:root, node_node, 30)

      Elkrb.layout(graph, algorithm: "force")

      expect(warnings.string.lines.size).to eq(1)
      expect(warnings.string).to include(node_node, "Read by box, layered")
    end
  end
end
