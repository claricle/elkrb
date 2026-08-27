# frozen_string_literal: true

module Elkrb
  module Graph
    # Recursively stringifies Hash/Array keys (Symbol -> String). Used only
    # by the five models' `layout_options=` overrides, and only on the
    # options map itself — never on a whole input tree, which would also
    # rewrite opaque data the caller parked in `properties`. Verified
    # against lutaml-model 0.8.19 that :hash-typed attributes otherwise
    # store a raw Hash unchanged, Symbol keys and all.
    module DeepStringifyKeys
      module_function

      def call(obj)
        case obj
        when ::Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_s] = call(v) }
        when ::Array
          obj.map { |v| call(v) }
        else
          obj
        end
      end
    end
    private_constant :DeepStringifyKeys
  end
end
