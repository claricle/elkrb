# frozen_string_literal: true

require_relative "spellings"

module Elkrb
  module Options
    # @api private
    #
    # One option map read once into { canonical id => value }. Read option
    # maps only through this table: it walks with each_pair, so a Hash
    # default is never a value, and it folds String and Symbol keys and every
    # spelling of an id. The best spelling wins, then a String over a Symbol,
    # then the first inserted. A nil value is a miss, but its id still counts
    # as present for the report.
    class OptionMap
      NESTED_KEY = "properties"
      STRING_KEY = 0
      OTHER_KEY = 1
      private_constant :STRING_KEY, :OTHER_KEY

      # @param map [Hash, nil] anything else reads as an empty map
      # @param spellings [Spellings]
      def initialize(map, spellings)
        @spellings = spellings
        @ids = {}
        @best = {}
        map.each_pair { |key, value| add(key, value) } if map.is_a?(Hash)
      end

      # @return [Object, nil] the raw value for a canonical id; nil is a miss
      def value(id)
        @best[id]&.last
      end

      # The deprecated map inside layoutOptions that older graphs nest
      # options under. Only a Hash counts; it is read after the map's own
      # keys.
      #
      # @return [OptionMap, nil]
      def nested
        return @nested if defined?(@nested)

        raw = value(nested_id)
        @nested = raw.is_a?(Hash) ? self.class.new(raw, @spellings) : nil
      end

      # Every canonical id the map names, nested properties included, in
      # first-seen order. A nested map replaces its own "properties" key.
      #
      # @return [Array<String>]
      def ids
        inner = nested
        return own_ids unless inner

        own_ids - [nested_id] + inner.own_ids
      end

      # The canonical ids of the map's own keys, without the nested
      # properties map.
      #
      # @return [Array<String>]
      def own_ids
        @ids.keys
      end

      private

      def nested_id
        @spellings.id(NESTED_KEY)
      end

      def add(key, value)
        id, spelling_rank = @spellings.resolve(key)
        @ids[id] = true
        return if value.nil?

        rank = [spelling_rank, key.is_a?(String) ? STRING_KEY : OTHER_KEY]
        held = @best[id]
        return unless held.nil? || (rank <=> held.first).negative?

        @best[id] = [rank, value]
      end
    end
  end
end
