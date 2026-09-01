# frozen_string_literal: true

require "spec_helper"
require "json"

# The `<case>.json` expectations under spec/fixtures/elkt are HAND-AUTHORED
# from the .elkt source and ElkGraph.xtext. Never regenerate one from this
# parser: an expectation produced by the code under test proves only
# self-consistency.
ELKT_FIXTURES = File.expand_path("../../fixtures/elkt", __dir__)

# Exact expected [line, column] per invalid fixture, each checked by hand
# against the source. Asserting only that a location is PRESENT passes even
# when every error reports 1:1, which is no assertion at all.
ELKT_ERROR_LOCATIONS = {
  "bare_arrow" => [2, 9],
  "bare_keyword_property_key" => [1, 1],
  "edge_in_port_body" => [1, 19],
  "cr_line_location" => [2, 1],
  "escaped_keyword_stmt" => [1, 1],
  "escaped_property_in_shape_layout" => [1, 19],
  "garbage" => [1, 34],
  "geometry_after_bends" => [1, 49],
  "html" => [1, 1],
  "layout_extra_key" => [1, 19],
  "literal_false_as_id" => [1, 6],
  "literal_null_as_key" => [1, 1],
  "literal_true_as_id" => [1, 6],
  "mid_file_bom" => [2, 1],
  "node_in_label_body" => [1, 13],
  "property_after_member" => [2, 1],
  "qualified_declaration_id" => [1, 6],
  "qualified_edge_id" => [1, 6],
  "qualified_graph_id" => [1, 7],
  "qualified_label_id" => [1, 16],
  "qualified_outgoing_section_ref" => [1, 37],
  "qualified_port_id" => [1, 15],
  "qualified_section_id" => [1, 32],
  "repeated_bends" => [1, 49],
  "repeated_position" => [1, 35],
  "repeated_section_member" => [1, 49],
  "repeated_size" => [1, 31],
  "spaced_property_key" => [1, 1],
  "stray_brace" => [1, 1],
  "stray_char" => [2, 1],
  "unbalanced_brace" => [2, 1],
  "unescaped_keyword_segment" => [1, 6],
  "unknown_label_escape" => [1, 16],
  "unterminated_comment" => [1, 1],
  "unterminated_string" => [1, 16],
  "unterminated_string_newline" => [1, 16],
}.freeze

RSpec.describe Elkrb::Parsers::ElktParser do
  def parse_fixture(name)
    described_class.parse(File.read("#{ELKT_FIXTURES}/#{name}.elkt"))
  end

  def parse(source)
    described_class.parse(source)
  end

  describe "the fixture corpus" do
    Dir["#{ELKT_FIXTURES}/*.elkt"].each do |path|
      name = File.basename(path, ".elkt")

      it "parses #{name} to its committed graph" do
        graph = Elkrb::Graph::Graph.from_hash(described_class.parse(File.read(path)))

        expect(graph.to_json)
          .to eq(File.read(path.sub(/\.elkt\z/, ".json")).strip)
      end
    end

    Dir["#{ELKT_FIXTURES}/invalid/*.elkt"].each do |path|
      name = File.basename(path, ".elkt")

      it "rejects #{name} at its expected line and column" do
        line, column = ELKT_ERROR_LOCATIONS.fetch(name)

        expect { described_class.parse(File.read(path)) }
          .to raise_error(Elkrb::ParseError) { |error|
            expect([error.line, error.column]).to eq([line, column])
            expect(error.message).to include("line #{line}, column #{column}")
          }
      end
    end
  end

  # Everything Graph#to_json cannot show. The model has no root labels or
  # ports, no Edge port attribute, and no recursive Label, so the corpus layer
  # is blind to all of it.
  describe "the parser Hash" do
    it "emits no sourcePort or targetPort" do
      edge = parse_fixture("port_refs")[:edges].first

      expect(edge).not_to have_key(:sourcePort)
      expect(edge).not_to have_key(:targetPort)
    end

    it "resolves a port reference to the port id" do
      expect(parse_fixture("port_refs")[:edges].first)
        .to include(sources: ["p1"], targets: ["p2"])
    end

    it "resolves a nested node reference to the child id" do
      expect(parse_fixture("nested_node_ref")[:edges].first[:sources])
        .to eq(["c"])
    end

    it "keeps an unresolvable reference verbatim" do
      expect(parse_fixture("nested_node_ref")[:edges].last[:sources])
        .to eq(["x.y"])
    end

    # Oracle is ELK 0.12.0, not ElkGraph.xtext and not elkrb's NodeIndex --
    # both of those yielded a port-first rule that ELK contradicts.
    #
    # Mutating these: the discriminating mutation is the WHOLE prior rule --
    # ports before children AND first-match-wins in both resolve_in and
    # resolve_path. Measured: either half alone is NEUTRAL, because
    # backtracking recovers from a ports-first ordering and children-first
    # ordering never needs to backtrack. Only the combination is observable.
    it "prefers a complete node chain over a dead-end port prefix" do
      # `b` is both a port and a child. ELK resolves a.b.c to `c`.
      expect(parse_fixture("port_child_collision")[:edges].first[:sources])
        .to eq(["c"])
    end

    it "applies the same rule to the first path segment" do
      graph = parse_fixture("port_child_collision_first_segment")

      expect(graph[:children].first[:edges].first[:sources]).to eq(["leaf"])
    end

    # A regression guard, not a discriminator: a terminal port resolves the
    # same under both rules, so no mutation of this rule turns it red.
    it "still resolves a port that is the terminal segment" do
      expect(parse_fixture("port_terminal_ref")[:edges].first)
        .to include(sources: ["p"], targets: ["b"])
    end

    it "does not treat a node named root as a root scope" do
      # ELK leaves this unresolved; only a `graph` header names the root.
      expect(parse_fixture("root_named_node")[:edges].first[:sources])
        .to eq(["root.a.p"])
    end

    it "scopes resolution to the container that owns the edge" do
      children = parse_fixture("repeated_ids_across_levels")[:children]

      expect(children[0][:edges].first[:sources]).to eq(["lp"])
      expect(children[1][:edges].first[:sources]).to eq(["rp"])
    end

    it "allocates automatic edge ids in document order" do
      graph = parse_fixture("interleaved_edge_order")

      expect(graph[:edges].map { |edge| edge[:id] }).to eq(%w[e0 e2])
      expect(graph[:children].first[:edges].map { |e| e[:id] }).to eq(["e1"])
    end

    it "skips every declared id when allocating" do
      expect(parse_fixture("auto_edge_ids")[:edges].last[:id]).to eq("e6")
    end

    it "accepts a property inside an edge section without recording it" do
      section = parse(<<~ELKT)[:edges].first[:sections].first
        edge a -> b { layout [ section S1 [ ^start: foo  myProp: 3 ] ] }
      ELKT

      expect(section).to include(id: "S1")
      expect(section).not_to have_key(:startPoint)
    end

    it "reads an escaped ^section as an unnamed section property" do
      sections = parse("edge a -> b { layout [ ^section: 1 ] }\n")
        .dig(:edges, 0, :sections)

      expect(sections.first[:layoutOptions]).to eq("section" => 1)
    end

    it "accepts a label nested in a label" do
      label = parse_fixture("recursive_labels")[:children].first[:labels].first

      expect(label[:labels].first).to include(text: "inner")
    end

    it "keeps an empty label rather than dropping it" do
      labels = parse_fixture("quote_styles")[:children].first[:labels]

      # The committed JSON cannot distinguish "" from a missing :text.
      expect(labels.map do |label|
        label[:text]
      end).to eq(["single", "double", ""])
    end

    it "keeps labels and ports declared on the root graph" do
      # Graph has neither attribute, so Graph#to_json drops both silently.
      graph = parse(%(label "root label"\nport rp\nnode n\n))

      expect(graph[:labels].first[:text]).to eq("root label")
      expect(graph[:ports].first[:id]).to eq("rp")
    end

    it "resolves an endpoint against an enclosing container" do
      graph = parse_fixture("enclosing_scope_ref")

      expect(graph[:children][1][:edges].first[:targets]).to eq(["p"])
    end

    # The committed JSON CANNOT see this: EdgeSection has no
    # outgoing_sections attribute, so Graph#to_json drops the links whether
    # they are stored or discarded. Asserting at the Hash layer is the only
    # way the fix is observable.
    it "keeps the outgoing links of a named section" do
      sections = parse_fixture("edge_section_refs").dig(:edges, 0, :sections)

      expect(sections.first[:outgoingSections]).to eq(%w[S2 S3])
    end

    # ELK measures a label in UTF-16 code units, as Java's String#length does.
    # Ruby's String#length counts characters -- and BYTES once the string is
    # not valid UTF-8 -- so a lone surrogate was billed as three characters.
    it "measures label width in UTF-16 code units" do
      width = ->(src) { parse(src).dig(:children, 0, :labels, 0, :width) }

      # The property that matters: a lone surrogate costs the same as any
      # other single code unit, regardless of UTF-8 representability.
      expect(width[%(node n { label "\\uD83D" }\n)])
        .to eq(width[%(node n { label "A" }\n)])
      # And an astral character is two units, exactly like two ASCII ones.
      expect(width[%(node n { label "\\uD83D\\uDE00" }\n)])
        .to eq(width[%(node n { label "AB" }\n)])
    end

    it "counts an escaped CRLF as one line ending" do
      # The raw-string path was fixed first; the escape path consumed the
      # backslash and CR together and left the LF to be counted again.
      expect { parse(%(node n { label "a\\\r\nb" }\n@\n)) }
        .to raise_error(Elkrb::ParseError) { |error|
          expect([error.line, error.column]).to eq([3, 1])
        }
    end

    it "resolves incoming and outgoing section references" do
      # Both refs are qualified and land on DIFFERENT ports, so dropping
      # either branch is observable; `outgoing: a` was "a" either way.
      section = parse_fixture("section_shape_refs")
        .dig(:edges, 0, :sections, 0)

      expect(section).to include(incomingShape: "p", outgoingShape: "q")
    end

    it "resolves references qualified by the graph name" do
      graph = parse_fixture("graph_qualified_refs")

      expect(graph[:edges][0]).to include(sources: ["p"], targets: ["b"])
      expect(graph[:edges][1][:sections].first)
        .to include(incomingShape: "p", outgoingShape: "b")
    end

    it "does not invent a root scope without a graph header" do
      graph = parse(%(node a { port p }\nedge root.a.p -> b\n))

      expect(graph[:edges].first[:sources]).to eq(["root.a.p"])
    end

    # RSpec's eq treats 30 == 30.0, so this asserts the CLASS. ELK types
    # Number as EDouble; origin/v2 coerced with to_f and the rewrite dropped
    # it, changing the public Hash's types without any fixture noticing.
    it "emits geometry as Float even when spelled as an integer" do
      node = parse(%(node n { layout [ position: 1, 2  size: 30, 40 ] }\n))
        .dig(:children, 0)

      expect([node[:x], node[:y], node[:width], node[:height]])
        .to all(be_a(Float))
      expect(node[:x]).to eql(1.0)
    end

    it "emits section geometry as Float" do
      section = parse(<<~ELKT).dig(:edges, 0, :sections, 0)
        edge a -> b { layout [ section S [ start: 1, 2  bends: 3, 4 ] ] }
      ELKT

      expect(section[:startPoint].values).to all(be_a(Float))
      expect(section[:bendPoints].first.values).to all(be_a(Float))
    end

    it "counts a lone CR as a line ending" do
      # The comment fix made CR-delimited files parse; without the same
      # change in `advance`, every location in them is wrong.
      expect { parse("node a\r@\r") }
        .to raise_error(Elkrb::ParseError) { |error|
          expect([error.line, error.column]).to eq([2, 1])
        }
    end

    # ELK accepts a lone surrogate and emits one UTF-16 code unit with no
    # diagnostic, so raising here rejected valid input. Ruby packs it to
    # CESU-8, giving a String that is NOT valid UTF-8 -- which is why this is
    # asserted at the Hash layer and has no committed .json: Graph#to_json
    # raises JSON::GeneratorError on it. Pair-combining still applies and is
    # what keeps ordinary astral characters JSON-safe; the two rules do not
    # conflict, they cover paired and unpaired input respectively.
    it "accepts a lone surrogate as one UTF-16 code unit" do
      text = parse(%(node n { label "\\uD83D" }\n))
        .dig(:children, 0, :labels, 0, :text)

      expect(text.unpack1("U")).to eq(0xD83D)
      expect(text.valid_encoding?).to be(false)
      expect { Elkrb::Graph::Graph.from_hash(parse(%(node n { label "\\uD83D" }\n))).to_json }
        .to raise_error(JSON::GeneratorError)
    end

    it "still combines a surrogate pair into one JSON-safe character" do
      graph = parse(%(node n { label "\\uD83D\\uDE00" }\n))

      expect(graph.dig(:children, 0, :labels, 0, :text)).to eq("😀")
      expect(Elkrb::Graph::Graph.from_hash(graph).to_json).to include("😀")
    end

    it "counts a CRLF inside a string body as one line ending" do
      expect { parse(%(node n { label "a\r\nb" }\n@\n)) }
        .to raise_error(Elkrb::ParseError) { |error|
          expect([error.line, error.column]).to eq([3, 1])
        }
    end

    it "keeps backslashes in a property value but decodes them in a label" do
      graph = parse_fixture("string_decoding_by_context")

      expect(graph[:layoutOptions]["custom"]).to eq('a\nb')
      expect(graph[:children].first[:labels].first[:text]).to eq("a\nb")
    end
  end

  describe "the card's repros" do
    it "keeps a one-line block's members as siblings" do
      graph = parse(%(node n1 { label "One" }\nnode n2\nedge n1 -> n2\n))

      expect(graph[:children].map { |child| child[:id] }).to eq(%w[n1 n2])
      expect(graph[:children].first[:labels].first[:text]).to eq("One")
    end

    it "keeps the first declaration of a BOM-prefixed file" do
      graph = parse("﻿algorithm: force\nnode n1\n")

      expect(graph[:layoutOptions]).to eq("algorithm" => "force")
    end

    it "raises ParseError for input that is not valid UTF-8" do
      # Would otherwise escape the documented boundary as an ArgumentError
      # from the first regexp match.
      malformed = +"node \xC3\x28\n"
      malformed.force_encoding(Encoding::UTF_8)

      expect { parse(malformed) }
        .to raise_error(Elkrb::ParseError, /not valid UTF-8/)
    end

    it "accepts a UTF-8 source handed over in binary encoding" do
      binary = +"\xEF\xBB\xBFnode a\n"
      binary.force_encoding(Encoding::ASCII_8BIT)

      expect(parse(binary)[:children].first[:id]).to eq("a")
    end

    it "raises on non-ELKT input instead of returning an empty graph" do
      expect { parse("<html><body>nonsense</body></html>") }
        .to raise_error(Elkrb::ParseError, /line 1, column 1/)
    end
  end

  # Carried forward from the pre-rewrite spec. Only its three sourcePort
  # examples asserted behaviour this card removes.
  describe "behaviour carried forward" do
    it "parses an empty graph" do
      expect(parse("")).to eq(id: "root", layoutOptions: {}, children: [],
                              edges: [])
    end

    it "parses a self-loop edge" do
      expect(parse("node n1\nedge n1 -> n1\n")[:edges].first)
        .to include(sources: ["n1"], targets: ["n1"])
    end

    it "parses multiple edges between the same nodes" do
      graph = parse("node a\nnode b\nedge a -> b\nedge a -> b\n")

      expect(graph[:edges].map { |edge| edge[:id] }).to eq(%w[e0 e1])
    end

    it "parses float and boolean and integer values" do
      graph = parse("f: 2.5\nb: true\ni: 7\n")

      expect(graph[:layoutOptions]).to eq("f" => 2.5, "b" => true, "i" => 7)
    end

    it "parses line, block and inline comments" do
      graph = parse("// one\n/* two */\nnode a // three\nnode b\n")

      expect(graph[:children].map { |child| child[:id] }).to eq(%w[a b])
    end

    it "parses nested nodes" do
      graph = parse("node outer {\n  node inner\n}\n")

      expect(graph[:children].first[:children].first[:id]).to eq("inner")
    end

    it "defaults node width and height" do
      expect(parse("node a\n")[:children].first)
        .to include(width: 40, height: 40)
    end

    it "parses the real ELK layered example with forward references" do
      graph = parse(<<~ELKT)
        edge node1-> node2
        edge node2-> node3

        node node1
        node node2
        node node3
      ELKT

      expect(graph[:children].length).to eq(3)
      expect(graph[:edges].length).to eq(2)
    end

    it "parses the real ELK box example" do
      graph = parse(<<~ELKT)
        algorithm: box
        spacing.nodeNode: 2.0

        node node2 {
          layout [ size: 30, 30 ]
        }
      ELKT

      expect(graph[:layoutOptions]["algorithm"]).to eq("box")
      expect(graph[:children].first).to include(width: 30.0, height: 30.0)
    end

    it "raises on invalid edge syntax" do
      expect { parse("node n1\nedge n1 n2\n") }
        .to raise_error(Elkrb::ParseError)
    end
  end
end
