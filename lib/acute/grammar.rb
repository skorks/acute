require_relative "lexer"

module Acute
  # Tokens to a tree of what was said, by recursive descent. It knows nothing of now, the zone or the
  # D-rules: a bare "4" stays hour 4 with no am/pm, and resolve decides what that means.
  #
  #   phrase := NOW | day [at] clock | day | [at] clock [day]
  #   clock  := NUM MER | CLOCK [MER] | NAMED | 12 NAMED | 12:00 NAMED | NUM (after "at" or a day, or alone)
  class Grammar
    # h24: written with a leading zero, a 24-hour form (D4); seconds: written with seconds
    Clock = Struct.new(:hour, :min, :sec, :meridiem, :named, :h24, :seconds)
    DayRef = Struct.new(:offset)
    Moment = Struct.new(:day, :clock)
    Now = Struct.new
    NOW = Now.new.freeze

    NUM = Lexer::NUM
    CLOCK = Lexer::CLOCK
    MER = Lexer::MER
    DAY = Lexer::DAY
    NAMED = Lexer::NAMED
    AT = Lexer::AT
    S = Lexer::STRIDE

    def self.parse(tokens) = new(tokens).phrase

    def initialize(tokens)
      @t = tokens
      @n = tokens.size
      @i = 0
    end

    def phrase
      return failure(:incomplete) if @n == 0
      if @t[@i] == Lexer::NOW
        @i += S
        node = NOW
      elsif @t[@i] == DAY
        node = DayRef.new(@t[@i + 1])
        @i += S
        at = skip_at
        if @i < @n
          clock = clock(true)
          return clock if Failure === clock
          node = Moment.new(node, clock)
        elsif at
          return failure(:incomplete)
        end
      else
        at = skip_at
        node = clock(at || @n == S) # D41: a lone number is an hour, as in chronic
        return node if Failure === node
        if @i < @n && @t[@i] == DAY
          node = Moment.new(DayRef.new(@t[@i + 1]), node)
          @i += S
        end
      end
      return failure(:conflict) if @i < @n
      node
    end

    private

    def skip_at
      return false unless @i < @n && @t[@i] == AT
      @i += S
      true
    end

    # loose: a bare number counts as an hour (after "at" or a day word)
    def clock(loose)
      return failure(:incomplete) if @i >= @n
      t = @t
      i = @i
      case t[i]
      when NAMED
        @i += S
        named(t[i + 1])
      when NUM then number(t[i + 1], t[i + 2], loose)
      when CLOCK then written(t[i + 1], t[i + 2])
      else failure(:conflict)
      end
    end

    def named(hour) = Clock.new(hour, 0, 0, nil, hour == 12 ? :noon : :midnight, false, false)

    def number(v, flags, loose)
      digits = flags & Lexer::DIGITS
      zero = flags & Lexer::ZERO != 0
      at = @i
      @i += S
      kind = @i < @n ? @t[@i] : -1
      if kind == MER && digits <= 2
        return failure(:invalid_date, at) if v < 1 || v > 12
        meridiem = @t[@i + 1] == 0 ? :am : :pm
        @i += S
        Clock.new(v, 0, 0, meridiem, nil, false, false)
      elsif kind == NAMED && v == 12 && digits <= 2
        @i += S
        named(@t[@i - S + 1])
      elsif digits == 4 && (zero || (at >= S && @t[at - S] == AT))
        return failure(:invalid_date, at) if v / 100 > 23 || v % 100 > 59
        Clock.new(v / 100, v % 100, 0, nil, nil, zero, false)
      elsif digits <= 2 && loose
        return failure(:invalid_date, at) if v > 23
        Clock.new(v, 0, 0, nil, nil, zero, false)
      else
        failure(:incomplete, at)
      end
    end

    def written(v, flags)
      hour = v / 10_000
      min = v / 100 % 100
      sec = v % 100
      at = @i
      @i += S
      return failure(:invalid_date, at) if hour > 23 || min > 59 || sec > 59
      kind = @i < @n ? @t[@i] : -1
      if kind == MER
        return failure(:invalid_date, at) if hour < 1 || hour > 12
        meridiem = @t[@i + 1] == 0 ? :am : :pm
        @i += S
        Clock.new(hour, min, sec, meridiem, nil, false, flags & Lexer::SECONDS != 0)
      elsif kind == NAMED && hour == 12 && min == 0 && sec == 0
        @i += S
        named(@t[@i - S + 1])
      else
        Clock.new(hour, min, sec, nil, nil, flags & Lexer::ZERO != 0, flags & Lexer::SECONDS != 0)
      end
    end

    # Points at token index i, or at the end of the text when the tokens ran out
    def failure(code, i = @i)
      if i < @n
        Failure.new(code, @t[i + 3], @t[i + 4])
      else
        stop = @n == 0 ? 0 : @t[@n - 1]
        Failure.new(code, stop, stop)
      end
    end
  end
end
