# frozen_string_literal: true

require_relative "option_map"
require_relative "registry"

module Elkrb
  module Options
    # @api private
    #
    # The option maps of one element, in the order Resolver#get reads them:
    # layoutOptions, the deprecated map nested in it, then properties.
    # Resolver#get and UnhonouredReport both take their sources from here, so
    # a source added to this list is read and reported together.
    class ElementOptions
      # @param element [#layout_options, #properties, nil]
      # @param spellings [Spellings]
      def initialize(element, spellings)
        @layout = OptionMap.new(element&.layout_options, spellings)
        @properties = OptionMap.new(element&.properties, spellings)
        @read_order = [@layout, @layout.nested, @properties].compact
      end

      # @return [Object, nil] the first non-nil value for a canonical id; an
      #   explicit false is a value
      def value(id)
        @read_order.each do |map|
          found = map.value(id)
          return found unless found.nil?
        end
        nil
      end

      # Every canonical id the element names as an option: all keys of
      # layoutOptions, nested ones included, and the registered keys of
      # properties. An unknown name in properties is metadata, not an option.
      #
      # @return [Array<String>]
      def ids
        @layout.ids + @properties.own_ids.select { |id| Registry.status(id) }
      end
    end
  end
end
