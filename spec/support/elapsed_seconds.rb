# frozen_string_literal: true

# Wall-clock seconds a block takes, on the monotonic clock. Used instead of
# `Benchmark.realtime` because `benchmark` is no longer a default gem on
# Ruby 4.0 and the Gemfile does not list it.
module ElapsedSeconds
  def elapsed_seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end
end

RSpec.configure { |config| config.include ElapsedSeconds }
