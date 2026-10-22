module Acute
  # What every error acute raises on purpose includes, so one rescue catches them all
  module Error; end

  # T30: inspect escapes control characters but leaves Unicode format characters as they are, and a bidi
  # override in a quoted word can reorder how the rest of a terminal or log line reads. A message shows them
  # escaped, as inspect shows a newline; so are the control characters of a message that quotes raw (OptionParser's).
  INVISIBLE = /[\p{Cc}\p{Cf}\u2028\u2029]/
  def self.visible(message)
    return message unless message.match?(INVISIBLE)
    message.gsub(INVISIBLE) { _1.ord < 128 ? _1.inspect[1..-2] : format("\\u%04X", _1.ord) }
  end

  class ParseError < StandardError
    include Error

    attr_reader :code, :position, :unknown, :hint

    def initialize(message, code:, position:, unknown: [], hint: nil)
      super(Acute.visible(message))
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
      super(Acute.visible(message))
      @option = option
      @value = value
    end
  end

  # What a stage returns instead of raising: start and stop are byte offsets into the text
  # @api private
  Failure = Struct.new(:code, :start, :stop)
end
