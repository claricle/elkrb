# frozen_string_literal: true

require_relative "option_map"
require_relative "registry"
require_relative "spellings"

module Elkrb
  module Options
    # @api private
    #
    # The option keys in a graph's layoutOptions, at any level, that the
    # registry does not know or does not fully honour. Built and read by
    # Resolver#report_unhonoured.
    class UnhonouredReport
      NESTED_COLLECTIONS = %i[children edges ports labels].freeze
      CONTROL_CHARACTERS = /[[:cntrl:]]/
      private_constant :NESTED_COLLECTIONS, :CONTROL_CHARACTERS

      # @param graph [Elkrb::Graph::Graph]
      # @param spellings [Spellings]
      def initialize(graph, spellings = Spellings.new)
        @spellings = spellings
        @findings = findings_for(graph)
      end

      def empty?
        @findings.empty?
      end

      # @return [String] one message naming every finding
      def strict_message
        described = @findings.map do |id, status|
          "#{printable(id)} " \
            "(#{status ? "#{status}, not honoured" : 'unknown'})"
        end
        "strict mode: unknown or unhonoured layout option(s): " \
          "#{described.join(', ')}"
      end

      # Partly honoured and accepted keys warn; unknown keys log at DEBUG
      # because elkjs ignores them too.
      def log
        @findings.each do |id, status|
          if status.nil?
            Elkrb.logger.debug(
              "elkrb: unknown option #{printable(id)}: stored and echoed",
            )
          else
            Elkrb.logger.warn(warning_for(id, status))
          end
        end
      end

      private

      # { canonical id => status }; status is nil for an unknown key.
      def findings_for(graph)
        ids = option_maps(graph).flat_map(&:ids)
        ids.each_with_object({}) do |id, findings|
          status = Registry.status(id)
          findings[id] = status unless status == :honoured
        end
      end

      def option_maps(graph)
        reachable_elements(graph).map do |element|
          OptionMap.new(element.layout_options, @spellings)
        end
      end

      # Every element reachable from the graph, breadth first. Iterative, so
      # a deeply nested graph cannot overflow the stack here; an element
      # reachable by two paths is visited once.
      def reachable_elements(graph)
        seen = {}.compare_by_identity
        pending = [graph]
        until pending.empty?
          element = pending.shift
          next if seen.key?(element)

          seen[element] = true
          pending.concat(nested_elements(element))
        end
        seen.keys
      end

      def nested_elements(element)
        NESTED_COLLECTIONS.flat_map do |collection|
          next [] unless element.respond_to?(collection)

          Array(element.public_send(collection))
        end
      end

      # An unknown key comes from the input file; keep control characters
      # and invalid bytes out of the log and the error message.
      def printable(id)
        id.to_s.scrub.gsub(CONTROL_CHARACTERS) { |char| char.dump[1..-2] }
      end

      def warning_for(id, status)
        if status == :partial
          "elkrb: option #{id} is partially honoured: #{Registry.note(id)}"
        else
          "elkrb: option #{id} is accepted but not honoured in this version"
        end
      end
    end
  end
end
