# frozen_string_literal: true

# Pure Ruby port of the Eclipse Layout Kernel. This file reopens the namespace
# only to hang an internal helper off it; the public API lives in lib/elkrb.rb.
module Elkrb
  # Only the write that emits the RESULT may decide the exit status. Every
  # other write -- a progress line, a failure report, anything printed
  # before or alongside the result -- is best-effort.
  #
  # Such a write can raise for reasons that have nothing to do with what it
  # is reporting: the reader hung up (Errno::EPIPE), or the text holds bytes
  # the stream cannot encode (ArgumentError). Either used to escape in place
  # of whatever came after it -- and because Thor rescues EPIPE and calls
  # exit(true), a caller lost both its result (or its error) AND its
  # process, silently, at exit 0.
  #
  # This module used to be named FailureReport and cover only a report
  # printed just before a raise. That was too narrow: a `--verbose` progress
  # line is not a failure report, so it never went through `attempt`, and a
  # dead stdout during a verbose run had the exact same silent-exit-0 defect
  # this module exists to prevent. Any write that is not the result write
  # must go through `attempt`, whether or not a raise follows it -- UNLESS
  # the write cannot raise in the first place. `Kernel#warn` is the one
  # exception in this codebase, for the way stderr actually goes dead here:
  # a reader closing its end of a real pipe leaves `$stderr` pointing at the
  # SAME IO object with a now-broken file descriptor (`$stderr.reopen`, or a
  # subprocess's inherited fd closing under it) -- and measured directly,
  # `warn` does not raise there, unlike `$stderr.puts`/`$stderr.write`. It
  # does raise if `$stderr` itself is reassigned to a different broken IO
  # object (`$stderr = other_io`), which is a test-harness shape, not
  # anything a closed pipe does to a running process. `warn` call sites in
  # this codebase are exempt by construction for the real failure mode, not
  # by oversight.
  module BestEffortWrite
    module_function

    # Returns the block's value, or nil if the write raised. Nothing reads
    # the value today -- either execution continues past a swallowed write,
    # or a raise that follows the call site is what matters.
    def attempt
      yield
    rescue StandardError
      nil
    end
  end
  # Internal. Reachable by the bare name from anywhere lexically inside
  # Elkrb, which is every call site there will be.
  private_constant :BestEffortWrite
end
