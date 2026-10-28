# frozen_string_literal: true

# leptris can fall back to FFI when a Ruby minor has no native bundle. Keep
# asserting all other stderr, including exact CLI diagnostics, on those hosts.
RSpec::Matchers.define :eq_ignoring_leptris_warning do |expected|
  match do |actual|
    warning = /\Aleptris:[ ]native[ ]acceleration[ ]unavailable[ ]
               \([^\r\n]*\);[ ]using[ ]the[ ]FFI[ ]surface\r?\n\z/x
    stderr = actual.lines.grep_v(warning).join
    values_match?(expected, stderr)
  end
end
