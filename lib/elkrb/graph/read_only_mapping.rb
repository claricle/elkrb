# frozen_string_literal: true

module Elkrb
  module Graph
    # The write half of a read-only `with:` mapping. lutaml requires both
    # halves of a `with:` pair, and a legacy alias must contribute nothing to
    # output -- one output vocabulary -- so this writes nothing on purpose.
    module ReadOnlyMapping
      # Public because lutaml invokes it with `public_send`; the `__elkrb_`
      # prefix keeps a subclass from taking the name by accident. Not part of
      # the supported API.
      #
      # @api private
      def __elkrb_omit_from_output(model, doc); end
    end
    private_constant :ReadOnlyMapping
  end
end
