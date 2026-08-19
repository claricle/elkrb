# frozen_string_literal: true

require_relative "../options/registry"

module Elkrb
  module Layout
    class AlgorithmRegistry
      @algorithms = {}
      @metadata = {}

      class << self
        def register(name, algorithm_class, metadata = {})
          name_str = normalize_name(name)
          @algorithms[name_str] = algorithm_class
          @metadata[name_str] = metadata
        end

        def get(name)
          @algorithms[resolve_key(name)]
        end

        def available_algorithms
          @algorithms.keys.sort
        end

        def algorithm_info(name)
          name_str = resolve_key(name)
          algorithm_class = @algorithms[name_str]
          return nil unless algorithm_class

          metadata = @metadata[name_str] || {}

          {
            id: name_str,
            name: metadata[:name] || name_str.capitalize,
            description: metadata[:description] || "",
            category: metadata[:category] || "general",
            supports_hierarchy: metadata[:supports_hierarchy] || false,
            supported_options: Options::Registry.for_algorithm(name_str),
          }
        end

        def all_algorithm_info
          available_algorithms.map { |name| algorithm_info(name) }
        end

        private

        # Used by #get and #algorithm_info to find the key actually
        # registered for `name`: try the properly snake_cased form first,
        # then fall back to the plain downcased form for the handful of
        # legacy run-together registrations ("mrtree", "libavoid", ...)
        # that predate word-boundary folding. Falls back to the folded
        # form even when unregistered, so callers always get a single,
        # well-defined key back rather than nil.
        def resolve_key(name)
          folded = normalize_name(name)
          return folded if @algorithms.key?(folded)

          legacy = legacy_normalize_name(name)
          @algorithms.key?(legacy) ? legacy : folded
        end

        def normalize_name(name)
          # "org.eclipse.elk.sporeOverlap" / "sporeOverlap" / "spore_overlap"
          # all fold to the same "spore_overlap" key.
          name = name.to_s
          name = name.split(".").last if name.include?(".")
          name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        end

        def legacy_normalize_name(name)
          name = name.to_s
          name = name.split(".").last if name.include?(".")
          name.downcase
        end
      end
    end
  end
end
