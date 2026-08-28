# frozen_string_literal: true

module Elkrb
  module Graph
    # Constructor shim for the pre-2.0 typed `LayoutOptions.new(...)` call
    # sites (spec/example only — no lib/ call site remains after S3).
    # `attribute :layout_options, :hash` on Graph/Node/Edge/Port/Label casts
    # whatever's assigned down to a plain ::Hash, so each model's
    # `layout_options=` re-wraps the cast result through .wrap. That keeps
    # #[]= normalizing the in-place writes a caller makes afterwards.
    #
    # Every dotted / ELK-style key survives the round trip; the bare keys
    # `text` and `elements` are reserved by lutaml-model and are not
    # supported inside layoutOptions (see spec/elkrb/graph/layout_options_spec.rb).
    #
    # @deprecated Migration shim for 1.x call sites; removed in S3b — pass
    #   a plain Hash instead (`{"elk.x" => 1}` or `layoutOptions: {...}`).
    class LayoutOptions < ::Hash
      # Old typed `LayoutOptions.new(edge_routing: ...)` keyword names,
      # mapped to the ELK id a caller should switch to. Symbol keys only —
      # this mirrors the OLD class's own behaviour: only the bare keyword
      # form ever routed through typed-attribute assignment; a positional
      # Hash (braced or braceless, Symbol or String keys) always went
      # straight to the untyped properties store, never through this
      # translation, so it doesn't go through it here either.
      LEGACY_KWARG_ELK_KEYS = {
        algorithm: "elk.algorithm",
        direction: "elk.direction",
        spacing_node_node: "elk.spacing.nodeNode",
        spacing_edge_node: "elk.spacing.edgeNode",
        spacing_edge_edge: "elk.spacing.edgeEdge",
        spacing_node_label: "elk.spacing.labelNode",
        edge_routing: "elk.edgeRouting",
        spline_curvature: "elk.spline.curvature",
        spline_segments: "elk.spline.segments",
        interactive_layout: "elk.interactiveLayout",
        aspect_ratio: "elk.aspectRatio",
        node_placement_strategy: "elk.layered.nodePlacement.strategy",
        crossing_minimization_strategy: "elk.layered.crossingMinimization.strategy",
        layer_constraint: "elk.layered.layering.layerConstraint",
        cycle_breaking_strategy: "elk.layered.cycleBreaking.strategy",
      }.freeze
      private_constant :LEGACY_KWARG_ELK_KEYS

      def initialize(hash = {}, **kwargs)
        super()
        (hash || {}).each { |key, value| self[key] = value }
        kwargs.each { |key, value| assign_kwarg(key, value) }
      end

      def [](key)
        super(key.to_s)
      end

      def []=(key, value)
        super(key.to_s, value)
      end

      # Mutates self and returns self, matching the pre-S3 LayoutOptions#merge
      # (unlike ::Hash#merge, which returns a new Hash and leaves self untouched).
      def merge(other)
        return self unless other

        other.each { |key, value| self[key] = value }
        self
      end

      # ::Hash's own writers store the key unchanged, bypassing #[]=. Route
      # them through it so a Symbol key normalizes whichever writer a caller
      # reaches for, not just the subscript one. These are the whole set of
      # ::Hash methods that introduce a key in place.
      def store(key, value)
        self[key] = value
      end

      # Honours ::Hash#merge!'s conflict block: for a key already present the
      # block picks the value, and only its result is stored.
      def merge!(*others)
        others.each do |other|
          other.each do |key, value|
            string_key = key.to_s
            self[string_key] =
              if block_given? && key?(string_key)
                yield(string_key, self[string_key], value)
              else
                value
              end
          end
        end
        self
      end
      alias update merge!

      # `other` may be self, so the pairs come out before the clear —
      # ::Hash#replace(self) is a no-op and this has to match it. The source's
      # default travels with the pairs, the way ::Hash#replace carries it.
      def replace(other)
        pairs = other.to_a
        source_default = other.default
        source_default_proc = other.default_proc
        refill(pairs)
        if source_default_proc
          self.default_proc = source_default_proc
        else
          self.default = source_default
        end
        self
      end

      # ::Hash#transform_keys! answers an Enumerator and mutates nothing when
      # it gets neither a block nor a mapping hash, so match that before
      # touching self — otherwise every key maps to nil. Refills in place
      # rather than going through #replace, which would take its default from
      # the plain Hash #to_h hands back and drop ours.
      def transform_keys!(*args, &block)
        return enum_for(:transform_keys!, *args) if args.empty? && block.nil?

        refill(to_h.transform_keys(*args, &block).to_a)
        self
      end

      private

      # #clear keeps the default, so a refill only swaps the pairs, and
      # every one of them goes back in through #[]=.
      def refill(pairs)
        clear
        pairs.each { |key, value| self[key] = value }
      end

      # Canonical-over-deprecated: a legacy kwarg name only translates and
      # writes its ELK key when that key isn't already present in this
      # options map — an explicit canonical key (from the positional Hash,
      # or an earlier kwarg in the same call) always wins over a same-call
      # legacy alias, regardless of which one appears first in the call.
      def assign_kwarg(key, value)
        # 1.x's typed class parked every unmapped option in a `properties`
        # Hash, so a `properties:` kwarg IS the options map, not an option
        # named "properties". Flatten it, or a 1.x caller's options all
        # nest one level down and every read silently falls back to a default.
        if key == :properties
          self.class.warn_legacy_kwarg_once(key, "a plain Hash of options")
          return merge!(value || {})
        end

        elk_key = LEGACY_KWARG_ELK_KEYS[key]
        return self[key] = value unless elk_key
        return if key?(elk_key)

        self.class.warn_legacy_kwarg_once(key, %("#{elk_key}" => ...))
        self[elk_key] = value
      end

      class << self
        # `attribute :layout_options, :hash` casts to a plain ::Hash, so a
        # value arriving through lutaml has to be re-wrapped for #[]= to keep
        # normalizing the in-place writes a caller makes afterwards.
        #
        # lutaml reads a bare `text` or `elements` key as its own wrapper and
        # casts the map down to that key's value, so anything but a Hash here
        # means the caller used a reserved key. Say that, rather than letting
        # the constructor fail on a String with a bare NoMethodError.
        # ::Hash.[] builds through allocation, not #[]=, so it would seed the
        # map with un-normalized keys. Build the plain Hash its own way, then
        # let #initialize put every pair through #[]=.
        def [](*)
          new(::Hash[*])
        end

        def wrap(value)
          return value if value.nil? || value.is_a?(self)

          unless value.is_a?(::Hash)
            raise Elkrb::ValidationError,
                  "layoutOptions cannot use `text` or `elements` as a key; " \
                  "both are reserved by lutaml-model"
          end

          new(value)
        end

        # Deprecation-diagnostic dedup only (not business state — never
        # read by layout logic), so a rare double-warn under concurrent
        # first-use is harmless; matches the "once per process" contract
        # a plain Mutex would only protect against for no practical gain.
        def warn_legacy_kwarg_once(key, replacement)
          @warned_legacy_kwargs ||= {}
          return if @warned_legacy_kwargs.key?(key)

          @warned_legacy_kwargs[key] = true
          warn "deprecated LayoutOptions.new(#{key}:) — use #{replacement}"
        end
      end
    end
  end
end
