module Acute
  # Lengths of time: counted units only, so "next friday" is not one
  class Grammar
    def self.duration(tokens, bare = nil, skip = false) = new(tokens).duration(bare, skip)

    # "3 days", "1h 30m", "2 weeks and 3 days", "1 hour plus 30 minutes", "an hour and a half", "half an hour",
    # "for 5 days": the Units said. With a bare unit, chronic_duration's forms too (D46): see chrono. With skip,
    # a token no part reads is passed over, as the chronic_duration gems pass over words they don't know.
    def duration(bare = nil, skip = false)
      @bare = bare
      parts = []
      @i += S if @t[0] == L::WORD && @t[1] == :for
      while @i < @n
        @i += S if parts.any? && ((w = @t[@i + 1]) == :and || w == :plus || @t[@i] == L::PLUS) # D44
        if parts.any? && (q = duration_tail(parts.last.unit))
          parts << q
          next
        end
        if bare && (q = chrono(parts.empty?))
          parts.concat(q)
          next
        end
        start = @i
        @lone = parts.empty?
        half = @t[@i + 1] == :half
        @i += S if half
        q = if half && @t[@i] == L::UNIT # "half hour"
              @i += S
              Unit.new(@t[@i - S + 1], 1)
            elsif !half || @t[@i] == L::ART # D47: "half an hour", not "half145h"
              duration_quantity
            end
        unless q && (q.count.positive? || (bare && q.count == 0))
          return failure(@i < @n ? :conflict : :incomplete) unless skip
          @i = start + S
          next
        end
        q.count = Rational(q.count, 2) if half
        parts << q
      end
      parts.empty? ? failure(:incomplete) : parts
    end

    private

    # D46, chronic_duration's forms: a clock group is minutes and seconds, or hours, minutes and seconds ("1:20.51",
    # "4:01:01"), but not straight after another; with days, months and years before it, it is the lexer's FIELDS
    # ("6:01:00:00", "1:00:01:00:00:00"). A unit first counts one ("day", "minute 30s"). A count alone is that
    # many bare units ("5"), and a count may be zero; quantity reads those.
    def chrono(first)
      if first && (unit = unit_at(@i))
        @i += S
        return [Unit.new(unit, 1)]
      end
      return fields if @t[@i] == L::FIELDS
      return unless @t[@i] == L::CLOCK && (first || @t[@i - S] != L::CLOCK)
      v = @t[@i + 1]
      flags = @t[@i + 2]
      @i += S
      fraction = flags >> L::FRACTION
      if flags & L::SECONDS != 0
        s = v % 100 + Rational(fraction >> 5, 10**(fraction & 31))
        return [Unit.new(:hour, v / 10_000), Unit.new(:minute, v / 100 % 100), Unit.new(:second, s)]
      end
      s = v / 100 % 100
      if @t[@i] == L::DOT && @t[@i + S] == L::NUM && touching?(@i - S, @i + S)
        s += Rational(@t[@i + S + 1], 10**(@t[@i + S + 2] & L::DIGITS))
        @i += 2 * S
      end
      [Unit.new(:minute, v / 10_000), Unit.new(:second, s)]
    end

    FIELD_UNITS = %i[second minute hour day month year].freeze

    # "2:04:13:02" is days to seconds; "6:01:00:00:00" months to seconds; six fields start with years
    def fields
      v = @t[@i + 1]
      flags = @t[@i + 2]
      @i += S
      fraction = flags >> L::FRACTION
      k = flags & L::DIGITS
      units = Array.new(k) do |j|
        count = j == k - 1 ? v : v % 100
        v /= 100
        Unit.new(FIELD_UNITS[j], count)
      end
      units[0].count += Rational(fraction >> 5, 10**(fraction & 31)) if fraction > 0
      units.reverse!
    end

    # After a unit: "and a half", "and half", "and three quarters" are that much of it; a bare number last is
    # the next smaller unit's ("1 hour thirty", "2 hours and 10")
    def duration_tail(unit)
      if (f = fraction(@i)) && @t[f[0]] != L::UNIT && @t[f[0]] != L::ART
        @i = f[0]
        return Unit.new(unit, f[1])
      end
      return unless @t[@i] == L::NUM && @i + S == @n && (unit == :hour || unit == :minute) && @t[@i + 1].between?(1, 59)
      @i += S
      Unit.new(unit == :hour ? :minute : :second, @t[@i - S + 1])
    end

    # "two and a half years", "one and three quarters of an hour", "a quarter of an hour", "3-min", "2 more
    # minutes", or a quantity
    def duration_quantity
      i = @i
      if (f = fraction(i)) && @t[f[0] + 1] == :of && @t[f[0]] == L::WORD
        j = f[0] + S
        j += S if @t[j] == L::ART
        if (unit = unit_at(j))
          @i = j + S
          return Unit.new(unit, f[1])
        end
      end
      if @t[i] == L::DECADE && @t[i + 2] & (L::WORDY | L::QUOTED) == 0 # "5400s": in a length, seconds, whatever the digits; not "70's" or "nineties" (D50)
        @i = i + S
        return Unit.new(:second, @t[i + 1])
      end
      return quantity unless @t[i] == L::NUM
      if @t[i + S + 1] == :and && (f = fraction(i + 2 * S))
        j = f[0]
        j += S if @t[j] == L::WORD && @t[j + 1] == :of
        j += S if @t[j] == L::ART
        if (unit = unit_at(j))
          @i = j + S
          return Unit.new(unit, @t[i + 1] + f[1])
        end
      end
      joined = @t[i + S] == L::DASH && @t[i + 4] == @t[i + S + 3] && @t[i + S + 4] == @t[i + 2 * S + 3]
      if (joined || @t[i + S + 1] == :more) && (unit = unit_at(i + 2 * S))
        @i = i + 3 * S
        return Unit.new(unit, @t[i + 1])
      end
      quantity
    end

    # A fraction from j, and where it ends: "a half", "half", "a quarter", "three quarters"
    def fraction(j)
      j += S if @t[j] == L::ART && @t[j + S + 1] == :half
      return [j + S, Rational(1, 2)] if @t[j] == L::WORD && @t[j + 1] == :half
      n = 1
      if @t[j] == L::ART || @t[j] == L::NUM
        n = @t[j + 1]
        j += S
      end
      [j + S, Rational(n, 4)] if @t[j] == L::UNIT && @t[j + 1] == :quarter && n.between?(1, 3)
    end
  end
end
