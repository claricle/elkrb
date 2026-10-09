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
          expect(described_class.canonical(a)).to eq(id),
                                                  "alias #{a} should resolve to #{id}"
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
      padding = described_class.coerce("elk.padding",
                                       "[top=1,left=2,bottom=3,right=4]")
      expect(padding).to be_a(Elkrb::Options::ElkPadding)
      expect(padding.to_h).to eq(top: 1.0, left: 2.0, bottom: 3.0, right: 4.0)
    end

    it "fills missing padding hash keys with the registry default (12)" do
      padding = described_class.coerce("elk.padding", { top: 5 })
      expect(padding.to_h).to eq(top: 5.0, left: 12.0, bottom: 12.0,
                                 right: 12.0)
    end

    it "treats a bare Numeric padding value as uniform on all sides" do
      padding = described_class.coerce("elk.padding", 7)
      expect(padding.to_h).to eq(top: 7.0, left: 7.0, bottom: 7.0, right: 7.0)
    end

    it "raises ArgumentError for a padding value that is none of String/Hash/Numeric/ElkPadding" do
      expect do
        described_class.coerce("elk.padding",
                               nil)
      end.to raise_error(ArgumentError, /Invalid padding value/)
      expect do
        described_class.coerce("elk.padding",
                               [1, 2])
      end.to raise_error(ArgumentError, /Invalid padding value/)
    end

    it "parses a KVectorChain in ELK's own canonical format" do
      chain = described_class.coerce("elk.bendPoints", "(1,2; 3,4)")
      expect(chain.vectors.size).to eq(2)
    end

    it "upcases a string to match its enum values" do
      expect(described_class.coerce("elk.direction", "right")).to eq("RIGHT")
    end

    it "passes booleans through and parses the literal string true (any case)" do
      id = "label.placement.disabled"
      expect(described_class.coerce(id, true)).to be(true)
      expect(described_class.coerce(id, false)).to be(false)
      expect(described_class.coerce(id, "true")).to be(true)
      expect(described_class.coerce(id, "TRUE")).to be(true)
    end

    it "treats non-'true' strings as false, including '1' and 'yes' (strict, no numeric/word aliases)" do
      id = "label.placement.disabled"
      expect(described_class.coerce(id, "1")).to be(false)
      expect(described_class.coerce(id, "yes")).to be(false)
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
    it "returns RIGHT as the public default for elk.direction" do
      expect(described_class.default("elk.direction")).to eq("RIGHT")
    end

    it "returns ELK's 20px default layered gap" do
      expect(described_class.default(
               "elk.layered.spacing.nodeNodeBetweenLayers",
             )).to eq(20.0)
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
    it "reports :honoured for elk.algorithm" do
      expect(described_class.status("elk.algorithm")).to eq(:honoured)
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

  # OptionRouteRows lays out every carrier x spelling x shape x positioning x
  # algorithm at two values. A row must move exactly when `readers` lists it,
  # so list a reader rather than adding a row. Status follows the rows: all
  # move -> :honoured, none -> :accepted, some -> :partial, counting only the
  # algorithms the entry's `algorithms` scope names and the carriers the
  # option applies to (`carriers`). A route outside that scope is still probed
  # and must move exactly as `readers` records, but it does not decide the
  # status. When a route gets wired, add its reader and change the registry's
  # status and note.
  describe "status agrees with what layout reads" do
    include OptionRouteProbe

    algorithms = Elkrb::Layout::AlgorithmRegistry.available_algorithms
    by_positioning = OptionRouteRows.method(:by_positioning)
    # elkjs 0.11 (knownLayoutOptions) targets these three options at parents
    # (padding also at nodes), never at an edge, so an edge's layoutOptions
    # does not decide their status. elk.direction is a parent target too, but
    # elkrb reads an edge's own direction, which its :partial note documents,
    # so every carrier applies to it.
    parent_carriers = OptionRouteRows::CARRIERS - %i[edge]

    spacing = { value: [5, 80] }
    box = ->(v) { { top: v, left: v, bottom: v, right: v } }
    padding = {
      sym_hash: [5, 50].map(&box),
      str_hash: [5, 50].map { |v| box.call(v).transform_keys(&:to_s) },
      number: [5, 50],
      elk_string: [5, 50].map { |v| "[top=#{v},left=#{v},bottom=#{v},right=#{v}]" },
    }

    # Measured: direction reaches SPLINES routing from an edge or the call
    # options under every resolver spelling. Fixed preserves edge routes and
    # libavoid routes its own connectors; spore_compaction gives the same
    # output at both directions when no node has an input position. MRTree
    # also reads direction from parent options.
    call_direction = by_positioning.call(
      algorithms - %w[fixed libavoid radial],
      unpositioned: algorithms - %w[fixed libavoid radial spore_compaction],
      first_only: algorithms - %w[fixed libavoid radial],
    )
    edge_direction = by_positioning.call(
      algorithms - %w[fixed libavoid mrtree radial],
      unpositioned: algorithms - %w[fixed libavoid mrtree radial spore_compaction],
      first_only: algorithms - %w[fixed libavoid mrtree radial],
    )
    direction = "elk.direction"
    direction_spellings =
      OptionRouteRows.spellings_for(direction, "direction")
    direction_readers = OptionRouteRows::CARRIERS.product(direction_spellings)
      .to_h do |carrier, spelling|
      readers =
        case carrier
        when :call_string, :call_symbol then call_direction
        when :edge then edge_direction
        when :compound_none then %w[disco layered mrtree]
        else %w[layered mrtree]
        end
      [[carrier, spelling, :value], readers]
    end
    # Measured: every carrier an option applies to reads padding in every
    # shape and spelling, for every algorithm.
    padding_spellings = OptionRouteRows.spellings_for("elk.padding", "padding")
    padding_routes = parent_carriers.product(padding_spellings, padding.keys)
    padding_readers = padding_routes.to_h { |route| [route, algorithms] }

    # Measured: every spelling, as a call option under either key kind or in
    # the layoutOptions of the graph or a compound node, moves layered. An
    # edge's layoutOptions moves nothing.
    layer_spacing = "elk.layered.spacing.nodeNodeBetweenLayers"
    layer_spacing_readers =
      parent_carriers.product(
        OptionRouteRows.spellings_for(layer_spacing, "layer_spacing"),
      ).to_h do |carrier, spelling|
        [[carrier, spelling, :value],
         carrier == :compound_none ? %w[disco layered] : %w[layered]]
      end

    # Measured: the same algorithms read every spelling from the call options
    # and from the layoutOptions of the graph or a compound node (a compound
    # without its own elk.algorithm also moves disco); libavoid only when a
    # node lacks an input position; vertiflex from call options or
    # layoutOptions under every spelling.
    node_node = "elk.spacing.nodeNode"
    node_node_readers =
      parent_carriers.product(
        OptionRouteRows.spellings_for(node_node, "spacing_node_node"),
      ).to_h do |carrier, spelling|
        readers = %w[box force layered mrtree random rectpacking topdownpacking]
        readers << "disco" if carrier == :compound_none
        if carrier != :edge
          readers << "vertiflex"
        end
        [[carrier, spelling, :value],
         by_positioning.call(readers, unpositioned: readers + %w[libavoid])]
      end

    {
      direction => {
        internal: "direction", shapes: { value: %w[RIGHT DOWN] },
        readers: direction_readers
      },
      layer_spacing => {
        internal: "layer_spacing", shapes: spacing,
        carriers: parent_carriers, readers: layer_spacing_readers
      },
      "elk.padding" => {
        internal: "padding", shapes: padding, readers: padding_readers,
        carriers: parent_carriers
      },
      node_node => {
        internal: "spacing_node_node", shapes: spacing,
        carriers: parent_carriers, readers: node_node_readers
      },
    }.each do |id, spec|
      spellings = OptionRouteRows.spellings_for(id, spec.fetch(:internal))
      rows = OptionRouteRows.rows(spellings: spellings, algorithms: algorithms,
                                  **spec.except(:internal))

      it "#{id}: each route moves layout or not as recorded, and status matches" do
        moved = rows.transform_values { |args, _| option_moves_layout?(**args) }
        wrong = moved.reject { |label, moves| moves == rows.fetch(label)[1] }

        expect(wrong.keys).to eq([])
        expect(described_class.status(id))
          .to eq(OptionRouteRows.expected_status(id, rows, moved))
      end
    end

    # The rows above hold node_node_readers to what layout does. An algorithm
    # the registry lists as a reader makes strict mode accept the key, so it
    # must move on every route, with every node positioned.
    it "#{node_node}: the registry's readers are the algorithms every route moves" do
      every_route = node_node_readers.values.map { |by| by.fetch(true) }

      expect(described_class.all.fetch(node_node).fetch(:readers))
        .to eq(every_route.reduce(:&).sort)
    end
  end

  describe "readers" do
    algorithms = Elkrb::Layout::AlgorithmRegistry.available_algorithms
    with_readers = described_class.all.select { |_, entry| entry[:readers] }

    # Keep: the examples after the first pass while no id lists readers; they
    # become the only check on a new row's readers.
    it "lists them on at least one id, so the examples below are not vacuous" do
      expect(with_readers.keys).to include("elk.spacing.nodeNode")
    end

    it "lists them only on :partial ids" do
      expect(with_readers.reject { |_, entry| entry[:status] == :partial }.keys)
        .to eq([])
    end

    it "names only registered algorithms, in scope for the id" do
      stray = with_readers.flat_map do |id, entry|
        scope = entry[:algorithms] == :all ? algorithms : entry[:algorithms]
        (entry[:readers] - (algorithms & scope)).map { |name| [id, name] }
      end

      expect(stray).to eq([])
    end

    it "names every reader in the note, and says nothing about them in it twice" do
      with_readers.each do |id, entry|
        expect(described_class.note(id)).to start_with("Read by #{entry[:readers].join(', ')}. ")
        expect(entry[:note])
          .not_to match(/\b(?:#{entry[:readers].join('|')})\b/)
      end
    end

    it "gives an id without readers its plain note, and an unknown id none" do
      expected = [
        described_class.all.fetch("elk.hierarchyHandling").fetch(:note), nil
      ]
      expect([described_class.note("elk.hierarchyHandling"),
              described_class.note("elk.nonesuch")])
        .to eq(expected)
    end

    it "answers read_by? for a reader, a non-reader and an id with none" do
      expect([
               described_class.read_by?("elk.spacing.nodeNode", "layered"),
               described_class.read_by?("elk.spacing.nodeNode", "force"),
               described_class.read_by?("spacing_node_node", "box"),
               described_class.read_by?("elk.direction", "layered"),
               described_class.read_by?("foo.bar", "layered"),
             ]).to eq([true, true, true, true, false])
    end
  end

  describe "partial notes" do
    # Keep: it passes against any registry whose :partial rows all carry a
    # note, so it protects nothing until a row is marked :partial without
    # one, and then it is the only check that the warning has text.
    it "carries a non-empty note on every :partial id" do
      missing = described_class.all.select do |id, entry|
        entry[:status] == :partial && described_class.note(id).to_s.strip.empty?
      end

      expect(missing.keys).to eq([])
    end
  end

  # libavoid_spec.rb ("with an edgeRouting style and an edge direction set")
  # holds the behaviour these two rows describe.
  describe "the edge routing options libavoid does not apply to its own routes" do
    {
      "elk.edgeRouting" => %w[fixed libavoid],
      "elk.spline.curvature" => %w[fixed libavoid mrtree radial],
    }.each do |id, nonreaders|
      it "records #{id} as partial and not read by libavoid" do
        expect(described_class.status(id)).to eq(:partial)
        expect(described_class.read_by?(id, "layered")).to be(true)
        expect(described_class.read_by?(id, "libavoid")).to be(false)
        expect(described_class.note(id)).to include("libavoid ")
      end

      it "lists exactly its measured readers" do
        readers = described_class.all.fetch(id)[:readers]
        expect(readers.sort)
          .to eq(Elkrb::Layout::AlgorithmRegistry.available_algorithms - nonreaders)
      end
    end
  end

  describe "elk.direction outside layout" do
    it "says DOT export reads it as elk.direction or direction" do
      expect(described_class.note("elk.direction"))
        .to match(/DOT export.*every registered spelling/)
    end

    directions = %w[RIGHT DOWN]
    %w[elk.direction direction].each do |key|
      it "is read by DOT export from the graph's layoutOptions as #{key}" do
        rankdirs = directions.map do |direction|
          graph = Elkrb::Graph::Graph.from_json({
            id: "root", layoutOptions: { key => direction },
            children: [{ id: "a", width: 30, height: 30 }]
          }.to_json)
          Elkrb.export_dot(graph)[/rankdir=\w+/]
        end
        expect(rankdirs).to eq(%w[rankdir=LR rankdir=TB])
      end
    end

    it "reads org.eclipse.elk.direction from the graph's layoutOptions" do
      graph = Elkrb::Graph::Graph.from_json({
        id: "root", layoutOptions: { "org.eclipse.elk.direction" => "RIGHT" },
        children: [{ id: "a", width: 30, height: 30 }]
      }.to_json)
      expect(Elkrb.export_dot(graph)).to include("rankdir=LR")
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
        elk.disco.componentCompaction.strategy
      ]

      accepted_ids.each do |id|
        expect(described_class.status(id)).to eq(:accepted),
                                              "#{id} should be :accepted"
      end
      expect(described_class.status("elk.radial.centerOnRoot")).to eq(:honoured)
      expect(described_class.status("elk.layered.layering.layerConstraint"))
        .to eq(:honoured)
    end

    it "describes elk.disco.componentCompaction.strategy with ELK's contract, not the arrangement values" do
      id = "elk.disco.componentCompaction.strategy"

      expect(described_class.default(id)).to eq("POLYOMINO")
      expect(described_class.all[id][:values]).to eq(%w[POLYOMINO])
      expect(described_class.default("disco.componentArrangement")).to eq("row")
    end

    it "sorts every row by canonical id" do
      expect(described_class.all.keys).to eq(described_class.all.keys.sort)
    end

    it "pins the real ELK enum values for the three layered strategy rows (verified against elkjs's enum construction order)" do
      expect(described_class.all["elk.layered.considerModelOrder.strategy"][:values]).to eq(
        %w[NONE NODES_AND_EDGES PREFER_EDGES PREFER_NODES],
      )
      expect(described_class.all["elk.layered.crossingMinimization.strategy"][:values]).to eq(
        %w[LAYER_SWEEP MEDIAN_LAYER_SWEEP INTERACTIVE NONE],
      )
      expect(described_class.all["elk.layered.nodePlacement.strategy"][:values]).to eq(
        %w[SIMPLE INTERACTIVE LINEAR_SEGMENTS BRANDES_KOEPF NETWORK_SIMPLEX],
      )
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
        "elk.layered.spacing.nodeNodeBetweenLayers",
      )
    end

    it "scopes aspectRatio to box/random and randomSeed to force/random, excluding stress" do
      expect(described_class.for_algorithm("box")).to include("elk.aspectRatio")
      expect(described_class.for_algorithm("random")).to include(
        "elk.aspectRatio", "elk.randomSeed"
      )
      expect(described_class.for_algorithm("force")).to include("elk.randomSeed")
      expect(described_class.for_algorithm("stress")).not_to include(
        "elk.aspectRatio", "elk.randomSeed"
      )
    end

    it "excludes algorithms: :all ids when include_all is false" do
      expect(described_class.for_algorithm("box",
                                           include_all: false)).not_to include("elk.padding")
      expect(described_class.for_algorithm("box",
                                           include_all: false)).to include("elk.aspectRatio")
    end
  end

  describe ".render_known_options" do
    it "renders the documented shape and patches in the given algorithm values" do
      rendered = described_class.render_known_options(algorithm_values: %w[
                                                        layered force
                                                      ])

      expect(rendered["elk.algorithm"][:values]).to eq(%w[layered force])
      expect(rendered["elk.spacing.nodeNode"]).to eq(
        type: :float,
        description: "Spacing between nodes",
        default: 20.0,
        values: nil,
        parser: nil,
        status: :partial,
        note: described_class.note("elk.spacing.nodeNode"),
      )
      expect(rendered["elk.padding"][:parser]).to eq("Elkrb::Options::ElkPadding")
    end
  end
end

RSpec.describe "boolean coercion keeps the value as the receiver" do
  # An object that delegates == answers for itself. Comparing the other way
  # round — `true == value`, which both Array#include? and any?(value) do —
  # unwraps it and hands back a native boolean instead.
  it "returns a delegating wrapper unchanged" do
    require "delegate"
    wrapped = SimpleDelegator.new(true)

    expect(Elkrb::Options::Registry.coerce("elk.radial.centerOnRoot", wrapped))
      .to be(wrapped)
  end

  it "still coerces the ordinary shapes" do
    coerced = %w[true TRUE false yes].map do |value|
      Elkrb::Options::Registry.coerce("elk.radial.centerOnRoot", value)
    end

    expect(coerced).to eq([true, true, false, false])
  end
end
