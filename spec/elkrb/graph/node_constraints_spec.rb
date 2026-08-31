# frozen_string_literal: true

require "spec_helper"

# Cross-spelling parity: the same value fed through the canonical and the
# legacy key must land identically -- same rejection, same Ruby type, same
# value. All six fields, relative_offset included.
#
# align_direction carries a VALID value on purpose. It is the only field with a
# validating setter, and the other five entries are wrong-typed Hashes that
# never reach a successful assignment, so a valid value is what covers the
# accept-and-normalise path here. The rejecting path is pinned separately, in
# "validation through the legacy alias". Both shapes satisfy parity -- measured
# -- so this is about coverage, not about making the example pass.
nc_bad_values = [
  { snake: "relative_offset", camel: "relativeOffset",
    yaml: "nope", reader: :relative_offset },
  { snake: "relative_to", camel: "relativeTo",
    yaml: "\n  a: 1", reader: :relative_to },
  { snake: "position_priority", camel: "positionPriority",
    yaml: "\n  a: 1", reader: :position_priority },
  { snake: "align_group", camel: "alignGroup",
    yaml: "\n  a: 1", reader: :align_group },
  { snake: "fixed_position", camel: "fixedPosition",
    yaml: "\n  a: 1", reader: :fixed_position },
  { snake: "align_direction", camel: "alignDirection",
    yaml: "horizontal", reader: :align_direction },
]

# The five scalar fields of the six Do 7 covers; relative_offset is nested and
# gets its own block below.
nc_fields = [
  { snake: "fixed_position", camel: "fixedPosition",
    reader: :fixed_position, value: true, default: false },
  { snake: "align_group", camel: "alignGroup",
    reader: :align_group, value: "databases", default: nil },
  { snake: "align_direction", camel: "alignDirection",
    reader: :align_direction, value: "horizontal", default: nil },
  { snake: "relative_to", camel: "relativeTo",
    reader: :relative_to, value: "backend", default: nil },
  { snake: "position_priority", camel: "positionPriority",
    reader: :position_priority, value: 5, default: 0 },
]

RSpec.describe Elkrb::Graph::NodeConstraints do
  describe "initialization" do
    it "creates constraints with default values" do
      constraints = described_class.new

      expect(constraints.fixed_position).to be false
      expect(constraints.layer).to be_nil
      expect(constraints.align_group).to be_nil
      expect(constraints.align_direction).to be_nil
      expect(constraints.relative_to).to be_nil
      expect(constraints.relative_offset).to be_nil
      expect(constraints.position_priority).to eq(0)
    end

    it "creates constraints with fixed_position" do
      constraints = described_class.new(fixed_position: true)

      expect(constraints.fixed_position).to be true
    end

    it "creates constraints with layer assignment" do
      constraints = described_class.new(layer: 2)

      expect(constraints.layer).to eq(2)
    end

    it "creates constraints with alignment" do
      constraints = described_class.new(
        align_group: "databases",
        align_direction: "horizontal",
      )

      expect(constraints.align_group).to eq("databases")
      expect(constraints.align_direction).to eq("horizontal")
    end

    it "creates constraints with relative positioning" do
      offset = Elkrb::Graph::RelativeOffset.new(x: 150, y: 0)
      constraints = described_class.new(
        relative_to: "backend",
        relative_offset: offset,
      )

      expect(constraints.relative_to).to eq("backend")
      expect(constraints.relative_offset.x).to eq(150)
      expect(constraints.relative_offset.y).to eq(0)
    end
  end

  describe "align_direction validation" do
    it "accepts horizontal direction" do
      constraints = described_class.new

      expect do
        constraints.align_direction = "horizontal"
      end.not_to raise_error

      expect(constraints.align_direction).to eq("horizontal")
    end

    it "accepts vertical direction" do
      constraints = described_class.new

      expect do
        constraints.align_direction = "vertical"
      end.not_to raise_error

      expect(constraints.align_direction).to eq("vertical")
    end

    it "normalizes direction to lowercase" do
      constraints = described_class.new
      constraints.align_direction = "HORIZONTAL"

      expect(constraints.align_direction).to eq("horizontal")
    end

    it "raises error for invalid direction" do
      constraints = described_class.new

      expect do
        constraints.align_direction = "diagonal"
      end.to raise_error(ArgumentError, /Invalid align_direction/)
    end

    it "allows nil direction" do
      constraints = described_class.new

      expect do
        constraints.align_direction = nil
      end.not_to raise_error

      expect(constraints.align_direction).to be_nil
    end
  end

  describe "JSON serialization" do
    it "serializes to JSON" do
      offset = Elkrb::Graph::RelativeOffset.new(x: 100, y: 50)
      constraints = described_class.new(
        fixed_position: true,
        layer: 1,
        align_group: "backend",
        align_direction: "horizontal",
        relative_to: "api",
        relative_offset: offset,
        position_priority: 5,
      )

      json = constraints.to_json
      parsed = JSON.parse(json)

      expect(parsed["fixedPosition"]).to be true
      expect(parsed["layer"]).to eq(1)
      expect(parsed["alignGroup"]).to eq("backend")
      expect(parsed["alignDirection"]).to eq("horizontal")
      expect(parsed["relativeTo"]).to eq("api")
      expect(parsed["relativeOffset"]["x"]).to eq(100)
      expect(parsed["relativeOffset"]["y"]).to eq(50)
      expect(parsed["positionPriority"]).to eq(5)
    end

    it "deserializes from JSON" do
      json = <<~JSON
        {
          "fixedPosition": true,
          "layer": 2,
          "alignGroup": "databases"
        }
      JSON

      constraints = described_class.from_json(json)

      expect(constraints.fixed_position).to be true
      expect(constraints.layer).to eq(2)
      expect(constraints.align_group).to eq("databases")
    end
  end

  describe "YAML serialization" do
    it "serializes to YAML" do
      constraints = described_class.new(
        fixed_position: true,
        layer: 1,
      )

      yaml = constraints.to_yaml
      parsed = YAML.safe_load(yaml)

      expect(parsed["fixed_position"]).to be true
      expect(parsed["layer"]).to eq(1)
    end

    it "deserializes from YAML" do
      yaml = <<~YAML
        fixedPosition: true
        layer: 2
        alignGroup: databases
        alignDirection: horizontal
      YAML

      constraints = described_class.from_yaml(yaml)

      expect(constraints.fixed_position).to be true
      expect(constraints.layer).to eq(2)
      expect(constraints.align_group).to eq("databases")
      expect(constraints.align_direction).to eq("horizontal")
    end
  end
  # Do 7: YAML is written in snake_case like every other model, with the old
  # camelCase spellings kept as read-only aliases. Every one of the six fields
  # is covered on all four axes so no alias or hook can be reverted silently.
  describe "snake_case YAML with camelCase read aliases" do
    nc_fields.each do |field|
      context "for #{field[:snake]}" do
        it "reads the canonical snake_case key" do
          constraints = described_class.from_yaml(
            "#{field[:snake]}: #{field[:value]}\n",
          )

          expect(constraints.public_send(field[:reader])).to eq(field[:value])
        end

        it "reads the legacy camelCase key" do
          constraints = described_class.from_yaml(
            "#{field[:camel]}: #{field[:value]}\n",
          )

          expect(constraints.public_send(field[:reader])).to eq(field[:value])
        end

        it "writes only the snake_case key" do
          constraints = described_class.from_yaml(
            "#{field[:snake]}: #{field[:value]}\n",
          )
          parsed = YAML.safe_load(constraints.to_yaml)

          expect(parsed[field[:snake]]).to eq(field[:value])
          expect(parsed).not_to have_key(field[:camel])
        end

        it "leaves the default when neither spelling is present" do
          constraints = described_class.from_yaml("layer: 2\n")

          expect(constraints.public_send(field[:reader])).to eq(field[:default])
        end
      end
    end

    # relative_offset is the only nested model of the six, and the one where a
    # wrong hook body yields an object that cannot serialize at all.
    describe "relative_offset" do
      it "reads the canonical snake_case key" do
        constraints = described_class.from_yaml(
          "relative_offset:\n  x: 1.0\n  y: 2.0\n",
        )

        expect([constraints.relative_offset.x, constraints.relative_offset.y])
          .to eq([1.0, 2.0])
      end

      it "reads the legacy camelCase key" do
        constraints = described_class.from_yaml(
          "relativeOffset:\n  x: 3.0\n  y: 4.0\n",
        )

        expect([constraints.relative_offset.x, constraints.relative_offset.y])
          .to eq([3.0, 4.0])
      end

      it "writes the nested offset under the snake_case key" do
        constraints = described_class.from_yaml(
          "relative_offset:\n  x: 1.0\n  y: 2.0\n",
        )
        parsed = YAML.safe_load(constraints.to_yaml)

        expect(parsed["relative_offset"]).to eq("x" => 1.0, "y" => 2.0)
        expect(parsed).not_to have_key("relativeOffset")
      end

      it "leaves it nil when neither spelling is present" do
        expect(described_class.from_yaml("layer: 2\n").relative_offset)
          .to be_nil
      end
    end

    # The legacy spelling must cast exactly as the canonical one does. Without
    # that, a bad value slips past parse on the alias path and dies later --
    # relativeOffset: nope reached the layout engine as a String.
    describe "type parity between the two spellings" do
      # Compared by class and rendered value: lutaml wrapper objects are
      # distinct instances, so identity would never match even when the two
      # spellings agree.
      def outcome(yaml, reader)
        value = described_class.from_yaml(yaml).public_send(reader)
        [:ok, value.class, value.to_s]
      rescue StandardError => e
        [:raised, e.class]
      end

      nc_bad_values.each do |field|
        it "treats #{field[:camel]} exactly like #{field[:snake]}" do
          reader = field[:reader]

          expect(outcome("#{field[:camel]}: #{field[:yaml]}\n", reader))
            .to eq(outcome("#{field[:snake]}: #{field[:yaml]}\n", reader))
        end
      end

      # An array for a scalar attribute: the canonical path rejects it via
      # Attribute#valid_collection!, so the legacy path must too. Two of these
      # used to parse clean and then crash the layout engine.
      [
        { snake: "fixed_position", camel: "fixedPosition", yaml: "[true]" },
        { snake: "align_group", camel: "alignGroup", yaml: "[g]" },
        { snake: "align_direction", camel: "alignDirection",
          yaml: "[horizontal]" },
        { snake: "relative_to", camel: "relativeTo", yaml: "[n]" },
        { snake: "position_priority", camel: "positionPriority", yaml: "[1]" },
        { snake: "relative_offset", camel: "relativeOffset",
          yaml: "[{x: 1, y: 2}]" },
      ].each do |field|
        it "rejects an array for #{field[:camel]} as #{field[:snake]} does" do
          both = [field[:camel], field[:snake]]

          both.each do |key|
            expect { described_class.from_yaml("#{key}: #{field[:yaml]}\n") }
              .to raise_error(Lutaml::Model::CollectionTrueMissingError)
          end
        end
      end

      it "rejects a mistyped relativeOffset at parse" do
        expect { described_class.from_yaml("relativeOffset: nope\n") }
          .to raise_error(Lutaml::Model::InvalidFormatError)
      end

      # Deleting the lutaml_parent/lutaml_root arguments from cast_legacy
      # leaves every other expectation green, so this asserts them from a
      # nested graph where the two differ.
      it "wires a legacy offset to its parent and root" do
        graph = Elkrb::Graph::Graph.from_yaml(
          "id: r\nchildren:\n- id: a\n  width: 1\n  height: 1\n  " \
          "constraints:\n    relativeOffset:\n      x: 3.0\n      y: 4.0\n",
        )
        constraints = graph.children.first.constraints

        expect(constraints.relative_offset.lutaml_parent).to equal(constraints)
        expect(constraints.relative_offset.lutaml_root).to equal(graph)
      end

      it "gives relativeTo a plain String, not a lutaml wrapper" do
        constraints = described_class.from_yaml("relativeTo:\n  a: 1\n")

        expect(constraints.relative_to).to be_an_instance_of(String)
      end

      # A blank legacy value is a real value, not an absent key: the root rule
      # sees the key and writes it, so the legacy spelling wins here too.
      it "lets a blank alias beat a canonical value" do
        constraints = described_class.from_yaml(
          "align_group: snake\nalignGroup: ''\n",
        )

        expect(constraints.align_group).to eq("")
      end

      # A null alias must OVERWRITE a canonical value, not merely leave the
      # attribute at a default that already equals nil. Without the canonical
      # seed these stay green if the hook becomes a no-op.
      [
        { snake: "align_group", camel: "alignGroup",
          seed: "preset", reader: :align_group },
        { snake: "align_direction", camel: "alignDirection",
          seed: "vertical", reader: :align_direction },
        { snake: "relative_to", camel: "relativeTo",
          seed: "seednode", reader: :relative_to },
      ].each do |field|
        it "lets a null #{field[:camel]} overwrite a canonical value" do
          constraints = described_class.from_yaml(
            "#{field[:snake]}: #{field[:seed]}\n#{field[:camel]}:\n",
          )

          expect(constraints.public_send(field[:reader])).to be_nil
        end
      end

      it "lets a null relativeOffset overwrite a canonical value" do
        constraints = described_class.from_yaml(
          "relative_offset:\n  x: 9.0\n  y: 9.0\nrelativeOffset:\n",
        )

        expect(constraints.relative_offset).to be_nil
      end

      # The standard YAML adapter preserves Symbol keys and lutaml's own
      # mappings resolve either spelling, so the aliases honour both.
      {
        fixedPosition: [:fixed_position, true],
        alignGroup: [:align_group, "db"],
        alignDirection: [:align_direction, "horizontal"],
        relativeTo: [:relative_to, "backend"],
        positionPriority: [:position_priority, 5],
      }.each do |camel, (reader, value)|
        it "reads a Symbol-keyed #{camel} alias" do
          constraints = described_class.from_yaml(YAML.dump(camel => value))

          expect(constraints.public_send(reader)).to eq(value)
        end
      end

      it "reads a Symbol-keyed relativeOffset alias" do
        constraints = described_class.from_yaml(
          YAML.dump(relativeOffset: { "x" => 3.0, "y" => 4.0 }),
        )

        expect([constraints.relative_offset.x, constraints.relative_offset.y])
          .to eq([3.0, 4.0])
      end

      # ACCEPTED RESIDUAL, measured against origin/v2.
      #
      # lutaml unwraps a root rule when the document has exactly one key equal
      # to `to:` (services/rule_value_extractor.rb:36-47) -- whatever the
      # value's type, and whether or not `to:` names an attribute. The sentinel
      # shrinks that collision to documents whose sole key is the literal
      # `__legacy_yaml_aliases`; it does not remove it. Naming a real attribute
      # instead would collide on an ordinary key like `layer`, so the sentinel
      # is still the better target.
      #
      # The guard in the hook makes a nonblank non-Hash collision inert -- a
      # scalar or a nonempty Array, neither of which answers to `key?`; a blank
      # one never reaches the hook at all, because transform.rb:251 drops the
      # rule first. A nonempty Hash is still merged as though it were the
      # document, and that is knowingly accepted: reaching it needs a
      # constraints block whose ONLY key is that literal name, where every real
      # ELK block carries fixedPosition, layer, alignGroup and so on.
      describe "the root-rule sentinel collision" do
        it "merges a Hash-valued sole sentinel key (diverges from base)" do
          constraints = described_class.from_yaml(
            "__legacy_yaml_aliases:\n  fixedPosition: true\n",
          )

          expect(constraints.fixed_position).to be true
        end

        it "ignores a scalar sole sentinel key, as base does" do
          constraints = described_class.from_yaml("__legacy_yaml_aliases: 7\n")

          expect(constraints.fixed_position).to be false
        end

        # The whole justification rests on this: one more key and lutaml stops
        # unwrapping, so the hook sees the real document again.
        # The sentinel collides on a Symbol key too: the extractor compares
        # both spellings (rule_value_extractor.rb:43) and the YAML adapter
        # permits Symbol keys. Same accepted divergence as the String case.
        it "merges a Symbol-keyed sole sentinel key (diverges from base)" do
          constraints = described_class.from_yaml(
            YAML.dump(__legacy_yaml_aliases: { "fixedPosition" => true }),
          )

          expect(constraints.fixed_position).to be true
        end

        it "ignores a Symbol-keyed scalar sentinel, as base does" do
          constraints = described_class.from_yaml(
            YAML.dump(__legacy_yaml_aliases: 7),
          )

          expect(constraints.fixed_position).to be false
        end

        # The second key carries a LEGACY spelling on purpose. Asserting only
        # that fixed_position stayed false and layer arrived would also pass
        # with the hook deleted -- layer comes from the canonical rule and
        # never reaches it. align_group can only be set by the hook, so these
        # actually prove the document reached it.
        it "stops colliding as soon as a second key is present" do
          constraints = described_class.from_yaml(
            "__legacy_yaml_aliases:\n  fixedPosition: true\nalignGroup: g\n",
          )

          expect(constraints.fixed_position).to be false
          expect(constraints.align_group).to eq("g")
        end

        it "stops colliding with a scalar sentinel and a second key" do
          constraints = described_class.from_yaml(
            "__legacy_yaml_aliases: 7\nalignGroup: g\n",
          )

          expect(constraints.fixed_position).to be false
          expect(constraints.align_group).to eq("g")
        end

        it "stops colliding when the sentinel is Symbol-keyed" do
          constraints = described_class.from_yaml(
            YAML.dump(__legacy_yaml_aliases: { "fixedPosition" => true },
                      "alignGroup" => "g"),
          )

          expect(constraints.fixed_position).to be false
          expect(constraints.align_group).to eq("g")
        end
      end

      # A canonical key whose value is a Hash must not be mistaken for the
      # document. lutaml unwraps a root rule when the document is a single key
      # matching `to:`, so `to:` names a sentinel instead of a real attribute.
      # That does NOT make the collision impossible -- see the accepted-residual
      # note above, which pins the case where the sentinel itself is the sole
      # key. It only moves the collision off every ordinary key like `layer`.
      it "does not treat a Hash-valued canonical key as the document" do
        constraints = described_class.from_yaml(
          "layer:\n  fixedPosition: true\n",
        )

        expect(constraints.fixed_position).to be false
      end

      it "does not treat a Hash-valued fixed_position as the document" do
        constraints = described_class.from_yaml(
          "fixed_position:\n  alignGroup: x\n",
        )

        expect(constraints.align_group).to be_nil
      end

      # Every blank shape, every field, matching origin/v2 cell for cell. A
      # per-key custom rule is dropped before it runs when its value is blank
      # (key_value/transform.rb:251); the root-document rule is what preserves
      # these. Values below were captured from origin/v2.
      {
        "fixedPosition" => [:fixed_position,
                            { "" => nil, "''" => "", "[]" => :raise_collection,
                              "{}" => :truthy_wrapper }],
        "alignGroup" => [:align_group,
                         { "" => nil, "''" => "", "[]" => :raise_collection,
                           "{}" => "{}" }],
        "alignDirection" => [:align_direction,
                             { "" => nil, "''" => :raise_format,
                               "[]" => :raise_collection,
                               "{}" => :raise_format }],
        "relativeTo" => [:relative_to,
                         { "" => nil, "''" => "", "[]" => :raise_collection,
                           "{}" => "{}" }],
        "positionPriority" => [:position_priority,
                               { "" => nil, "''" => nil,
                                 "[]" => :raise_collection, "{}" => nil }],
        "relativeOffset" => [:relative_offset,
                             { "" => nil, "''" => :raise_format,
                               "[]" => :raise_collection,
                               "{}" => :zero_offset }],
      }.each do |camel, (reader, shapes)|
        shapes.each do |input, expected|
          it "matches base for #{camel}: #{input.empty? ? 'null' : input}" do
            parse = -> { described_class.from_yaml("#{camel}: #{input}\n") }

            case expected
            when :raise_collection
              expect { parse.call }
                .to raise_error(Lutaml::Model::CollectionTrueMissingError)
            when :raise_format
              expect { parse.call }
                .to raise_error(Lutaml::Model::InvalidFormatError)
            when :zero_offset
              offset = parse.call.public_send(reader)
              expect([offset.x, offset.y]).to eq([0.0, 0.0])
            when :truthy_wrapper
              expect(parse.call.public_send(reader)).to be_truthy
            else
              expect(parse.call.public_send(reader)).to eq(expected)
            end
          end
        end
      end

      # The path the comment above calls risky: an object that arrived through
      # the legacy spelling must serialize like any other.
      it "serializes an offset that arrived through relativeOffset" do
        constraints = described_class.from_yaml(
          "relativeOffset:\n  x: 3.0\n  y: 4.0\n",
        )

        expect(YAML.safe_load(constraints.to_yaml)["relative_offset"])
          .to eq("x" => 3.0, "y" => 4.0)
      end
    end

    # Proves the hooks assign through the public setters rather than writing
    # ivars: the validating setter still rejects a bad value via the alias.
    describe "validation through the legacy alias" do
      it "rejects an invalid alignDirection" do
        expect { described_class.from_yaml("alignDirection: sideways\n") }
          .to raise_error(Lutaml::Model::InvalidFormatError)
      end

      it "rejects an invalid align_direction" do
        expect { described_class.from_yaml("align_direction: sideways\n") }
          .to raise_error(Lutaml::Model::InvalidFormatError)
      end
    end

    # Where both spellings appear the alias wins, fixed by declaration order
    # rather than by key order in the document.
    describe "when a document carries both spellings" do
      it "resolves to the legacy value with snake first" do
        constraints = described_class.from_yaml(
          "fixed_position: true\nfixedPosition: false\n",
        )

        expect(constraints.fixed_position).to be false
      end

      it "resolves to the legacy value with camel first" do
        constraints = described_class.from_yaml(
          "fixedPosition: false\nfixed_position: true\n",
        )

        expect(constraints.fixed_position).to be false
      end

      it "resolves to the legacy value with the polarity reversed" do
        constraints = described_class.from_yaml(
          "fixed_position: false\nfixedPosition: true\n",
        )

        expect(constraints.fixed_position).to be true
      end

      it "resolves distinct string values to the legacy one" do
        constraints = described_class.from_yaml(
          "align_group: snake\nalignGroup: camel\n",
        )

        expect(constraints.align_group).to eq("camel")
      end
    end
  end
end

RSpec.describe Elkrb::Graph::RelativeOffset do
  describe "initialization" do
    it "creates offset with default values" do
      offset = described_class.new

      expect(offset.x).to eq(0.0)
      expect(offset.y).to eq(0.0)
    end

    it "creates offset with custom values" do
      offset = described_class.new(x: 150, y: 75)

      expect(offset.x).to eq(150)
      expect(offset.y).to eq(75)
    end
  end

  describe "JSON serialization" do
    it "serializes to JSON" do
      offset = described_class.new(x: 100, y: 50)

      json = offset.to_json
      parsed = JSON.parse(json)

      expect(parsed["x"]).to eq(100)
      expect(parsed["y"]).to eq(50)
    end

    it "deserializes from JSON" do
      json = '{"x": 200, "y": 100}'

      offset = described_class.from_json(json)

      expect(offset.x).to eq(200)
      expect(offset.y).to eq(100)
    end
  end
end
