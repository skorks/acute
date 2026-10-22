module Acute
  # What every error acute raises on purpose includes, so one rescue catches them all
  module Error; end

  class ParseError < StandardError
    include Error

    attr_reader :code, :position, :unknown, :hint

    def initialize(message, code:, position:, unknown: [], hint: nil)
      super(message)
      @code = code
      @position = position
      @unknown = unknown
      @hint = hint
    end
  end

  # A bad value for an option; an ArgumentError, so code rescuing that is unchanged
  class OptionError < ArgumentError
    include Error

    attr_reader :option, :value

    def initialize(message, option:, value:)
      super(message)
      @option = option
      @value = value
    end
  end

  # What a stage returns instead of raising: start and stop are byte offsets into the text
  # @api private
  Failure = Struct.new(:code, :start, :stop)
end
