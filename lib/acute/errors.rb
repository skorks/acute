module Acute
  class Error < StandardError; end

  class ParseError < Error
    attr_reader :code, :position, :unknown, :hint

    def initialize(message, code:, position:, unknown: [], hint: nil)
      super(message)
      @code = code
      @position = position
      @unknown = unknown
      @hint = hint
    end
  end

  # What a stage returns instead of raising: start and stop are byte offsets into the text
  Failure = Struct.new(:code, :start, :stop)
end
