# frozen_string_literal: true

module Elkrb
  module Layout
    class AlgorithmRegistry
      @algorithms = {}
      @metadata = {}

      class << self
        def register(name, algorithm_class, metadata = {})
          name_str = name.to_s
          @algorithms[name_str] = algorithm_class
          @metadata[name_str] = metadata
        end

        def get(name)
          algorithm_name = normalize_name(name)
          @algorithms[algorithm_name]
        end

        def available_algorithms
          @algorithms.keys.sort
        end

        def algorithm_info(name)
          algorithm_class = get(name)
          return nil unless algorithm_class

          name_str = normalize_name(name)
          metadata = @metadata[name_str] || {}

          {
            id: name_str,
            name: metadata[:name] || name_str.capitalize,
            description: metadata[:description] || "",
            category: metadata[:category] || "general",
            supports_hierarchy: metadata[:supports_hierarchy] || false,
          }
        end

        def all_algorithm_info
          available_algorithms.map { |name| algorithm_info(name) }
        end

        private

        def normalize_name(name)
          # Support both full names and short names
          # e.g., "org.eclipse.elk.layered" -> "layered"
          name = name.to_s
          name = name.split(".").last if name.include?(".")
          name.downcase
        end
      end
    end
  end
end
