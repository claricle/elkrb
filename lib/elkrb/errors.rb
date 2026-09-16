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

  # Exception raised when input cannot be parsed. Carries the source position
  # so a caller can report it without re-parsing the message.
  class ParseError < Error
    attr_reader :line, :column

    def initialize(message, line: nil, column: nil)
      @line = line
      @column = column
      super(message)
    end
  end

  # Exception raised when an algorithm is not found
  class AlgorithmNotFoundError < Error
    attr_reader :algorithm_name

    def initialize(algorithm_name)
      @algorithm_name = algorithm_name
      super("Algorithm not found: #{algorithm_name}")
    end
  end

  # Raised when a command has already ATTEMPTED to report its own failure and
  # the only thing left to decide is the exit status. Reporting is best-effort:
  # a dead stdout leaves nothing printed and this is still raised, so do not
  # assume the user saw anything. `exe/elkrb` turns it into `exit 1`; a library
  # caller rescues it and keeps its process.
  class CommandFailed < Error; end
end
