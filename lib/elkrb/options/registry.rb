# frozen_string_literal: true

require_relative "elk_padding"
require_relative "k_vector"
require_relative "k_vector_chain"

module Elkrb
  module Options
    # Single source of truth for ELK/elkrb layout option metadata: id,
    # type, default, allowed values, aliases, owning algorithms, and the
    # elkrb 2.0 truthfulness status. Elkrb.known_layout_options,
    # LayoutEngine.known_layout_options, and AlgorithmRegistry#algorithm_info
    # all read from OPTIONS through the methods below — nothing else does.
    class Registry
      ELK_PREFIX = "org.eclipse.elk."
      BOOLEAN_LITERALS = [true, false].freeze
      private_constant :BOOLEAN_LITERALS
      private_constant :ELK_PREFIX

      # The OPTIONS constant name/path is private; .all below returns
      # this same frozen object, so use .all (or .canonical/.coerce/
      # .default/.status/.note/.for_algorithm) rather than reaching for
      # the constant directly. Rows are sorted by id; insert new rows in
      # sorted position, never at the end.
      # rubocop:disable Layout/LineLength
      OPTIONS = {
        "disco.componentAlgorithm" => { type: :string, default: "layered", namespace: :elkrb, algorithms: %w[disco], status: :honoured, description: "Algorithm used to lay out each component" },
        "disco.componentArrangement" => { type: :string, values: %w[row column grid], default: "row", namespace: :elkrb, algorithms: %w[disco], status: :honoured, description: "How components are arranged" },
        "disco.componentSpacing" => { type: :float, default: 20.0, namespace: :elkrb, algorithms: %w[disco], status: :honoured, description: "Spacing between components" },
        "elk.algorithm" => { type: :string, default: "layered", aliases: %w[algorithm], algorithms: :all, status: :honoured, description: "The layout algorithm to use" },
        "elk.aspectRatio" => { type: :float, default: 1.6, aliases: %w[aspectRatio aspect_ratio], algorithms: %w[box random], status: :honoured, description: "Target width/height ratio (box, random)" },
        "elk.bendPoints" => { type: :kvector_chain, default: nil, aliases: %w[bendPoints], algorithms: :all, status: :honoured, description: "Manual bend points for an edge" },
        "elk.box.packingMode" => { type: :enum, values: %w[SIMPLE GROUP_DEC GROUP_MIXED GROUP_INC], default: "SIMPLE", algorithms: %w[box], status: :accepted, description: "Box layout packing mode; not honoured today (S16 implements SIMPLE, others fall back to it)" },
        "elk.direction" => { type: :enum, values: %w[UNDEFINED RIGHT LEFT DOWN UP], default: "UNDEFINED", aliases: %w[direction], algorithms: %w[layered mrtree], status: :honoured, description: "Overall direction of layout" },
        "elk.disco.componentCompaction.strategy" => { type: :enum, values: %w[POLYOMINO], default: "POLYOMINO", algorithms: %w[disco], status: :accepted, description: "DisCo component compaction; not honoured today. Arrangement is a separate concern elkrb reads as disco.componentArrangement" },
        "elk.edgeLabels.placement" => { type: :string, default: "CENTER", algorithms: :all, status: :honoured, description: "Edge label placement" },
        "elk.edgeRouting" => { type: :enum, values: %w[UNDEFINED POLYLINE ORTHOGONAL SPLINES], default: "UNDEFINED", aliases: %w[edgeRouting edge_routing edge.routing], algorithms: :all, status: :honoured, description: "Edge routing style" },
        "elk.force.iterations" => { type: :integer, default: 300, aliases: %w[iterations], algorithms: %w[force], status: :honoured, description: "Force simulation iteration count" },
        "elk.force.repulsion" => { type: :float, default: 5.0, aliases: %w[repulsion], algorithms: %w[force], status: :honoured, description: "Force simulation repulsion strength" },
        "elk.force.temperature" => { type: :float, default: 0.001, aliases: %w[temperature], algorithms: %w[force], status: :honoured, description: "Force simulation cooling temperature" },
        "elk.hierarchyHandling" => { type: :enum, values: %w[INHERIT INCLUDE_CHILDREN SEPARATE_CHILDREN], default: "INHERIT", algorithms: :all, status: :partial, note: "cross-level edges are routed; no cross-level layering", description: "Whether a compound node's children are laid out separately or together with it" },
        "elk.layered.compaction.postCompaction.strategy" => { type: :enum, values: %w[NONE LEFT RIGHT LEFT_RIGHT_CONSTRAINT_LOCKING LEFT_RIGHT_CONNECTION_LOCKING EDGE_LENGTH], default: "NONE", algorithms: %w[layered], status: :accepted, description: "Post-layout compaction strategy; not honoured today" },
        "elk.layered.considerModelOrder.strategy" => { type: :enum, values: %w[NONE NODES_AND_EDGES PREFER_EDGES PREFER_NODES], default: "NONE", algorithms: %w[layered], status: :accepted, description: "Whether to preserve model node/edge order as a crossing-minimization tie-break; not honoured today" },
        "elk.layered.crossingMinimization.strategy" => { type: :enum, values: %w[LAYER_SWEEP MEDIAN_LAYER_SWEEP INTERACTIVE NONE], default: "LAYER_SWEEP", algorithms: %w[layered], status: :accepted, description: "Crossing minimization strategy; LAYER_SWEEP honoured from S25a" },
        "elk.layered.layering.layerConstraint" => { type: :enum, values: %w[NONE FIRST FIRST_SEPARATE LAST LAST_SEPARATE], default: "NONE", algorithms: %w[layered], status: :accepted, description: "Forces a node to a specific layer position; honoured from S19" },
        "elk.layered.nodePlacement.strategy" => { type: :enum, values: %w[SIMPLE INTERACTIVE LINEAR_SEGMENTS BRANDES_KOEPF NETWORK_SIMPLEX], default: "SIMPLE", algorithms: %w[layered], status: :accepted, description: "Node placement strategy; not honoured today (elkrb implements SIMPLE only, others fall back to it)" },
        "elk.layered.spacing.nodeNodeBetweenLayers" => { type: :float, default: 60.0, aliases: %w[layer_spacing layered.spacing.nodeNodeBetweenLayers], algorithms: %w[layered], status: :honoured, description: "Spacing between layers (ELK's own default is 20.0; elkrb currently defaults to 60.0)" },
        "elk.nodeLabels.placement" => { type: :string, default: "INSIDE CENTER", aliases: %w[node.label.placement label.placement], algorithms: :all, status: :honoured, description: "Node label placement" },
        "elk.padding" => { type: :padding, default: "[top=12,left=12,bottom=12,right=12]", aliases: %w[padding], algorithms: :all, status: :honoured, description: "Padding around the graph" },
        "elk.port.index" => { type: :integer, default: -1, aliases: %w[port.index], algorithms: :all, status: :honoured, description: "Order of a port among its side's ports" },
        "elk.port.side" => { type: :enum, values: %w[NORTH SOUTH EAST WEST UNDEFINED], default: "UNDEFINED", aliases: %w[port.side], algorithms: :all, status: :honoured, description: "Side of the node a port is attached to" },
        "elk.portConstraints" => { type: :enum, values: %w[UNDEFINED FREE FIXED_SIDE FIXED_ORDER FIXED_RATIO FIXED_POS], default: "UNDEFINED", aliases: %w[portConstraints], algorithms: :all, status: :honoured, description: "How strictly port positions are respected" },
        "elk.portLabels.placement" => { type: :string, default: "OUTSIDE", aliases: %w[port.label.placement], algorithms: :all, status: :honoured, description: "Port label placement" },
        "elk.position" => { type: :kvector, default: nil, aliases: %w[position], algorithms: %w[fixed], status: :honoured, description: "Fixed position for a node (fixed algorithm)" },
        "elk.radial.centerOnRoot" => { type: :boolean, default: false, algorithms: %w[radial], status: :accepted, description: "Whether the root node is placed at the centre; not honoured today (ELK default is false; radial.rb does not centre any node today either)" },
        "elk.radial.radius" => { type: :float, default: 100.0, algorithms: %w[radial], status: :honoured, description: "Radius for radial layout" },
        "elk.randomSeed" => { type: :integer, default: 1, aliases: %w[randomSeed], algorithms: %w[force random], status: :honoured, description: "Seed for algorithms with random behaviour" },
        "elk.selfLoopOffset" => { type: :float, default: 20.0, aliases: %w[selfLoopOffset], namespace: :elkrb, algorithms: :all, status: :accepted, description: "elkrb-private: self-loop offset (not yet wired; hardcoded today)" },
        "elk.selfLoopRouting" => { type: :string, default: nil, aliases: %w[selfLoopRouting], namespace: :elkrb, algorithms: :all, status: :accepted, description: "elkrb-private: self-loop routing style (not yet wired)" },
        "elk.selfLoopSide" => { type: :enum, values: %w[NORTH SOUTH EAST WEST], default: "EAST", aliases: %w[selfLoopSide], namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: side a self-loop is drawn on" },
        "elk.spacing.componentComponent" => { type: :float, default: 20.0, algorithms: %w[disco], status: :honoured, description: "Spacing between disconnected components" },
        "elk.spacing.edgeEdge" => { type: :float, default: 10.0, algorithms: %w[layered], status: :accepted, description: "Spacing between two edges; not honoured today" },
        "elk.spacing.edgeNode" => { type: :float, default: 10.0, algorithms: %w[layered], status: :accepted, description: "Spacing between an edge and a node it does not connect to; not honoured today" },
        "elk.spacing.nodeNode" => { type: :float, default: 20.0, aliases: %w[spacing.nodeNode spacing_node_node], algorithms: :all, status: :honoured, description: "Spacing between nodes" },
        "elk.spline.curvature" => { type: :float, default: 0.5, aliases: %w[spline.curvature], namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: curvature factor for SPLINES routing" },
        "elk.stress.desiredEdgeLength" => { type: :float, default: 100.0, algorithms: %w[stress], status: :honoured, description: "Desired edge length for stress majorization" },
        "elk.stress.epsilon" => { type: :float, default: 0.0001, aliases: %w[epsilon], algorithms: %w[stress], status: :honoured, description: "Stress majorization convergence threshold" },
        "elk.stress.iterationLimit" => { type: :integer, default: 500, algorithms: %w[stress], status: :honoured, description: "Stress majorization iteration limit" },
        "hierarchical" => { type: :boolean, default: false, namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: recurse into compound nodes per level (not org.eclipse.elk.hierarchyHandling)" },
        "label.margin" => { type: :float, default: 5.0, namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: outer label margin" },
        "label.padding" => { type: :float, default: 5.0, namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: inner label padding" },
        "label.placement.disabled" => { type: :boolean, default: false, namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: skip automatic label placement entirely" },
        "libavoid.bendPenalty" => { type: :float, default: 2.0, namespace: :elkrb, algorithms: %w[libavoid], status: :honoured, description: "Penalty per bend in a routed connector" },
        "libavoid.routingPadding" => { type: :float, default: 10.0, namespace: :elkrb, algorithms: %w[libavoid], status: :honoured, description: "Obstacle padding for connector routing" },
        "libavoid.segmentPenalty" => { type: :float, default: 1.0, namespace: :elkrb, algorithms: %w[libavoid], status: :honoured, description: "Penalty per routed segment" },
        "spore.compactionDirection" => { type: :string, values: %w[both horizontal vertical], default: "both", namespace: :elkrb, algorithms: %w[spore_compaction], status: :honoured, description: "Direction(s) SPOrE compaction runs in" },
        "spore.maxIterations" => { type: :integer, default: 50, namespace: :elkrb, algorithms: %w[spore_overlap], status: :honoured, description: "Maximum overlap-removal iterations" },
        "spore.nodeSpacing" => { type: :float, default: 10.0, namespace: :elkrb, algorithms: %w[spore_overlap spore_compaction], status: :honoured, description: "Minimum spacing enforced by the SPOrE algorithms" },
        "topdownpacking.aspectRatio" => { type: :float, default: 1.0, namespace: :elkrb, algorithms: %w[topdownpacking], status: :honoured, description: "Target cell aspect ratio" },
        "topdownpacking.nodeWidth" => { type: :float, default: nil, namespace: :elkrb, algorithms: %w[topdownpacking], status: :honoured, description: "Explicit node width override" },
        "vertiflex.balanceColumns" => { type: :boolean, default: true, namespace: :elkrb, algorithms: %w[vertiflex], status: :honoured, description: "Balance node counts across columns" },
        "vertiflex.columnCount" => { type: :integer, default: 3, namespace: :elkrb, algorithms: %w[vertiflex], status: :honoured, description: "Number of columns" },
        "vertiflex.columnSpacing" => { type: :float, default: 50.0, namespace: :elkrb, algorithms: %w[vertiflex], status: :honoured, description: "Spacing between columns" },
        "vertiflex.verticalSpacing" => { type: :float, default: 30.0, namespace: :elkrb, algorithms: %w[vertiflex], status: :honoured, description: "Spacing between nodes within a column" },
      }.freeze
      # rubocop:enable Layout/LineLength
      private_constant :OPTIONS

      # LayoutEngine, not the algorithm, honours the selector — so it applies
      # to every registration, including a custom class that inherits no
      # BaseAlgorithm mixins and therefore gets none of the shared ids.
      ENGINE_OPTIONS = %w[elk.algorithm].freeze
      private_constant :ENGINE_OPTIONS

      OPTIONS.each_value do |entry|
        entry.freeze
        entry[:aliases]&.freeze
        entry[:values]&.freeze
        entry[:algorithms].freeze if entry[:algorithms].is_a?(Array)
      end

      ALIAS_LOOKUP = OPTIONS.each_with_object({}) do |(id, entry), lookup|
        Array(entry[:aliases]).each { |a| lookup[a] = id }
      end.freeze
      private_constant :ALIAS_LOOKUP

      class << self
        # @param key [String, Symbol] any id, alias, or ELK-prefixed id
        # @return [String, nil] the canonical id, or nil if unknown
        def canonical(key)
          key_str = key.to_s
          return key_str if OPTIONS.key?(key_str)

          if key_str.start_with?(ELK_PREFIX)
            stripped = key_str.sub(ELK_PREFIX, "elk.")
            return stripped if OPTIONS.key?(stripped)
          end

          return ALIAS_LOOKUP[key_str] if ALIAS_LOOKUP.key?(key_str)

          suffix_match(key_str)
        end

        # @param id [String, Symbol] any id or alias
        # @param value [Object] the raw value to coerce
        # @return [Object] value coerced to the id's registered type
        def coerce(id, value)
          entry = entry_for(id)
          return value unless entry

          coerce_typed(entry[:type], value, entry)
        end

        # @param id [String, Symbol] any id or alias
        # @return [Object, nil] the id's default, coerced to its type
        def default(id)
          entry = entry_for(id)
          return nil unless entry
          return nil if entry[:default].nil?

          coerce_typed(entry[:type], entry[:default], entry)
        end

        # @param id [String, Symbol] any id or alias
        # @return [Symbol, nil] :honoured, :partial, :accepted, :unsupported, or nil if unknown
        def status(id)
          entry_for(id)&.[](:status)
        end

        # @param id [String, Symbol] any id or alias
        # @return [String, nil] explanatory note for a :partial id
        def note(id)
          entry_for(id)&.[](:note)
        end

        # Membership, not truthfulness: an id's presence here means it's
        # scoped to this algorithm, regardless of whether it's currently
        # honoured, accepted, or unsupported — cross-reference #status(id)
        # for that.
        #
        # @param name [String] a normalised algorithm name (e.g. "layered")
        # @param include_all [Boolean] whether to include algorithms: :all
        #   ids (AlgorithmRegistry passes false for a registration that
        #   does not inherit BaseAlgorithm, so does not get those for free)
        # @return [Array<String>] canonical ids scoped to that algorithm
        def for_algorithm(name, include_all: true)
          OPTIONS.select do |id, entry|
            ENGINE_OPTIONS.include?(id) ||
              (include_all && entry[:algorithms] == :all) ||
              Array(entry[:algorithms]).include?(name)
          end.keys
        end

        # @return [Hash] the full, frozen options table
        def all
          OPTIONS
        end

        # Renders OPTIONS into the documented shape Elkrb.known_layout_options
        # and LayoutEngine.known_layout_options both return. The single
        # owner of that rendering — the two callers are one-line
        # delegators, mirroring how they already both delegate straight to
        # AlgorithmRegistry.all_algorithm_info for known_layout_algorithms.
        #
        # @param algorithm_values [Array<String>] registered algorithm ids,
        #   patched onto the elk.algorithm row's :values. Passed in rather
        #   than read from AlgorithmRegistry directly, so Options never
        #   depends on Layout.
        # @return [Hash{String => Hash}] canonical id => {type:, description:,
        #   default:, values:, parser:, status:, note:}
        def render_known_options(algorithm_values:)
          parsers = {
            padding: "Elkrb::Options::ElkPadding",
            kvector: "Elkrb::Options::KVector",
            kvector_chain: "Elkrb::Options::KVectorChain",
          }

          rendered = OPTIONS.each_with_object({}) do |(id, entry), hash|
            hash[id] = {
              type: entry[:type],
              description: entry[:description],
              default: entry[:default],
              values: entry[:values],
              parser: parsers[entry[:type]],
              status: entry[:status],
              note: entry[:note],
            }
          end

          rendered["elk.algorithm"][:values] = algorithm_values
          rendered
        end

        private

        # canonical(id) already checks OPTIONS.key?(key_str) as its very
        # first step, so when it returns nil, OPTIONS[id.to_s] is
        # provably nil too — no `|| id.to_s` fallback needed here.
        def entry_for(id)
          OPTIONS[canonical(id)]
        end

        def suffix_match(key_str)
          matches = OPTIONS.keys.select { |id| id.end_with?(".#{key_str}") }
          matches.first if matches.size == 1
        end

        def coerce_typed(type, value, entry)
          case type
          when :float then value.to_f
          when :integer then value.to_i
          when :string then value.to_s
          when :boolean then coerce_boolean(value)
          when :enum then value.to_s.upcase
          when :padding then coerce_padding(value, entry[:default])
          when :kvector then Options::KVector.parse(value)
          when :kvector_chain then Options::KVectorChain.parse(value)
          else value
          end
        end

        # Strict boolean-env semantics: only true itself, or the literal
        # string "true" (case-insensitive), coerces to true. "1", "yes",
        # and everything else — including malformed input — coerce to
        # false; no numeric or word aliases for "true" are recognised.
        def coerce_boolean(value)
          # `value` stays the receiver so a delegator wrapping a boolean answers
          # for itself and comes back unwrapped. Both rewrites rubocop offers
          # here -- Array#include? and any?(value) -- compare the other way
          # round, and one of them swaps == for ===, so neither is equivalent.
          # rubocop:disable Performance/RedundantEqualityComparisonBlock
          return value if BOOLEAN_LITERALS.any? { |literal| value == literal }
          # rubocop:enable Performance/RedundantEqualityComparisonBlock

          value.to_s.strip.casecmp("true").zero?
        end

        def coerce_padding(value, default_string)
          return value if value.is_a?(ElkPadding)
          return ElkPadding.parse(value) if value.is_a?(String)

          if value.is_a?(Numeric)
            return ElkPadding.new(top: value, left: value, bottom: value,
                                  right: value)
          end

          unless value.is_a?(Hash)
            raise ArgumentError,
                  "Invalid padding value: #{value.inspect}"
          end

          fallback = ElkPadding.parse(default_string)
          ElkPadding.new(
            top: value[:top] || value["top"] || fallback.top,
            left: value[:left] || value["left"] || fallback.left,
            bottom: value[:bottom] || value["bottom"] || fallback.bottom,
            right: value[:right] || value["right"] || fallback.right,
          )
        end
      end
    end
  end
end
