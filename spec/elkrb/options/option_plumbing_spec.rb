# frozen_string_literal: true

require "spec_helper"

# For every registered algorithm and every id the registry scopes to it, one
# example that proves the option reaches the layout: a :honoured id moves the
# output, a :accepted id leaves it byte-identical. Each row writes the option
# at the element that owns it, because the resolver reads only the elements
# the caller names. The direct rows are in option_plumbing_direct_spec.rb.
#
# Keep the unwired, read-only, accepted and completeness examples: they pass
# today by design and go red when an id gets wired, a read is removed or the
# registry gains an :honoured id without a row.
RSpec.describe "option plumbing" do
  registry = Elkrb::Options::Registry
  algorithms = Elkrb::Layout::AlgorithmRegistry.available_algorithms
  live_statuses = %i[honoured partial]

  # The registry says :honoured but no code reads the id today. The example
  # asserts the output does NOT move, so wiring the id turns it red and the
  # row has to move to the live table.
  unread = lambda do |why, only: :all|
    { algorithms: only, why: why }
  end
  # The id is read but no 4-node output can show it; the example asserts the
  # resolver was asked for the id.
  read_only = lambda do |why, only: :all|
    { algorithms: only, why: why }
  end
  libavoid_penalty = "no route on this fixture has a cheaper alternative " \
                     "for the penalty to choose"

  # at:        where the option is written (OptionPlumbing::PLACES)
  # value:     what is written; a Proc receives the algorithm name
  # with:      further options written alongside, at their own places
  # variant:   the fixture shape (OptionPlumbing::NODE_VARIANTS); a Hash picks
  #            one per algorithm
  # unwired:   see `unread`
  # read_only: see `read_only`
  cases = {
    "disco.componentAlgorithm" => { at: :root, value: "radial" },
    "disco.componentArrangement" => { at: :root, value: "column" },
    "disco.componentSpacing" => { at: :root, value: 77.0 },
    "elk.algorithm" => {
      at: :root,
      value: ->(name) { name == "radial" ? "box" : "radial" },
    },
    "elk.aspectRatio" => {
      at: :root, value: ->(name) { name == "layered" ? 0.1 : 10.0 }
    },
    "elk.bendPoints" => {
      at: :spline_edge, value: "(1,2; 3,4)",
      unwired: unread[
        "only fixed applies explicit bend points",
        only: algorithms - %w[fixed],
      ]
    },
    "elk.direction" => {
      at: :root,
      value: ->(name) { name == "mrtree" ? "RIGHT" : "DOWN" },
    },
    "elk.disco.componentCompaction.strategy" => { at: :root, value: "ROW" },
    "elk.edgeLabels.placement" => {
      at: :edge, value: "TAIL",
      unwired: unread[
        "fixed edges without sections get no label placement",
        only: %w[fixed],
      ]
    },
    "elk.edgeRouting" => {
      at: :root, value: "SPLINES",
      unwired: unread[
        "fixed preserves existing edge routes; random scatters its own " \
        "bend points", only: %w[fixed random]
      ]
    },
    "elk.force.iterations" => { at: :root, value: 5 },
    "elk.force.repulsion" => { at: :root, value: 50.0 },
    "elk.force.temperature" => { at: :root, value: 0.5 },
    "elk.layered.considerModelOrder.strategy" => {
      at: :root, value: "NODES_AND_EDGES", variant: :fan_in_tie
    },
    "elk.layered.crossingMinimization.strategy" => {
      at: :root, value: "NONE", variant: :sweep_gain
    },
    "elk.layered.layering.layerConstraint" => {
      at: :node, value: "LAST_SEPARATE"
    },
    "elk.layered.spacing.nodeNodeBetweenLayers" => {
      at: :root, value: 200.0
    },
    "elk.nodeLabels.placement" => {
      at: :node, value: "OUTSIDE V_TOP H_LEFT"
    },
    "elk.padding" => {
      at: :root, value: "[top=40,left=40,bottom=40,right=40]"
    },
    "elk.port.index" => {
      at: :port, value: 2,
      with: { node: { "elk.portConstraints" => "FIXED_ORDER" } }
    },
    "elk.port.side" => {
      at: :port, value: "NORTH"
    },
    "elk.portConstraints" => {
      at: :node, value: "FIXED_SIDE",
      read_only: read_only[
        "the fixture's one port already has a fixed side and order",
      ]
    },
    "elk.portLabels.placement" => { at: :port, value: "INSIDE" },
    "elk.position" => { at: :node, value: "(5,5)" },
    "elk.radial.centerOnRoot" => {
      at: :root, value: true,
      read_only: read_only[
        "the fixture's inferred root is already its first node",
        only: %w[radial],
      ]
    },
    "elk.radial.radius" => { at: :root, value: 300.0 },
    "elk.randomSeed" => {
      at: :root, value: 7,
      variant: { "force" => :unpositioned }
    },
    "elk.selfLoopSide" => {
      at: :loop, value: "WEST", variant: :self_loop_only,
      unwired: unread[
        "fixed preserves existing edge routes; random scatters its own " \
        "bend points", only: %w[fixed random]
      ]
    },
    "elk.separateConnectedComponents" => { at: :root, value: false },
    "elk.spacing.componentComponent" => {
      at: :root, value: 90.0,
      unwired: unread[
        "disco reads disco.componentSpacing only", only: %w[disco]
      ]
    },
    "elk.spacing.nodeNode" => {
      at: :root, value: 90.0,
      variant: { "libavoid" => :unpositioned },
      unwired: unread[
        "these algorithms do not read it today",
        only: %w[disco fixed radial spore_compaction spore_overlap stress],
      ]
    },
    "elk.spline.curvature" => {
      at: :spline_edge, value: 0.9,
      unwired: unread[
        "these algorithms preserve or replace this fixture's generic " \
        "spline route", only: %w[fixed libavoid mrtree radial random]
      ]
    },
    "elk.stress.desiredEdgeLength" => { at: :root, value: 300.0 },
    "elk.stress.epsilon" => { at: :root, value: 1e9 },
    "elk.stress.iterationLimit" => { at: :root, value: 1 },
    "label.margin" => {
      at: :node, value: 30.0,
      with: { node: { "label.placement" => "OUTSIDE V_TOP" } }
    },
    "label.padding" => {
      at: :node, value: 30.0,
      with: { node: { "label.placement" => "INSIDE V_TOP" } }
    },
    "label.placement.disabled" => {
      at: :root, value: true,
      read_only: read_only[
        "disco's component layouts have already placed the labels",
        only: %w[disco],
      ]
    },
    "libavoid.bendPenalty" => {
      at: :root, value: 50.0, read_only: read_only[libavoid_penalty]
    },
    "libavoid.maxExpansions" => { at: :root, value: 1 },
    "libavoid.routingPadding" => { at: :root, value: 40.0 },
    "libavoid.segmentPenalty" => {
      at: :root, value: 50.0, read_only: read_only[libavoid_penalty]
    },
    "libavoid.stepSize" => { at: :root, value: 40.0 },
    "spore.compactionDirection" => {
      at: :root, value: "horizontal", variant: :spread
    },
    "spore.maxIterations" => { at: :root, value: 1, variant: :crowded },
    "spore.nodeSpacing" => { at: :root, value: 80.0 },
    "topdownpacking.aspectRatio" => {
      at: :root, value: 5.0, variant: :sizeless
    },
    "topdownpacking.nodeWidth" => {
      at: :root, value: 90.0, variant: :sizeless
    },
    "vertiflex.balanceColumns" => { at: :root, value: false },
    "vertiflex.columnCount" => { at: :root, value: 2 },
    "vertiflex.columnSpacing" => { at: :root, value: 120.0 },
    "vertiflex.verticalSpacing" => { at: :root, value: 99.0 },
  }

  applies = lambda do |setting, name|
    setting &&
      (setting[:algorithms] == :all || setting[:algorithms].include?(name))
  end

  # A value the registry would accept, for the rows that carry no test value.
  accepted_value = lambda do |id|
    entry = registry.all.fetch(id)
    entry[:values]&.last ||
      { float: 77.0, integer: 7, boolean: true }.fetch(entry[:type], "X")
  end

  describe "the table" do
    # option_plumbing_direct_spec carries this :partial id's row.
    direct_ids = ["elk.hierarchyHandling"]

    it "has a row for every honoured or partial id except direct rows" do
      covered = algorithms.flat_map { |name| registry.for_algorithm(name) }
        .select { |id| live_statuses.include?(registry.status(id)) }
        .uniq - direct_ids

      expect(cases.keys.sort).to eq(covered.sort)
    end

    it "lists, in every unwired and read_only entry, only algorithms " \
       "the registry scopes the id to" do
      kinds = %i[unwired read_only]
      stale = cases.flat_map do |id, row|
        kinds.flat_map do |kind|
          listed = row.dig(kind, :algorithms)
          next [] unless listed.is_a?(Array)

          scoped = algorithms.select do |name|
            registry.for_algorithm(name).include?(id)
          end
          (listed - scoped).map { |name| "#{id}: #{kind} lists #{name}" }
        end
      end

      expect(stale).to eq([])
    end
  end

  algorithms.each do |name|
    describe name do
      registry.for_algorithm(name).each do |id|
        status = registry.status(id)

        if %i[honoured partial].include?(status)
          row = cases[id]
          next unless row

          value = row[:value]
          value = value.call(name) if value.respond_to?(:call)
          places = { row[:at] => { id => value } }
          row.fetch(:with, {}).each do |place, extra|
            places[place] = (places[place] || {}).merge(extra)
          end
          # The same places without the option: the two layouts may differ
          # only by it, or a `with:` setting could be what moves the output.
          without_option = places.transform_values { |set| set.except(id) }
          variant = row.fetch(:variant, :default)
          variant = variant.fetch(name, :default) if variant.is_a?(Hash)

          if applies.call(row[:unwired], name)
            it "#{id} is not read yet (#{row[:unwired][:why]})" do
              expect(plumbing_geometry(name, places, variant: variant))
                .to eq(plumbing_geometry(name, without_option,
                                         variant: variant))
            end
          elsif applies.call(row[:read_only], name)
            it "#{id} is read, though no output shows it " \
               "(#{row[:read_only][:why]})" do
              expect(plumbing_reads(name, places, variant: variant))
                .to include(id)
            end
          else
            it "#{id} changes the output" do
              expect(plumbing_geometry(name, places, variant: variant))
                .not_to eq(plumbing_geometry(name, without_option,
                                             variant: variant))
            end
          end
        elsif %i[accepted unsupported].include?(status)
          # An id whose only legal value is its default sets the same value
          # in both layouts, so no wiring could make the two differ.
          entry = registry.all.fetch(id)
          next if entry[:values] == [entry[:default]]

          it "#{id} (#{status}) leaves the output byte-identical" do
            places = { root: { id => accepted_value.call(id) } }

            expect(plumbing_geometry(name, places))
              .to eq(plumbing_geometry(name, {}))
          end
        end
      end
    end
  end
end
