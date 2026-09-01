# frozen_string_literal: true

module Elkrb
  module Graph
    # The write half of a read-only `with:` mapping. lutaml requires both
    # halves of a `with:` pair, and a legacy alias must contribute nothing to
    # output -- one output vocabulary -- so this writes nothing on purpose.
    module ReadOnlyMapping
      # Public because lutaml invokes it with `public_send`; not part of the
      # supported API.
      #
      # @api private
      def omit_from_output(model, doc); end
    end
    private_constant :ReadOnlyMapping
  end
end
