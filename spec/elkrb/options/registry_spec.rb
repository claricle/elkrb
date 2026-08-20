# frozen_string_literal: true

require "spec_helper"

RSpec.describe Elkrb::Options::Registry do
  describe "OPTIONS table" do
    it "gives every id a type and a default key (default may be nil)" do
      described_class.all.each do |id, entry|
        expect(entry).to have_key(:type), "#{id} is missing :type"
        expect(entry).to have_key(:default), "#{id} is missing :default"
        expect(entry).to have_key(:algorithms), "#{id} is missing :algorithms"
        expect(entry).to have_key(:status), "#{id} is missing :status"
      end
    end

    it "maps every alias back to the id that declared it" do
      described_class.all.each do |id, entry|
        Array(entry[:aliases]).each do |a|
          expect(described_class.canonical(a)).to eq(id), "alias #{a} should resolve to #{id}"
        end
      end
    end

    it "registers position and bendPoints as aliases (Card S4's explicit list)" do
      expect(described_class.canonical("position")).to eq("elk.position")
      expect(described_class.canonical("bendPoints")).to eq("elk.bendPoints")
    end

    it "is frozen at every level it exposes" do
      expect(described_class.all).to be_frozen
      expect(described_class.all["elk.direction"]).to be_frozen
      expect(described_class.all["elk.direction"][:aliases]).to be_frozen
      expect(described_class.all["elk.direction"][:values]).to be_frozen
    end
  end

  describe ".canonical" do
    it "returns an exact id unchanged" do
      expect(described_class.canonical("elk.direction")).to eq("elk.direction")
    end

    it "strips the org.eclipse.elk. prefix" do
      expect(described_class.canonical("org.eclipse.elk.direction")).to eq("elk.direction")
    end

    it "resolves a legacy snake_case alias" do
      expect(described_class.canonical("spacing_node_node")).to eq("elk.spacing.nodeNode")
    end

    it "resolves a bare dotted suffix" do
      expect(described_class.canonical("spacing.nodeNode")).to eq("elk.spacing.nodeNode")
    end

    it "returns nil for an unknown key" do
      expect(described_class.canonical("nope")).to be_nil
    end

    it "resolves direction via the explicit alias" do
      expect(described_class.canonical("direction")).to eq("elk.direction")
    end

    it "returns nil for a bare suffix shared by more than one id, rather than guessing" do
      expect(described_class.canonical("placement")).to be_nil
      expect(described_class.canonical("strategy")).to be_nil
    end

    it "resolves a longer suffix that uniquely disambiguates among same-tail strategy ids" do
      expect(described_class.canonical("nodePlacement.strategy")).to eq("elk.layered.nodePlacement.strategy")
    end

    it "resolves aspectRatio to the ELK id even though a private id shares the same bare suffix" do
      expect(described_class.canonical("aspectRatio")).to eq("elk.aspectRatio")
    end
  end

  describe ".coerce" do
    it "coerces a numeric string to Float" do
      expect(described_class.coerce("elk.spacing.nodeNode", "40")).to eq(40.0)
    end

    it "parses an ELK padding string" do
      padding = described_class.coerce("elk.padding", "[top=1,left=2,bottom=3,right=4]")
      expect(padding).to be_a(Elkrb::Options::ElkPadding)
      expect(padding.to_h).to eq(top: 1.0, left: 2.0, bottom: 3.0, right: 4.0)
    end

    it "fills missing padding hash keys with the registry default (12)" do
      padding = described_class.coerce("elk.padding", { top: 5 })
      expect(padding.to_h).to eq(top: 5.0, left: 12.0, bottom: 12.0, right: 12.0)
    end

    it "treats a bare Numeric padding value as uniform on all sides" do
      padding = described_class.coerce("elk.padding", 7)
      expect(padding.to_h).to eq(top: 7.0, left: 7.0, bottom: 7.0, right: 7.0)
    end

    it "raises ArgumentError for a padding value that is none of String/Hash/Numeric/ElkPadding" do
      expect { described_class.coerce("elk.padding", nil) }.to raise_error(ArgumentError, /Invalid padding value/)
      expect { described_class.coerce("elk.padding", [1, 2]) }.to raise_error(ArgumentError, /Invalid padding value/)
    end

    it "parses a KVectorChain in ELK's own canonical format" do
      chain = described_class.coerce("elk.bendPoints", "(1,2; 3,4)")
      expect(chain.vectors.size).to eq(2)
    end

    it "upcases a string to match its enum values" do
      expect(described_class.coerce("elk.direction", "right")).to eq("RIGHT")
    end

    it "passes booleans through and parses the literal string true (any case)" do
      expect(described_class.coerce("hierarchical", true)).to be(true)
      expect(described_class.coerce("hierarchical", false)).to be(false)
      expect(described_class.coerce("hierarchical", "true")).to be(true)
      expect(described_class.coerce("hierarchical", "TRUE")).to be(true)
    end

    it "treats non-'true' strings as false, including '1' and 'yes' (strict, no numeric/word aliases)" do
      expect(described_class.coerce("hierarchical", "1")).to be(false)
      expect(described_class.coerce("hierarchical", "yes")).to be(false)
    end

    it "coerces a numeric string to Integer" do
      expect(described_class.coerce("elk.port.index", "3")).to eq(3)
    end

    it "parses a KVector" do
      vector = described_class.coerce("elk.position", [1, 2])
      expect(vector.to_h).to eq(x: 1.0, y: 2.0)
    end

    it "passes the value through unchanged for an unknown id" do
      expect(described_class.coerce("nope_unknown_id", "raw")).to eq("raw")
    end

    it "resolves an alias before coercing" do
      expect(described_class.coerce("spacing_node_node", "50")).to eq(50.0)
    end
  end

  describe ".default" do
    it "returns the ELK-real default for elk.direction" do
      expect(described_class.default("elk.direction")).to eq("UNDEFINED")
    end

    it "returns nil for an id with no default" do
      expect(described_class.default("elk.position")).to be_nil
    end

    it "returns false, not nil, for a boolean id whose default is literally false" do
      expect(described_class.default("label.placement.disabled")).to be(false)
    end

    it "returns an ElkPadding for elk.padding's default" do
      expect(described_class.default("elk.padding")).to be_a(Elkrb::Options::ElkPadding)
    end
  end

  describe ".status" do
    it "reports :honoured for core ids" do
      expect(described_class.status("elk.spacing.nodeNode")).to eq(:honoured)
    end

    it "reports :accepted for a self-loop id with no wired read today" do
      expect(described_class.status("elk.selfLoopOffset")).to eq(:accepted)
    end

    it "reports :accepted for edgeNode/edgeEdge spacing (sirena emits them; not honoured today)" do
      expect(described_class.status("elk.spacing.edgeNode")).to eq(:accepted)
      expect(described_class.status("elk.spacing.edgeEdge")).to eq(:accepted)
    end

    it "reports :partial for elk.hierarchyHandling, with a non-empty note" do
      expect(described_class.status("elk.hierarchyHandling")).to eq(:partial)
      expect(described_class.note("elk.hierarchyHandling")).not_to be_empty
    end
  end

  describe "consumer-contract table rows (remediation plan)" do
    # Every id the consumer-contract table lists gets its own registry
    # row with that table's status — S16-S19/S25a flip status/default on
    # these same rows in place, never add duplicates.
    it "registers every contract row pre-seeded for a later slice" do
      accepted_ids = %w[
        elk.spacing.edgeNode
        elk.spacing.edgeEdge
        elk.layered.nodePlacement.strategy
        elk.layered.considerModelOrder.strategy
        elk.layered.crossingMinimization.strategy
        elk.layered.compaction.postCompaction.strategy
        elk.box.packingMode
        elk.layered.layering.layerConstraint
        elk.radial.centerOnRoot
        elk.disco.componentCompaction.strategy
      ]

      accepted_ids.each do |id|
        expect(described_class.status(id)).to eq(:accepted), "#{id} should be :accepted"
      end
    end

    it "sorts every row by canonical id" do
      expect(described_class.all.keys).to eq(described_class.all.keys.sort)
    end
  end

  describe ".for_algorithm" do
    it "includes core ids for every algorithm" do
      expect(described_class.for_algorithm("box")).to include("elk.spacing.nodeNode")
    end

    it "includes layered-only ids for layered" do
      expect(described_class.for_algorithm("layered")).to include(
        "elk.direction", "elk.layered.spacing.nodeNodeBetweenLayers"
      )
    end

    it "excludes layered-only ids for box" do
      expect(described_class.for_algorithm("box")).not_to include(
        "elk.layered.spacing.nodeNodeBetweenLayers"
      )
    end

    it "scopes aspectRatio to box/random and randomSeed to force/random, excluding stress" do
      expect(described_class.for_algorithm("box")).to include("elk.aspectRatio")
      expect(described_class.for_algorithm("random")).to include("elk.aspectRatio", "elk.randomSeed")
      expect(described_class.for_algorithm("force")).to include("elk.randomSeed")
      expect(described_class.for_algorithm("stress")).not_to include("elk.aspectRatio", "elk.randomSeed")
    end

    it "excludes algorithms: :all ids when include_all is false" do
      expect(described_class.for_algorithm("box", include_all: false)).not_to include("elk.padding")
      expect(described_class.for_algorithm("box", include_all: false)).to include("elk.aspectRatio")
    end
  end

  describe ".render_known_options" do
    it "renders the documented shape and patches in the given algorithm values" do
      rendered = described_class.render_known_options(algorithm_values: %w[layered force])

      expect(rendered["elk.algorithm"][:values]).to eq(%w[layered force])
      expect(rendered["elk.spacing.nodeNode"]).to eq(
        type: :float,
        description: "Spacing between nodes",
        default: 20.0,
        values: nil,
        parser: nil,
        status: :honoured,
        note: nil,
      )
      expect(rendered["elk.padding"][:parser]).to eq("Elkrb::Options::ElkPadding")
    end
  end
end
