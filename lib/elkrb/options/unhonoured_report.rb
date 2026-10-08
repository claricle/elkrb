# frozen_string_literal: true

require_relative "element_options"
require_relative "option_map"
require_relative "registry"
require_relative "spellings"

module Elkrb
  module Options
    # @api private
    #
    # The option keys in a graph's elements, at any level, that the registry
    # does not know or does not fully honour, plus the call's own registered
    # keys that are not fully honoured. An element's sources are those of
    # ElementOptions. A key that is partial across algorithms (see
    # Registry's readers) is judged against the algorithm that lays out the
    # element carrying it, and a call key against every algorithm in play.
    # Built and read by Resolver#report_unhonoured.
    class UnhonouredReport
      NESTED_COLLECTIONS = %i[children edges ports labels].freeze
      CONTROL_CHARACTERS = /[[:cntrl:]]/
      ALGORITHM_ID = "elk.algorithm"
      # Takes an algorithm name as written; answers the name it is
      # registered under, or nil when it is not registered.
      AS_WRITTEN = :to_s.to_proc
      private_constant :NESTED_COLLECTIONS, :CONTROL_CHARACTERS, :ALGORITHM_ID

      # @param graph [Elkrb::Graph::Graph]
      # @param spellings [Spellings]
      # @param call [OptionMap] the options passed to the layout call
      # @param root_algorithm [String, nil] the algorithm laying out the
      #   graph, by registered name
      # @param algorithm_name [#call] resolves a name written in the options
      #   to a registered name; AS_WRITTEN takes every name as registered
      def initialize(graph, spellings = Spellings.new,
                     call = OptionMap.new({}, spellings),
                     root_algorithm: nil, algorithm_name: AS_WRITTEN)
        @spellings = spellings
        @graph = graph
        @root_algorithm = root_algorithm
        @algorithm_name = algorithm_name
        @findings = findings_for(graph, call)
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

      # { canonical id => status }; status is nil for an unknown key. An
      # unknown key in the call is not reported: the call also carries engine
      # flags such as strict and hierarchical. The call's nested properties
      # map is never read as options, so it is not reported either.
      def findings_for(graph, call)
        occurrences(laid_out_elements(graph), call)
          .each_with_object({}) do |(id, algorithms), findings|
          status = Registry.status(id)
          findings[id] = status if unread?(id, status, algorithms)
        end
      end

      # [[canonical id, algorithms that would read it]], one per place a key
      # is written. An element's key is read by the algorithm laying out that
      # element. A call key reaches every level, so any algorithm in play may
      # read it.
      def occurrences(levels, call)
        in_play = levels.filter_map(&:last).uniq
        written = levels.flat_map do |options, algorithm|
          options.ids.map { |id| [id, [algorithm]] }
        end
        called = call.own_ids.select { |id| Registry.status(id) }
        (written + called.map { |id| [id, in_play] }).uniq
      end

      def unread?(id, status, algorithms)
        status != :honoured &&
          algorithms.none? { |name| Registry.read_by?(id, name) }
      end

      # [[ElementOptions, algorithm]] for every element reachable from the
      # graph, breadth first; the algorithm is the one laying out the element's
      # children, nil for an element that has none to lay out (a leaf node,
      # an edge, a port, a label). Iterative, so a deeply nested graph
      # cannot overflow the stack here; an element reachable by two paths is
      # visited once.
      def laid_out_elements(graph)
        seen = {}.compare_by_identity
        pending = [[graph, @root_algorithm]]
        until pending.empty?
          element, enclosing = pending.shift
          next if seen.key?(element)

          seen[element] = level_of(element, enclosing)
          algorithm = seen[element].last
          nested_elements(element).each { |child| pending << [child, algorithm] }
        end
        seen.values
      end

      def level_of(element, enclosing)
        options = ElementOptions.new(element, @spellings)
        [options, layout_algorithm(element, options, enclosing)]
      end

      # The algorithm a compound node is laid out by is its own registered
      # elk.algorithm, else the one laying out the level it sits in, the way
      # HierarchicalProcessor picks it.
      def layout_algorithm(element, options, enclosing)
        return enclosing if element.equal?(@graph)
        return unless compound?(element)

        own = options.value(ALGORITHM_ID)
        (own && @algorithm_name.call(own)) || enclosing
      end

      def compound?(element)
        element.respond_to?(:children) && !Array(element.children).empty?
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
