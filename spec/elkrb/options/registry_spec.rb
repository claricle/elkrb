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

    it "parses a KVectorChain in ELK's own canonical format" do
      chain = described_class.coerce("elk.bendPoints", "(1,2; 3,4)")
      expect(chain.vectors.size).to eq(2)
    end
  end

  describe ".default" do
    it "returns the ELK-real default for elk.direction" do
      expect(described_class.default("elk.direction")).to eq("UNDEFINED")
    end

    it "returns nil for an id with no default" do
      expect(described_class.default("elk.position")).to be_nil
    end
  end

  describe ".status" do
    it "reports :honoured for core ids" do
      expect(described_class.status("elk.spacing.nodeNode")).to eq(:honoured)
    end

    it "reports :accepted for a self-loop id with no wired read today" do
      expect(described_class.status("elk.selfLoopOffset")).to eq(:accepted)
    end

    it "reports :accepted for edgeNode/edgeEdge spacing (sirena emits them; not honoured until S25b)" do
      expect(described_class.status("elk.spacing.edgeNode")).to eq(:accepted)
      expect(described_class.status("elk.spacing.edgeEdge")).to eq(:accepted)
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
  end
end
