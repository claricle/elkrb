# frozen_string_literal: true

require "lutaml/model"
require_relative "read_only_mapping"

module Elkrb
  module Graph
    # Relative offset for positioning
    #
    # Specifies x and y offset from a reference node.
    #
    # @example
    #   offset = RelativeOffset.new(x: 100, y: 50)
    #   # Position 100px right, 50px down from reference
    class RelativeOffset < Lutaml::Model::Serializable
      attribute :x, :float, default: -> { 0.0 }
      attribute :y, :float, default: -> { 0.0 }

      key_value do
        map "x", to: :x
        map "y", to: :y
      end

      yaml do
        map "x", to: :x
        map "y", to: :y
      end
    end

    # Node positioning constraints
    #
    # Allows precise control over node placement through various constraint types:
    # - Fixed position: Lock node at specific coordinates
    # - Alignment: Align nodes horizontally or vertically
    # - Layer: Force node into specific layer (for layered algorithm)
    # - Relative position: Position relative to another node
    #
    # @example Fixed position constraint
    #   constraints = NodeConstraints.new(fixed_position: true)
    #   node.constraints = constraints
    #   node.x = 100
    #   node.y = 200
    #   # Node won't move during layout
    #
    # @example Alignment constraint
    #   constraints = NodeConstraints.new(
    #     align_group: "databases",
    #     align_direction: "horizontal"
    #   )
    #   # All nodes in "databases" group will align horizontally
    #
    # @example Layer constraint
    #   constraints = NodeConstraints.new(layer: 2)
    #   # Node forced into layer 2 (for layered algorithm)
    #
    # @example Relative position constraint
    #   offset = RelativeOffset.new(x: 150, y: 0)
    #   constraints = NodeConstraints.new(
    #     relative_to: "backend_service",
    #     relative_offset: offset
    #   )
    #   # Node positioned 150px right of backend_service
    class NodeConstraints < Lutaml::Model::Serializable
      include ReadOnlyMapping

      attribute :fixed_position, :boolean, default: -> { false }
      attribute :layer, :integer
      attribute :align_group, :string
      attribute :align_direction, :string
      attribute :relative_to, :string
      attribute :relative_offset, RelativeOffset
      attribute :position_priority, :integer, default: -> { 0 }

      # Legacy camelCase YAML spellings, still readable so documents written
      # against the old mapping keep working. Output is snake_case only.
      LEGACY_YAML_KEYS = {
        "fixedPosition" => :fixed_position,
        "alignGroup" => :align_group,
        "alignDirection" => :align_direction,
        "relativeTo" => :relative_to,
        "relativeOffset" => :relative_offset,
        "positionPriority" => :position_priority,
      }.freeze
      private_constant :LEGACY_YAML_KEYS

      key_value do
        map "fixedPosition", to: :fixed_position
        map "layer", to: :layer
        map "alignGroup", to: :align_group
        map "alignDirection", to: :align_direction
        map "relativeTo", to: :relative_to
        map "relativeOffset", to: :relative_offset
        map "positionPriority", to: :position_priority
      end

      # YAML is snake_case like every other model here. The camelCase spellings
      # stay readable so existing documents keep working, and a legacy spelling
      # wins when a document carries both -- but only once the canonical rules
      # have run. They run first, so a canonical value that fails to cast or
      # validate raises before the hook is reached: `align_direction: sideways`
      # alongside a valid `alignDirection: horizontal` raises rather than
      # yielding "horizontal". The base had no snake_case key at all, so it
      # could not hit this.
      #
      # The legacy path is otherwise exactly what it was before the snake_case
      # keys existed, for every value shape -- scalar, wrong-typed, array and
      # blank. It casts through the attribute the way lutaml's own deserializer
      # does, applies the same cardinality check, and assigns through the
      # public setter, so it rejects the same input, produces the same Ruby
      # types, and runs align_direction's validation.
      #
      # Two things about the shape of the rule, neither of them free choices:
      #
      # * It is ONE root-document rule, not six per-key ones. A per-key custom
      #   rule is dropped before its hook runs when its value is blank
      #   (key_value/transform.rb:251), which would turn `alignDirection: ''`
      #   from a parse error into a silent nil. A plain `map ... to:` alias is
      #   no good either -- it fires even when its key is absent, overwriting a
      #   canonical-only read: with nil for an attribute that has no default,
      #   and with the declared default otherwise (`fixed_position` back to
      #   false, `position_priority` back to 0).
      # * Its `to:` names a sentinel rather than a real attribute. lutaml
      #   unwraps a root rule when the document has exactly one key equal to
      #   `to:`, handing over that key's VALUE instead of the document
      #   (services/rule_value_extractor.rb:36-47). It does that whatever the
      #   value's type, whether or not `to:` names an attribute, and for the
      #   key spelled as EITHER a String or a Symbol -- line 41 is the
      #   size == 1 guard, line 43 tests the two spellings. So
      #   the sentinel REDUCES the collision to documents whose sole key is
      #   `__legacy_yaml_aliases` in either spelling; it does not eliminate it.
      #   Naming a real attribute instead would collide on an ordinary key such
      #   as `layer`, which is why the sentinel is still the better target. The
      #   guard in the hook makes a NONBLANK NON-HASH collision inert -- a
      #   scalar or a nonempty Array, neither of which answers to `key?`; a
      #   nonempty Hash is still merged as though it were the document, which
      #   is an accepted residual pinned in the spec. A blank unwrapped value
      #   never reaches the hook at all -- transform.rb:251 drops the rule via
      #   Utils.present? (utils.rb:119) for nil, "", [] and {}.
      #
      #   `to:` cannot simply be dropped: without it `nil.to_sym` raises for a
      #   single-key document -- except a sole
      #   empty-string key, which matches `nil.to_s` and short-circuits first.
      #   A custom-method rule does not require the attribute to exist
      #   (valid_rule? is `attribute || rule.custom_methods[:from]`).
      yaml do
        map "fixed_position", to: :fixed_position
        map "layer", to: :layer
        map "align_group", to: :align_group
        map "align_direction", to: :align_direction
        map "relative_to", to: :relative_to
        map "relative_offset", to: :relative_offset
        map "position_priority", to: :position_priority
        # Declared last, so a legacy spelling wins. See the note above the
        # block for why this is one rule and why `to:` names no attribute.
        map nil, to: :__legacy_yaml_aliases,
                 with: { from: :merge_legacy_aliases, to: :omit_from_output }
      end

      # Serialization hook for every legacy camelCase spelling. Receives the
      # whole YAML document, so a key that is present with a blank value is
      # still seen. Public because lutaml invokes it with `public_send`; not
      # part of the supported API.
      #
      # @api private
      def merge_legacy_aliases(model, doc)
        # Only a NONBLANK value reaches here: transform.rb:251 drops the
        # rule for nil, "", [] and {} before the hook runs. So a non-Hash
        # arrives only when lutaml unwrapped a sole `__legacy_yaml_aliases`
        # key holding a nonblank non-Hash value -- a scalar or a nonempty
        # Array -- and ignoring it keeps that case inert. A nonempty Hash is
        # still merged -- see the note above `yaml do`.
        return unless doc.respond_to?(:key?) && doc.respond_to?(:[])

        LEGACY_YAML_KEYS.each do |camel, name|
          # The standard YAML adapter preserves Symbol keys, and lutaml's own
          # mappings resolve either spelling, so both are honoured here.
          key = [camel, camel.to_sym].find { |candidate| doc.key?(candidate) }
          next unless key

          model.public_send(:"#{name}=", cast_legacy(model, name, doc[key]))
        end
      end

      # Valid alignment directions
      HORIZONTAL = "horizontal"
      VERTICAL = "vertical"
      ALIGN_DIRECTIONS = [HORIZONTAL, VERTICAL].freeze

      # Validate alignment direction
      def align_direction=(value)
        if value && !ALIGN_DIRECTIONS.include?(value.to_s.downcase)
          raise ArgumentError,
                "Invalid align_direction: #{value}. " \
                "Must be #{ALIGN_DIRECTIONS.join(' or ')}"
        end
        @align_direction = value&.to_s&.downcase
      end

      private

      # Mirrors what lutaml's own deserializer does for a canonical
      # `map ... to:` rule (key_value/transform.rb:261-266): cast through the
      # attribute -- wired to the same parent and root -- then apply the
      # cardinality check. Skipping the cast leaks lutaml wrapper objects into
      # public attributes; skipping valid_collection! lets an array through for
      # a scalar attribute, which the canonical spelling rejects and which
      # reaches the layout engine as an Array.
      def cast_legacy(model, name, value)
        register = model.lutaml_register
        attribute = model.class.attributes(register)[name]
        cast = attribute.cast(
          value, :yaml, register,
          lutaml_parent: model, lutaml_root: model.lutaml_root || model
        )
        attribute.valid_collection!(cast, model.class)
        cast
      end
    end
  end
end
