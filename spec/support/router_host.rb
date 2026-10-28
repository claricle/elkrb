# frozen_string_literal: true

# A bare host for the EdgeRouter mixin: the resolver the mixin reads, and none
# of BaseAlgorithm.
class RouterHost
  include Elkrb::Layout::EdgeRouter

  attr_reader :resolver

  # @param call_options [Hash] the call-level options the resolver falls back to
  def initialize(call_options = {})
    @resolver = Elkrb::Options::Resolver.new(call_options)
  end
end
