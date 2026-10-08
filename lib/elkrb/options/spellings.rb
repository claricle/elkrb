# frozen_string_literal: true

require_relative "registry"

module Elkrb
  module Options
    # @api private
    #
    # Resolves an option key, as a Symbol or String, to its canonical id and
    # ranks how canonical that spelling is. Registry.canonical scans every
    # registered id for a suffix match, so each distinct name is resolved once.
    class Spellings
      ELK_LONG_PREFIX = "org.eclipse.elk."
      ELK_SHORT_PREFIX = "elk."
      private_constant :ELK_LONG_PREFIX, :ELK_SHORT_PREFIX

      def initialize
        @resolved = {}
      end

      # @param key [String, Symbol]
      # @return [Array(String, Integer)] the canonical id (an unknown key
      #   stays under its own name) and the spelling's rank, lowest best:
      #   the id, then its org.eclipse.elk. form, then each alias in
      #   registry order, then the shorter dot-suffixes of the id, the
      #   longer first. No two spellings of one id share a rank.
      def resolve(key)
        name = key.to_s
        @resolved[name] ||= begin
          id = Registry.canonical(name) || name
          [id, rank(name, id)]
        end
      end

      def id(key)
        resolve(key).first
      end

      private

      def rank(name, id)
        return 0 if name == id

        entry = Registry.all[id]
        aliases = Array(entry&.fetch(:aliases, nil))
        return 1 if name == long_form(id)

        position = aliases.index(name)
        return 2 + position if position

        2 + aliases.size + id.length - name.length
      end

      def long_form(id)
        return id unless id.start_with?(ELK_SHORT_PREFIX)

        ELK_LONG_PREFIX + id.delete_prefix(ELK_SHORT_PREFIX)
      end
    end
  end
end
