# frozen_string_literal: true

require "thor"

require_relative "../options/registry"

module Elkrb
  class Cli < Thor
    # The flags that become layout options, declared once for every command
    # that lays out a graph. `extend` it into the Thor class and call
    # `layout_flags` directly above the command's `def`: Thor attaches
    # `option` declarations to the next method defined, so the call has to
    # sit where the individual `option` lines would.
    #
    # LayoutFlags.apply turns the parsed flags into root-graph options. Enum
    # values in the help text are read from the registry when the class is
    # defined, so a value added there reaches `--help` without an edit here.
    module LayoutFlagOptions
      # No Thor default: an absent --algorithm must stay nil so the graph's
      # own elk.algorithm can be read before falling back to layered.
      ALGORITHM_DESC = "Layout algorithm to use (default: the graph's " \
                       "own elk.algorithm, else layered)"

      def layout_flags
        option :algorithm, type: :string, desc: ALGORITHM_DESC
        option :direction, type: :string, desc: enum_desc(
          "Layout direction", "elk.direction",
          "; applied by layered and mrtree algorithms"
        )
        option :edge_routing, type: :string,
                              desc: enum_desc("Edge routing", "elk.edgeRouting")
        numeric_flags
      end

      private

      def numeric_flags
        option :spacing, type: :numeric, desc: "Node spacing"
        option :layer_spacing, type: :numeric,
                               desc: "Layer spacing (for layered algorithm)"
        %w[top bottom left right].each do |side|
          option :"padding_#{side}", type: :numeric,
                                     desc: "#{side.capitalize} padding"
        end
      end

      # @param id [String] a canonical registry id with an enumerated value list
      def enum_desc(label, id, suffix = "")
        values = Options::Registry.all.fetch(id).fetch(:values)
        "#{label}, one of #{values.join(', ')}#{suffix}"
      end
    end
  end
end
