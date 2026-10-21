module Acute
  # Lengths of time: counted units only, so "next friday" is not one
  class Grammar
    def self.duration(tokens) = new(tokens).duration

    # "3 days", "1h 30m", "2 weeks and 3 days", "an hour and a half", "half an hour", "for 5 days": the Units said
    def duration
      parts = []
      @i += S if @t[0] == L::WORD && @t[1] == :for
      while @i < @n
        @i += S if parts.any? && (@t[@i + 1] == :and || @t[@i] == L::PLUS)
        if parts.any? && (q = duration_tail(parts.last.unit))
          parts << q
          next
        end
        half = @t[@i + 1] == :half
        @i += S if half
        if half && @t[@i] == L::UNIT # "half hour"
          q = Unit.new(@t[@i + 1], 1)
          @i += S
        elsif half && @t[@i] != L::ART # D47: "half an hour", not "half145h"
          return failure(@i < @n ? :conflict : :incomplete)
        else
          q = duration_quantity
        end
        return failure(@i < @n ? :conflict : :incomplete) unless q&.count&.positive?
        q.count = Rational(q.count, 2) if half
        parts << q
      end
      parts.empty? ? failure(:incomplete) : parts
    end

    private

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
