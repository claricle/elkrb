# frozen_string_literal: true

module Elkrb
  # @api private
  #
  # The one table that turns CLI flags into layout options. A flag the user
  # typed becomes a canonical option on the ROOT graph, where it outranks
  # whatever the file says for itself. A flag the user did not type is never
  # written, so the file's own options (including its elk.algorithm pin)
  # stay in charge.
  module LayoutFlags
    OPTION_IDS = {
      algorithm: "elk.algorithm",
      spacing: "elk.spacing.nodeNode",
      layer_spacing: "elk.layered.spacing.nodeNodeBetweenLayers",
      direction: "elk.direction",
      edge_routing: "elk.edgeRouting",
    }.freeze
    private_constant :OPTION_IDS

    PADDING_FLAGS = %i[padding_top padding_bottom padding_left padding_right]
      .freeze
    private_constant :PADDING_FLAGS

    # ELK parses a padding string with missing sides as 0, so the sides the
    # user did not give are written out as the registry default.
    DEFAULT_PADDING = 12
    private_constant :DEFAULT_PADDING

    class << self
      # @param graph [Elkrb::Graph::Graph, Hash] a Graph, or the Hash an
      #   ELKT parse returns
      # @param options [Hash] Thor options, Symbol keys; only the flags
      #   present are applied
      # @return [Elkrb::Graph::Graph] the graph, with the flags written onto
      #   its layoutOptions
      def apply(graph, options)
        graph = Graph::Graph.from_hash(graph) if graph.is_a?(::Hash)
        graph.layout_options = {} if graph.layout_options.nil?

        flag_options(options).each do |id, value|
          graph.layout_options[id] = value
        end
        graph
      end

      private

      def flag_options(options)
        given = OPTION_IDS.filter_map do |flag, id|
          [id, options[flag]] unless options[flag].nil?
        end.to_h

        padding = padding_string(options)
        given["elk.padding"] = padding if padding
        given
      end

      def padding_string(options)
        return nil if PADDING_FLAGS.all? { |flag| options[flag].nil? }

        side = ->(flag) { options[flag] || DEFAULT_PADDING }
        "[top=#{side.call(:padding_top)},left=#{side.call(:padding_left)}," \
          "bottom=#{side.call(:padding_bottom)}," \
          "right=#{side.call(:padding_right)}]"
      end
    end
  end
end
