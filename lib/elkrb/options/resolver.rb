# frozen_string_literal: true

require_relative "registry"
require_relative "../errors"
require_relative "decimal"
require_relative "element_options"
require_relative "option_map"
require_relative "spellings"
require_relative "unhonoured_report"

module Elkrb
  module Options
    # Reads layout options in one order: element layoutOptions, element
    # properties, call-level options, registry default. The caller names the
    # elements to consult; nothing is inherited from a parent. Every spelling
    # the registry knows reaches the same value, and an explicit false or 0 is
    # a value, not a miss.
    #
    # @example
    #   resolver = Elkrb::Options::Resolver.new(spacing_node_node: 40)
    #   resolver.get("elk.spacing.nodeNode", node, graph) # => 40.0
    class Resolver
      NUMERIC_TYPES = %i[float integer].freeze
      private_constant :NUMERIC_TYPES

      # @param call_options [Hash] the options passed to the layout call, under
      #   any key spelling; Symbol keys are read like String keys
      def initialize(call_options = {})
        @spellings = Spellings.new
        @call = OptionMap.new(call_options, @spellings)
      end

      # @param key [String, Symbol] any registry id or alias, or a custom key
      # @param elements [Array<#layout_options, #properties, nil>] consulted
      #   in the order given
      # @param default [Object] returned when nothing names the key;
      #   :registry means the registry default, nil means nil
      # @return [Object] the value, coerced to the registry type for a known
      #   id and left as written for an unknown one
      # @raise [Elkrb::ValidationError] when the value cannot be coerced to
      #   the registered type, or is a non-finite number
      def get(key, *elements, default: :registry)
        id = @spellings.id(key)

        elements.each do |element|
          value = element_value(element, id)
          return coerce(id, value) unless value.nil?
        end

        value = @call.value(id)
        return coerce(id, value) unless value.nil?

        default == :registry ? Registry.default(id) : default
      end

      # True when the call asked for strict option handling.
      #
      # @raise [Elkrb::ValidationError] when strict: is neither true nor
      #   false, so a typo cannot silently turn strictness off
      def strict?
        case (strict = @call.value(@spellings.id("strict")))
        when true then true
        when false, nil then false
        else
          raise ValidationError,
                "option strict must be true or false, got #{strict.inspect}"
        end
      end

      # Reports every key in the graph's layoutOptions, at any level, that the
      # registry does not know or does not fully honour, and every registered
      # key in an element's properties or the call that it does not. A key
      # only some algorithms read is reported only where the algorithm laying
      # out its element does not read it. Unknown property names and call keys
      # are not reported. Warns once per key; with strict: true it raises
      # before anything is logged.
      #
      # @param graph [Elkrb::Graph::Graph]
      # @param algorithm_name [#call] name as written => registered name or nil
      # @raise [Elkrb::Error] in strict mode, naming each such key
      def report_unhonoured(graph,
                            algorithm_name: UnhonouredReport::AS_WRITTEN)
        strict = strict?
        report = UnhonouredReport.new(
          graph, @spellings, @call,
          root_algorithm: algorithm_name.call(get("elk.algorithm", graph)),
          algorithm_name: algorithm_name
        )
        return if report.empty?

        raise Error, report.strict_message if strict

        report.log
      end

      private

      def element_value(element, id)
        ElementOptions.new(element, @spellings).value(id)
      end

      def coerce(id, value)
        coerced = coerce_value(id, numeric_input(id, value))
        unless finite?(coerced)
          raise ValidationError,
                "option #{id} must be a finite number, got #{value.inspect}"
        end

        coerced
      end

      # A string for a numeric option must be plain decimal, so "abc" and
      # "0x10" raise instead of becoming 0.0. It is parsed here, once.
      def numeric_input(id, value)
        return value unless value.is_a?(String)
        return value unless NUMERIC_TYPES.include?(Registry.all.dig(id, :type))

        Decimal.parse(value) ||
          raise(ValidationError,
                "invalid value #{value.inspect} for option #{id}")
      end

      # The one delegate call the rescue covers. Registry.coerce raises
      # NoMethodError/TypeError for a value of the wrong shape (an Array for
      # a Float), ArgumentError for malformed padding, and RangeError
      # (FloatDomainError, Complex) for a number that cannot be an Integer or
      # Float; all are bad input here, and the caller needs the option's name.
      def coerce_value(id, value)
        Registry.coerce(id, value)
      rescue ArgumentError, TypeError, NoMethodError, RangeError, EncodingError
        raise ValidationError,
              "invalid value #{value.inspect} for option #{id}"
      end

      # Infinity or NaN anywhere in a coerced number, padding or vector.
      def finite?(coerced)
        components(coerced).none? { |n| n.is_a?(Float) && !n.finite? }
      end

      def components(coerced)
        case coerced
        when Float then [coerced]
        when Options::ElkPadding then coerced.to_h.values
        when Options::KVector then coerced.to_a
        when Options::KVectorChain then coerced.vectors.flat_map(&:to_a)
        else []
        end
      end
    end
  end
end
