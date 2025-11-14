# frozen_string_literal: true

module Elkrb
  # Base error class for Elkrb
  class Error < StandardError; end

  # Exception raised when an unsupported configuration is detected
  class UnsupportedConfigurationException < Error
    attr_reader :option, :value

    def initialize(message, option: nil, value: nil)
      @option = option
      @value = value
      super(message)
    end
  end

  # Exception raised when graph validation fails
  class ValidationError < Error; end

  # Exception raised when an algorithm is not found
  class AlgorithmNotFoundError < Error
    attr_reader :algorithm_name

    def initialize(algorithm_name)
      @algorithm_name = algorithm_name
      super("Algorithm not found: #{algorithm_name}")
    end
  end
end
