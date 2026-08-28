# frozen_string_literal: true

module Elkrb
  module Graph
    # Normalizes the result of `attr.cast_value` for an options map, and
    # rejects the one shape that result can take when a caller used a key
    # lutaml-model has reserved.
    #
    # A non-Hash here is an INFERENCE, not a direct observation: lutaml reads
    # a bare `text` or `elements` key as its own wrapper and casts the map
    # down to that key's value, so anything but a Hash means a reserved key
    # was used. Saying so beats letting the next line fail with a bare
    # NoMethodError. The message is pinned by a matcher in
    # spec/elkrb/graph/layout_options_spec.rb and must stay verbatim.
    #
    # Stringifies the TOP LEVEL only, matching the constructor this replaces.
    # Deliberately not DeepStringifyKeys: that one walks nested Hashes and
    # Arrays, this never did, and the models already ran it on the way in.
    module NormalizeOptionKeys
      module_function

      def call(cast)
        return cast if cast.nil?

        unless cast.is_a?(::Hash)
          raise Elkrb::ValidationError,
                "layoutOptions cannot use `text` or `elements` as a key; " \
                "both are reserved by lutaml-model"
        end

        cast.transform_keys(&:to_s)
      end
    end
    private_constant :NormalizeOptionKeys
  end
end
