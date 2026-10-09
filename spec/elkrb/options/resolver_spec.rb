# frozen_string_literal: true

require "spec_helper"
require "logger"
require "stringio"
require "timeout"

RSpec.describe Elkrb::Options::Resolver do
  let(:spacing) { "elk.spacing.nodeNode" }

  describe "#get" do
    describe "elk.spacing.nodeNode, every source and value shape" do
      sources = {
        "element layoutOptions, canonical id" =>
          ->(v) { [{}, [with_layout_options("elk.spacing.nodeNode" => v)]] },
        "element layoutOptions, spacing.nodeNode" =>
          ->(v) { [{}, [with_layout_options("spacing.nodeNode" => v)]] },
        "element layoutOptions, org.eclipse.elk long form" =>
          lambda { |v|
            [{}, [with_layout_options(
              "org.eclipse.elk.spacing.nodeNode" => v,
            )]]
          },
        "element layoutOptions, spacing_node_node" =>
          ->(v) { [{}, [with_layout_options("spacing_node_node" => v)]] },
        "element properties" =>
          ->(v) {
            [{}, [option_element(properties: { "spacing.nodeNode" => v })]]
          },
        "element layoutOptions[\"properties\"] (deprecated)" =>
          lambda { |v|
            [{}, [with_layout_options(
              "properties" => { "elk.spacing.nodeNode" => v },
            )]]
          },
        "call, canonical id" =>
          ->(v) { [{ "elk.spacing.nodeNode" => v }, [option_element]] },
        "call, spacing_node_node symbol" =>
          ->(v) { [{ spacing_node_node: v }, [option_element]] },
      }
      values = [40, "40", 40.0]

      sources.each do |label, build|
        values.each do |value|
          it "reads #{value.inspect} from #{label} as the Float 40.0" do
            call, elements = instance_exec(value, &build)

            result = described_class.new(call).get(spacing, *elements)

            expect(result).to eql(40.0)
          end
        end
      end

      it "returns the registry default 20.0 when no source names it" do
        expect(described_class.new({}).get(spacing, option_element))
          .to eq(20.0)
      end

      it "treats an explicit zero as a value, not a miss" do
        expect(described_class.new(spacing => 0).get(spacing)).to eq(0.0)
      end

      it "reads an alias key passed to #get like the canonical id" do
        resolver = described_class.new(spacing => 33)

        expect(resolver.get("spacing_node_node")).to eq(33.0)
      end
    end

    describe "precedence" do
      let(:resolver) { described_class.new(spacing => 70) }

      it "prefers element layoutOptions over properties over call options" do
        node = option_element(layout_options: { spacing => 50 },
                              properties: { "spacing.nodeNode" => 60 })

        expect(resolver.get(spacing, node)).to eq(50.0)
      end

      it "prefers element properties over call options" do
        node = option_element(properties: { "spacing.nodeNode" => 60 })

        expect(resolver.get(spacing, node)).to eq(60.0)
      end

      it "falls back to the call option when the element carries none" do
        expect(resolver.get(spacing, option_element)).to eq(70.0)
      end

      it "lets the canonical id win over an alias in the same map" do
        node = with_layout_options("spacing_node_node" => 70, spacing => 50)

        expect(described_class.new({}).get(spacing, node)).to eq(50.0)
      end

      it "lets the canonical id win over an alias in the call options" do
        resolver = described_class.new(spacing_node_node: 70, spacing => 50)

        expect(resolver.get(spacing)).to eq(50.0)
      end

      it "lets the canonical id win in the call options, listed first" do
        resolver = described_class.new(spacing => 50, spacing_node_node: 70)

        expect(resolver.get(spacing)).to eq(50.0)
      end

      it "walks the caller's chain in order, edge then graph then call" do
        edge = with_layout_options("elk.edgeRouting" => "SPLINES")
        graph = with_layout_options("elk.edgeRouting" => "POLYLINE")
        resolver = described_class.new("elk.edgeRouting" => "ORTHOGONAL")

        expect(resolver.get("elk.edgeRouting", edge, graph)).to eq("SPLINES")
        expect(resolver.get("elk.edgeRouting", option_element, graph))
          .to eq("POLYLINE")
        expect(resolver.get("elk.edgeRouting", option_element, option_element))
          .to eq("ORTHOGONAL")
      end

      it "does not inherit from a parent unless the caller names it" do
        graph = with_layout_options("elk.direction" => "RIGHT")
        resolver = described_class.new({})

        expect(resolver.get("elk.direction", option_element))
          .to eq("RIGHT")
        expect(resolver.get("elk.direction", option_element, graph))
          .to eq("RIGHT")
      end
    end

    describe "a false value" do
      let(:key) { "vertiflex.balanceColumns" }

      it "defaults to true when nothing names it" do
        expect(described_class.new({}).get(key, option_element)).to be(true)
      end

      it "reads an element false as false" do
        node = with_layout_options(key => false)

        expect(described_class.new({}).get(key, node)).to be(false)
      end

      it "reads a call false as false" do
        expect(described_class.new(key => false).get(key, option_element))
          .to be(false)
      end

      it "lets an element false beat a call true" do
        node = with_layout_options(key => false)

        expect(described_class.new(key => true).get(key, node)).to be(false)
      end

      it "reads the string \"false\" as false" do
        node = with_layout_options(key => "false")

        expect(described_class.new({}).get(key, node)).to be(false)
      end
    end

    describe "elk.padding" do
      let(:resolver) { described_class.new({}) }

      it "parses an ELK string" do
        node = with_layout_options(
          "elk.padding" => "[top=5,left=7,bottom=9,right=11]",
        )

        expect(resolver.get("elk.padding", node)).to eq(
          Elkrb::Options::ElkPadding.new(top: 5, left: 7, bottom: 9, right: 11),
        )
      end

      it "fills the missing sides of a Hash from the registry default" do
        node = with_layout_options("elk.padding" => { "top" => 5 })

        expect(resolver.get("elk.padding", node)).to eq(
          Elkrb::Options::ElkPadding.new(top: 5, left: 12, bottom: 12,
                                         right: 12),
        )
      end

      it "spreads a number over every side" do
        expect(described_class.new(padding: 7).get("elk.padding")).to eq(
          Elkrb::Options::ElkPadding.new(top: 7, left: 7, bottom: 7, right: 7),
        )
      end

      it "reads a Symbol-keyed Hash passed as a call option" do
        call = { padding: { top: 50, left: 50, bottom: 50, right: 50 } }

        expect(described_class.new(call).get("elk.padding").top).to eq(50.0)
      end
    end

    describe "keys the registry does not know" do
      let(:resolver) { described_class.new({}) }

      it "returns the caller's default" do
        expect(resolver.get("custom.thing", default: 9)).to eq(9)
      end

      it "returns nil for default: nil" do
        expect(resolver.get("custom.thing", default: nil)).to be_nil
      end

      it "reads a custom key from the call options under its own name" do
        expect(described_class.new(custom_thing: 4).get("custom_thing"))
          .to eq(4)
      end

      it "reads an explicit false for an unregistered key, not the default" do
        node = with_layout_options("custom.flag" => false)

        expect(described_class.new({}).get("custom.flag", node, default: true))
          .to be(false)
      end

      it "finds an element's value under a unique key suffix" do
        node = with_layout_options("nodeNode" => 40)

        expect(described_class.new({}).get(spacing, node)).to eq(40.0)
      end

      it "reads the deprecated nested properties map after layoutOptions" do
        node = with_layout_options(
          spacing => 50, "properties" => { spacing => 99 },
        )

        expect(described_class.new({}).get(spacing, node)).to eq(50.0)
      end

      it "ranks the deprecated nested map above element properties" do
        node = option_element(
          layout_options: { "properties" => { spacing => 60 } },
          properties: { "spacing.nodeNode" => 90 },
        )

        expect(described_class.new({}).get(spacing, node)).to eq(60.0)
      end

      it "reads a custom key from an element under its own name, uncoerced" do
        node = with_layout_options("custom.thing" => "x")

        expect(resolver.get("custom.thing", node)).to eq("x")
      end
    end

    describe "default:" do
      let(:resolver) { described_class.new({}) }

      it "returns a literal in place of the registry default" do
        expect(resolver.get(spacing, default: 3)).to eq(3)
      end

      it "returns nil in place of the registry default for default: nil" do
        expect(resolver.get(spacing, default: nil)).to be_nil
      end
    end

    describe "nil-safety" do
      it "accepts a nil element and an element with nil maps" do
        edge = Elkrb::Graph::Edge.new(id: "e")
        edge.layout_options = nil
        edge.properties = nil

        expect(described_class.new({}).get(spacing, nil, edge)).to eq(20.0)
      end
    end

    describe "a value that cannot be coerced" do
      [[1], { "a" => 1 }, true, "abc", "", "12px"].each do |bad|
        it "raises ValidationError naming the option for #{bad.inspect}" do
          node = with_layout_options("elk.spacing.nodeNode" => bad)

          expect { described_class.new({}).get(spacing, node) }
            .to raise_error(Elkrb::ValidationError, /elk\.spacing\.nodeNode/)
        end
      end

      it "reads a numeric string with surrounding space as a number" do
        expect(described_class.new(spacing => " 40 ").get(spacing)).to eq(40.0)
      end

      # Float() reads these; String#to_f and #to_i read them as 0, so a
      # validator as wide as Float() lets a silent zero through.
      ["0x10", "0X1F", "0x1p3", "6_0", "1e", "--1", "NaN", "Infinity"]
        .each do |bad|
        it "rejects the numeric string #{bad.inspect} instead of reading 0" do
          expect { described_class.new(spacing => bad).get(spacing) }
            .to raise_error(Elkrb::ValidationError, /elk\.spacing\.nodeNode/)
        end
      end

      [["1e3", 1000], ["1.9", 1], [" 7 ", 7], ["+5", 5]].each do |text, parsed|
        it "reads the integer option's #{text.inspect} as #{parsed}" do
          resolver = described_class.new("elk.force.iterations" => text)

          expect(resolver.get("elk.force.iterations")).to eq(parsed)
        end
      end

      { "5." => 5.0, "1.e3" => 1000.0, "-2." => -2.0, ".5" => 0.5 }
        .each do |text, parsed|
        it "reads the float option's #{text.inspect} as #{parsed}" do
          resolver = described_class.new(spacing => text)

          expect(resolver.get(spacing)).to eq(parsed)
        end
      end

      it "reads the float option's scientific notation as a number" do
        expect(described_class.new(spacing => "1e2").get(spacing)).to eq(100.0)
      end

      [Float::NAN, Float::INFINITY, Complex(1, 2)].each do |bad|
        it "raises ValidationError for #{bad} as an integer option" do
          resolver = described_class.new("elk.force.iterations" => bad)

          expect { resolver.get("elk.force.iterations") }
            .to raise_error(Elkrb::ValidationError, /elk\.force\.iterations/)
        end
      end

      ["5\xFF", "5".encode("UTF-16LE"), "5".b + "\xFF".b].each do |bad|
        it "raises ValidationError for the mis-encoded string #{bad.inspect}" do
          resolver = described_class.new(spacing => bad)

          expect { resolver.get(spacing) }
            .to raise_error(Elkrb::ValidationError, /elk\.spacing\.nodeNode/)
        end
      end

      it "raises ValidationError for a mis-encoded padding string" do
        resolver = described_class.new(padding: "[top=1]".encode("UTF-16LE"))

        expect { resolver.get("elk.padding") }
          .to raise_error(Elkrb::ValidationError, /elk\.padding/)
      end

      it "raises ValidationError for a Complex float option" do
        expect { described_class.new(spacing => Complex(1, 2)).get(spacing) }
          .to raise_error(Elkrb::ValidationError, /elk\.spacing\.nodeNode/)
      end

      [Float::INFINITY, Float::NAN, "[top=1e400,left=1,bottom=1,right=1]",
       { top: Float::INFINITY }].each do |bad|
        it "raises for the non-finite padding #{bad.inspect}" do
          expect { described_class.new(padding: bad).get("elk.padding") }
            .to raise_error(Elkrb::ValidationError, /elk\.padding/)
        end
      end

      it "raises for a non-finite component in a kvector option" do
        resolver = described_class.new("elk.position" => "(1e400, 1)")

        expect { resolver.get("elk.position") }
          .to raise_error(Elkrb::ValidationError, /finite/)
      end

      ["(1e400, 1)", "(1,2; 3,1e400)", [[1, Float::NAN]]].each do |bad|
        it "raises for the non-finite vector chain #{bad.inspect}" do
          resolver = described_class.new("elk.bendPoints" => bad)

          expect { resolver.get("elk.bendPoints") }
            .to raise_error(Elkrb::ValidationError, /finite/)
        end
      end

      it "raises for a padding string that is not ELK padding syntax" do
        expect { described_class.new(padding: "abc").get("elk.padding") }
          .to raise_error(Elkrb::ValidationError, /elk\.padding/)
      end

      # Every spelling of a structured numeric option has to read each
      # component like a scalar one: "abc" and "0x10" are not 0.0.
      StructuredOptionForms::SIDES.each do |side|
        StructuredOptionForms::BAD_COMPONENTS.each do |bad|
          StructuredOptionForms.paddings(side, bad).each do |form, value|
            it "raises for #{bad.inspect} as #{side} of a padding #{form}" do
              resolver = described_class.new(padding: value)

              expect { resolver.get("elk.padding") }
                .to raise_error(Elkrb::ValidationError, /elk\.padding/)
            end
          end
        end
      end

      ["[top]", "[top=1=2]", "[top=1=]", "[=1]", "[top=1,]", "[top=1, ]",
       "[top=1,,left=2]"].each do |bad|
        it "raises for the padding entry in #{bad.inspect}" do
          expect { described_class.new(padding: bad).get("elk.padding") }
            .to raise_error(Elkrb::ValidationError, /elk\.padding/)
        end
      end

      StructuredOptionForms::AXES.each do |axis|
        StructuredOptionForms::BAD_COMPONENTS.each do |bad|
          StructuredOptionForms.vectors(axis, bad).each do |form, value|
            it "raises for #{bad.inspect} as #{axis} of a vector #{form}" do
              resolver = described_class.new("elk.position" => value)

              expect { resolver.get("elk.position") }
                .to raise_error(Elkrb::ValidationError, /elk\.position/)
            end
          end
        end
      end

      ["(1,abc)", "(0x10,1; 2,3)", "(1,2; 3,1e)", [[1, "abc"]]].each do |bad|
        it "raises for the non-numeric vector chain #{bad.inspect}" do
          resolver = described_class.new("elk.bendPoints" => bad)

          expect { resolver.get("elk.bendPoints") }
            .to raise_error(Elkrb::ValidationError, /elk\.bendPoints/)
        end
      end

      # to_h would collapse a repeated side before it is validated.
      ["[top=abc,top=1]", "[top=1,top=abc]", "[top=0x10,left=1,top=2]"]
        .each do |bad|
        it "raises for the repeated side in #{bad.inspect}" do
          expect { described_class.new(padding: bad).get("elk.padding") }
            .to raise_error(Elkrb::ValidationError, /elk\.padding/)
        end
      end

      it "lets the last of a repeated valid side win" do
        resolver = described_class.new(padding: "[top=1,top=3]")

        expect(resolver.get("elk.padding").top).to eq(3.0)
      end

      ["(1,2,)", "(1,2, )", "(,1)", "()", "(1)"].each do |bad|
        it "raises for the vector string #{bad.inspect}" do
          resolver = described_class.new("elk.position" => bad)

          expect { resolver.get("elk.position") }
            .to raise_error(Elkrb::ValidationError, /elk\.position/)
        end
      end

      it "reads an empty padding string as no padding" do
        padding = described_class.new(padding: "[]").get("elk.padding")

        expect(padding.to_h.values).to eq([0.0, 0.0, 0.0, 0.0])
      end

      it "keeps the default for a side a padding hash leaves out or nils" do
        resolver = described_class.new(padding: { top: 5, left: nil })
        padding = resolver.get("elk.padding")

        expect(padding.to_h).to eq(left: 12.0, top: 5.0, right: 12.0,
                                   bottom: 12.0)
      end

      it "raises for a vector string with one component" do
        resolver = described_class.new("elk.position" => "(1,)")

        expect { resolver.get("elk.position") }
          .to raise_error(Elkrb::ValidationError, /elk\.position/)
      end

      it "raises for a malformed padding on an element, not only on the call" do
        node = with_layout_options("elk.padding" => "[top=abc]")

        expect { described_class.new({}).get("elk.padding", node) }
          .to raise_error(Elkrb::ValidationError, /elk\.padding/)
      end

      {
        "[top=5.,left= 1 ,bottom=1.e1,right=+2]" => [5.0, 1.0, 10.0, 2.0],
        { top: "5", left: 1, bottom: "2.5", right: " 3 " } =>
          [5.0, 1.0, 2.5, 3.0],
      }.each do |good, (top, left, bottom, right)|
        it "reads the padding #{good.inspect} component by component" do
          padding = described_class.new(padding: good).get("elk.padding")

          expect(padding.to_h.values_at(:top, :left, :bottom, :right))
            .to eq([top, left, bottom, right])
        end
      end

      {
        "(5., 1.e1)" => [5.0, 10.0],
        { x: "2.5", y: 3 } => [2.5, 3.0],
        ["7", " 8 "] => [7.0, 8.0],
      }.each do |good, expected|
        it "reads the vector #{good.inspect} component by component" do
          resolver = described_class.new("elk.position" => good)

          expect(resolver.get("elk.position").to_a).to eq(expected)
        end
      end

      [Float::INFINITY, -Float::INFINITY, Float::NAN].each do |bad|
        it "raises for the non-finite float #{bad}" do
          expect { described_class.new(spacing => bad).get(spacing) }
            .to raise_error(Elkrb::ValidationError, /finite/)
        end
      end
    end
  end

  describe "#report_unhonoured" do
    let(:log) { StringIO.new }
    let(:logger) do
      Logger.new(log, level: Logger::DEBUG,
                      formatter: ->(sev, _t, _p, msg) { "#{sev} #{msg}\n" })
    end
    let(:resolver) { described_class.new({}) }
    let(:honoured) { "elk.edgeRouting" }

    around do |example|
      previous = Elkrb.logger
      Elkrb.logger = logger
      example.run
    ensure
      Elkrb.logger = previous
    end

    it "warns once per partially honoured key, with the registry note" do
      note = Elkrb::Options::Registry.note("elk.hierarchyHandling")

      resolver.report_unhonoured(
        option_graph({ "elk.hierarchyHandling" => "INCLUDE_CHILDREN" }),
      )

      expect(log.string).to eq(
        "WARN elkrb: option elk.hierarchyHandling is partially honoured: " \
        "#{note}\n",
      )
    end

    it "warns once per accepted key" do
      resolver.report_unhonoured(option_graph({ "elk.spacing.edgeNode" => 5 }))

      expect(log.string).to eq(
        "WARN elkrb: option elk.spacing.edgeNode is accepted but not " \
        "honoured in this version\n",
      )
    end

    it "stays silent for honoured keys" do
      resolver.report_unhonoured(
        option_graph({ honoured => 5, "elk.algorithm" => "box" }),
      )

      expect(log.string).to eq("")
    end

    it "logs an unknown key at DEBUG, never WARN" do
      resolver.report_unhonoured(option_graph({ "foo.bar" => 1 }))

      expect(log.string)
        .to eq("DEBUG elkrb: unknown option foo.bar: stored and echoed\n")
    end

    it "logs one line for a key that appears at several levels" do
      child = Elkrb::Graph::Node.new(
        id: "c", layout_options: { "spacing.edgeNode" => 1 },
      )
      graph = option_graph({ "elk.spacing.edgeNode" => 5 }, children: [child])

      resolver.report_unhonoured(graph)

      expect(log.string.lines.size).to eq(1)
    end

    it "finds a key on a nested node, port, edge and label" do
      port = Elkrb::Graph::Port.new(
        id: "p", layout_options: { "elk.spacing.edgeEdge" => 1 },
      )
      label = Elkrb::Graph::Label.new(
        text: "t", layout_options: { "elk.box.packingMode" => "SIMPLE" },
      )
      inner = Elkrb::Graph::Node.new(id: "inner", ports: [port],
                                     labels: [label])
      edge = Elkrb::Graph::Edge.new(
        id: "e", layout_options: { "elk.radial.centerOnRoot" => true },
      )
      outer = Elkrb::Graph::Node.new(id: "outer", children: [inner],
                                     edges: [edge])

      resolver.report_unhonoured(option_graph({}, children: [outer]))

      expect(log.string.lines.map { |line| line[/option (\S+)/, 1] })
        .to contain_exactly("elk.spacing.edgeEdge", "elk.box.packingMode")
    end

    it "warns again on every call, because the report is per layout" do
      graph = option_graph({ "elk.spacing.edgeNode" => 5 })

      2.times { resolver.report_unhonoured(graph) }

      expect(log.string.lines.size).to eq(2)
    end

    it "does not report a deprecated nested properties map as unknown" do
      graph = option_graph({ "properties" => { honoured => 5 } })

      resolver.report_unhonoured(graph)

      expect(log.string).to eq("")
    end

    it "keeps control characters in an unknown key out of the debug log" do
      forged = option_graph({ "evil\nERROR -- : forged" => 1 })

      resolver.report_unhonoured(forged)

      expect(log.string.lines.size).to eq(1)
    end

    it "reports an unknown key that is invalid UTF-8 on one line" do
      resolver.report_unhonoured(option_graph({ "bad\xFF" => 1 }))

      expect(log.string.lines.size).to eq(1)
    end

    it "visits an element reachable twice, or from itself, once" do
      shared = with_layout_options({ "elk.spacing.edgeNode" => 5 })
      cyclic = option_graph({})
      cyclic.children = [shared, shared, cyclic]

      Timeout.timeout(5) { resolver.report_unhonoured(cyclic) }

      expect(log.string.lines.size).to eq(1)
    end

    describe "strict: true" do
      let(:strict) { described_class.new(strict: true) }

      it "raises Elkrb::Error naming every unknown and unhonoured key" do
        graph = option_graph({ "foo.bar" => 1, "elk.spacing.edgeNode" => 5,
                               "elk.hierarchyHandling" => "INCLUDE_CHILDREN",
                               honoured => 3 })

        expect { strict.report_unhonoured(graph) }
          .to raise_error(Elkrb::Error) { |error|
            expect(error.message)
              .to include("foo.bar", "elk.spacing.edgeNode",
                          "elk.hierarchyHandling")
            expect(error.message).not_to include(honoured)
          }
      end

      it "logs nothing when it raises" do
        graph = option_graph({ "elk.spacing.edgeNode" => 5 })

        expect { strict.report_unhonoured(graph) }.to raise_error(Elkrb::Error)
        expect(log.string).to eq("")
      end

      it "does not raise for a graph carrying only honoured keys" do
        expect { strict.report_unhonoured(option_graph({ honoured => 3 })) }
          .not_to raise_error
      end

      [false, nil].each do |not_true|
        it "stays in warn mode for strict: #{not_true.inspect}" do
          lenient = described_class.new(strict: not_true)

          expect { lenient.report_unhonoured(option_graph({ "foo.bar" => 1 })) }
            .not_to raise_error
        end
      end

      ["true", 1, :yes].each do |typo|
        it "refuses strict: #{typo.inspect} instead of ignoring it" do
          resolver = described_class.new(strict: typo)

          expect { resolver.report_unhonoured(option_graph({})) }
            .to raise_error(Elkrb::ValidationError, /strict/)
        end
      end

      it "keeps control characters in an unknown key out of the message" do
        graph = option_graph({ "evil\nERROR -- : forged\e[2J" => 1 })

        expect { strict.report_unhonoured(graph) }
          .to raise_error(Elkrb::Error) { |error|
            expect(error.message).not_to match(/[[:cntrl:]]/)
            expect(error.message).to include("evil\\nERROR")
          }
      end
    end

    describe "every source #get reads is reported" do
      let(:edge_node) { "elk.spacing.edgeNode" }

      %i[layout_options properties nested call].each do |source|
        it "reads and reports a registered key from #{source}" do
          resolver, elements = option_source(source, { edge_node => 5 }, :plain)

          resolver.report_unhonoured(option_graph({}, children: elements))

          expect(resolver.get(edge_node, *elements)).to eq(5.0)
          expect(log.string).to eq(
            "WARN elkrb: option #{edge_node} is accepted but not " \
            "honoured in this version\n",
          )
        end
      end

      it "raises in strict mode for a registered key in element properties" do
        strict = described_class.new(strict: true)
        graph = option_graph(
          {}, children: [option_element(properties: { edge_node => 5 })]
        )

        expect { strict.report_unhonoured(graph) }
          .to raise_error(Elkrb::Error, /#{Regexp.escape(edge_node)}/)
      end

      # Keep: the opposite direction of the examples above; it is the only
      # check that properties keeps ordinary metadata out of strict mode.
      it "treats an unknown name in properties as metadata, not an option" do
        strict = described_class.new(strict: true)
        element = option_element(
          properties: { "foo.bar" => 1, "_constraint_layer" => 2 },
        )
        graph = option_graph({}, children: [element])

        expect { strict.report_unhonoured(graph) }.not_to raise_error
        expect(log.string).to eq("")
      end
    end

    describe "options passed to the layout call" do
      let(:empty_graph) { option_graph({}) }

      it "warns once for a call-level accepted key" do
        resolver = described_class.new("elk.spacing.edgeNode" => 5)

        resolver.report_unhonoured(empty_graph)

        expect(log.string).to eq(
          "WARN elkrb: option elk.spacing.edgeNode is accepted but not " \
          "honoured in this version\n",
        )
      end

      it "warns with the registry note for a call-level partial key" do
        note = Elkrb::Options::Registry.note("elk.hierarchyHandling")

        resolver = described_class.new(
          "elk.hierarchyHandling" => "SEPARATE_CHILDREN",
        )

        resolver.report_unhonoured(empty_graph)

        expect(log.string).to eq(
          "WARN elkrb: option elk.hierarchyHandling is partially honoured: " \
          "#{note}\n",
        )
      end

      it "warns once when graph and call carry the same key" do
        resolver = described_class.new("elk.spacing.edgeNode" => 5)

        resolver.report_unhonoured(
          option_graph({ "elk.spacing.edgeNode" => 5 }),
        )

        expect(log.string.lines.size).to eq(1)
      end

      it "raises under strict: true, naming the call-level key" do
        strict = described_class.new(strict: true, "elk.spacing.edgeNode" => 5)

        expect { strict.report_unhonoured(empty_graph) }
          .to raise_error(Elkrb::Error, /elk\.spacing\.edgeNode/)
        expect(log.string).to eq("")
      end

      it "reads the key under any spelling" do
        strict = described_class.new(strict: true,
                                     hierarchyHandling: "SEPARATE_CHILDREN")

        expect { strict.report_unhonoured(empty_graph) }
          .to raise_error(Elkrb::Error, /elk\.hierarchyHandling/)
      end

      it "does not report a nested properties map the call never reads" do
        strict = described_class.new(
          strict: true, properties: { "elk.spacing.edgeNode" => 5 },
        )

        expect { strict.report_unhonoured(empty_graph) }.not_to raise_error
        expect(log.string).to eq("")
      end

      it "stays silent for honoured call keys and engine flags, even strict" do
        strict = described_class.new(
          strict: true, hierarchical: true, algorithm: "box",
          edge_routing: "ORTHOGONAL", iterations: 10, "not.a.key" => 1
        )

        expect { strict.report_unhonoured(empty_graph) }.not_to raise_error
        expect(log.string).to eq("")
      end
    end
  end
end
