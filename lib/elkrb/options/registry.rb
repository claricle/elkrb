# frozen_string_literal: true

module Elkrb
  module Options
    # Single source of truth for ELK/elkrb layout option metadata: id,
    # type, default, allowed values, aliases, owning algorithms, and the
    # elkrb 2.0 truthfulness status. Elkrb.known_layout_options,
    # LayoutEngine.known_layout_options, and AlgorithmRegistry#algorithm_info
    # all read from OPTIONS through the methods below — nothing else does.
    class Registry
      ELK_PREFIX = "org.eclipse.elk."
      private_constant :ELK_PREFIX

      # OPTIONS is intentionally not part of the public API — callers read
      # it through .all, .canonical, .coerce, .default, .status, .note, and
      # .for_algorithm below.
      # rubocop:disable Layout/LineLength
      OPTIONS = {
        "elk.algorithm" => { type: :string, default: "layered", aliases: %w[algorithm], algorithms: :all, status: :honoured, description: "The layout algorithm to use" },
        "elk.direction" => { type: :enum, values: %w[UNDEFINED RIGHT LEFT DOWN UP], default: "UNDEFINED", aliases: %w[direction], algorithms: %w[layered mrtree], status: :honoured, description: "Overall direction of layout" },
        "elk.spacing.nodeNode" => { type: :float, default: 20.0, aliases: %w[spacing.nodeNode spacing_node_node], algorithms: :all, status: :honoured, description: "Spacing between nodes" },
        "elk.padding" => { type: :padding, default: "[top=12,left=12,bottom=12,right=12]", aliases: %w[padding], algorithms: :all, status: :honoured, description: "Padding around the graph" },
        "elk.edgeRouting" => { type: :enum, values: %w[UNDEFINED POLYLINE ORTHOGONAL SPLINES], default: "UNDEFINED", aliases: %w[edgeRouting edge_routing edge.routing], algorithms: :all, status: :honoured, description: "Edge routing style" },
        "elk.aspectRatio" => { type: :float, default: 1.6, aliases: %w[aspectRatio aspect_ratio], algorithms: :all, status: :honoured, description: "Target width/height ratio (box, random)" },
        "elk.randomSeed" => { type: :integer, default: 1, aliases: %w[randomSeed], algorithms: :all, status: :honoured, description: "Seed for algorithms with random behaviour" },
        "elk.portConstraints" => { type: :enum, values: %w[UNDEFINED FREE FIXED_SIDE FIXED_ORDER FIXED_RATIO FIXED_POS], default: "UNDEFINED", aliases: %w[portConstraints], algorithms: :all, status: :honoured, description: "How strictly port positions are respected" },
        "elk.port.side" => { type: :enum, values: %w[NORTH SOUTH EAST WEST UNDEFINED], default: "UNDEFINED", aliases: %w[port.side], algorithms: :all, status: :honoured, description: "Side of the node a port is attached to" },
        "elk.port.index" => { type: :integer, default: -1, aliases: %w[port.index], algorithms: :all, status: :honoured, description: "Order of a port among its side's ports" },
        "elk.nodeLabels.placement" => { type: :string, default: "INSIDE CENTER", aliases: %w[node.label.placement label.placement], algorithms: :all, status: :honoured, description: "Node label placement" },
        "elk.portLabels.placement" => { type: :string, default: "OUTSIDE", aliases: %w[port.label.placement], algorithms: :all, status: :honoured, description: "Port label placement" },
        "elk.edgeLabels.placement" => { type: :string, default: "CENTER", algorithms: :all, status: :honoured, description: "Edge label placement" },
        "elk.position" => { type: :kvector, default: nil, aliases: %w[position], algorithms: %w[fixed], status: :honoured, description: "Fixed position for a node (fixed algorithm)" },
        "elk.bendPoints" => { type: :kvector_chain, default: nil, aliases: %w[bendPoints], algorithms: :all, status: :honoured, description: "Manual bend points for an edge" },
        "elk.layered.spacing.nodeNodeBetweenLayers" => { type: :float, default: 60.0, aliases: %w[layer_spacing layered.spacing.nodeNodeBetweenLayers], algorithms: %w[layered], status: :honoured, description: "Spacing between layers (S9 changes the default to 20.0)" },
        "elk.force.iterations" => { type: :integer, default: 300, aliases: %w[iterations], algorithms: %w[force], status: :honoured, description: "Force simulation iteration count" },
        "elk.force.repulsion" => { type: :float, default: 5.0, aliases: %w[repulsion], algorithms: %w[force], status: :honoured, description: "Force simulation repulsion strength" },
        "elk.force.temperature" => { type: :float, default: 0.001, aliases: %w[temperature], algorithms: %w[force], status: :honoured, description: "Force simulation cooling temperature" },
        "elk.stress.iterationLimit" => { type: :integer, default: 500, algorithms: %w[stress], status: :honoured, description: "Stress majorization iteration limit" },
        "elk.stress.epsilon" => { type: :float, default: 0.0001, aliases: %w[epsilon], algorithms: %w[stress], status: :honoured, description: "Stress majorization convergence threshold" },
        "elk.stress.desiredEdgeLength" => { type: :float, default: 100.0, algorithms: %w[stress], status: :honoured, description: "Desired edge length for stress majorization" },
        "elk.radial.radius" => { type: :float, default: 100.0, algorithms: %w[radial], status: :honoured, description: "Radius for radial layout" },
        "elk.spacing.componentComponent" => { type: :float, default: 20.0, algorithms: %w[disco], status: :honoured, description: "Spacing between disconnected components" },
        "hierarchical" => { type: :boolean, default: false, namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: recurse into compound nodes per level (not org.eclipse.elk.hierarchyHandling)" },
        "spore.maxIterations" => { type: :integer, default: 50, namespace: :elkrb, algorithms: %w[spore_overlap], status: :honoured, description: "Maximum overlap-removal iterations" },
        "spore.nodeSpacing" => { type: :float, default: 10.0, namespace: :elkrb, algorithms: %w[spore_overlap spore_compaction], status: :honoured, description: "Minimum spacing enforced by the SPOrE algorithms" },
        "spore.compactionDirection" => { type: :string, values: %w[both horizontal vertical], default: "both", namespace: :elkrb, algorithms: %w[spore_compaction], status: :honoured, description: "Direction(s) SPOrE compaction runs in" },
        "libavoid.routingPadding" => { type: :float, default: 10.0, namespace: :elkrb, algorithms: %w[libavoid], status: :honoured, description: "Obstacle padding for connector routing" },
        "libavoid.segmentPenalty" => { type: :float, default: 1.0, namespace: :elkrb, algorithms: %w[libavoid], status: :honoured, description: "Penalty per routed segment" },
        "libavoid.bendPenalty" => { type: :float, default: 2.0, namespace: :elkrb, algorithms: %w[libavoid], status: :honoured, description: "Penalty per bend in a routed connector" },
        "vertiflex.columnCount" => { type: :integer, default: 3, namespace: :elkrb, algorithms: %w[vertiflex], status: :honoured, description: "Number of columns" },
        "vertiflex.columnSpacing" => { type: :float, default: 50.0, namespace: :elkrb, algorithms: %w[vertiflex], status: :honoured, description: "Spacing between columns" },
        "vertiflex.verticalSpacing" => { type: :float, default: 30.0, namespace: :elkrb, algorithms: %w[vertiflex], status: :honoured, description: "Spacing between nodes within a column" },
        "vertiflex.balanceColumns" => { type: :boolean, default: true, namespace: :elkrb, algorithms: %w[vertiflex], status: :honoured, description: "Balance node counts across columns" },
        "topdownpacking.aspectRatio" => { type: :float, default: 1.0, namespace: :elkrb, algorithms: %w[topdownpacking], status: :honoured, description: "Target cell aspect ratio" },
        "topdownpacking.nodeWidth" => { type: :float, default: nil, namespace: :elkrb, algorithms: %w[topdownpacking], status: :honoured, description: "Explicit node width override" },
        "disco.componentAlgorithm" => { type: :string, default: "layered", namespace: :elkrb, algorithms: %w[disco], status: :honoured, description: "Algorithm used to lay out each component" },
        "disco.componentSpacing" => { type: :float, default: 20.0, namespace: :elkrb, algorithms: %w[disco], status: :honoured, description: "Spacing between components" },
        "disco.componentArrangement" => { type: :string, values: %w[row column grid], default: "row", namespace: :elkrb, algorithms: %w[disco], status: :honoured, description: "How components are arranged" },
        "elk.selfLoopSide" => { type: :enum, values: %w[NORTH SOUTH EAST WEST], default: "EAST", aliases: %w[selfLoopSide], namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: side a self-loop is drawn on" },
        "elk.selfLoopOffset" => { type: :float, default: 20.0, aliases: %w[selfLoopOffset], namespace: :elkrb, algorithms: :all, status: :accepted, description: "elkrb-private: self-loop offset (not yet wired; hardcoded today)" },
        "elk.selfLoopRouting" => { type: :string, default: nil, aliases: %w[selfLoopRouting], namespace: :elkrb, algorithms: :all, status: :accepted, description: "elkrb-private: self-loop routing style (not yet wired)" },
        "elk.spline.curvature" => { type: :float, default: 0.5, aliases: %w[spline.curvature], namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: curvature factor for SPLINES routing" },
        "label.padding" => { type: :float, default: 5.0, namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: inner label padding" },
        "label.margin" => { type: :float, default: 5.0, namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: outer label margin" },
        "label.placement.disabled" => { type: :boolean, default: false, namespace: :elkrb, algorithms: :all, status: :honoured, description: "elkrb-private: skip automatic label placement entirely" },
      }.freeze
      # rubocop:enable Layout/LineLength
      private_constant :OPTIONS

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
          entry = OPTIONS[canonical(id) || id.to_s]
          return value unless entry

          coerce_typed(entry[:type], value, entry)
        end

        # @param id [String, Symbol] any id or alias
        # @return [Object, nil] the id's default, coerced to its type
        def default(id)
          entry = OPTIONS[canonical(id) || id.to_s]
          return nil unless entry
          return nil if entry[:default].nil?

          coerce(id, entry[:default])
        end

        # @param id [String, Symbol] any id or alias
        # @return [Symbol, nil] :honoured, :partial, :accepted, :unsupported, or nil if unknown
        def status(id)
          OPTIONS.dig(canonical(id) || id.to_s, :status)
        end

        # @param id [String, Symbol] any id or alias
        # @return [String, nil] explanatory note for a :partial id
        def note(id)
          OPTIONS.dig(canonical(id) || id.to_s, :note)
        end

        # @param name [String] a normalised algorithm name (e.g. "layered")
        # @return [Array<String>] canonical ids that algorithm reads
        def for_algorithm(name)
          OPTIONS.select do |_id, entry|
            entry[:algorithms] == :all || Array(entry[:algorithms]).include?(name)
          end.keys
        end

        # @return [Hash] the full, frozen options table
        def all
          OPTIONS
        end

        private

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

        def coerce_boolean(value)
          return value if value == true || value == false

          value.to_s.strip.casecmp("true").zero?
        end

        def coerce_padding(value, default_string)
          return value if value.is_a?(ElkPadding)
          return ElkPadding.parse(value) if value.is_a?(String)

          if value.is_a?(Numeric)
            return ElkPadding.new(top: value, left: value, bottom: value, right: value)
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
