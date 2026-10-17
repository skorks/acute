module Acute
  # Atoms led by digits or a number word: clocks, numeric and ISO dates, years, "four twenty-three"
  class Grammar
    private

    def number_atom(loose)
      t = @t
      i = @i
      v = t[i + 1]
      flags = t[i + 2]
      digits = flags & L::DIGITS
      nk = @t[i + S]
      if nk == L::SLASH || nk == L::DOT
        return numeric_date(nk == L::SLASH ? :slash : :dot) if @t[i + 2 * S] == L::NUM
      elsif nk == L::DASH
        if @t[i + 2 * S] == L::NUM
          return iso_date if digits == 4
          w = t[i + 2 * S + 1]
          return numeric_date(:dash) if @t[i + 3 * S] == L::DASH || (w > 12 && w <= 31 && v <= 12) || v > 12 && v <= 31 && w <= 12
        end
      elsif nk == L::MONTH
        return day_month(v, i + S) if digits <= 2 && v >= 1 && v <= 31
      elsif nk == L::UNIT
        # D5: "1530h", "1530 hrs" are times
        if digits == 4 && t[i + S + 1] == :hour && @t[i + 2 * S] != L::WORD
          @i += 2 * S
          return four_digits(v, flags, i)
        end
      elsif nk == L::ORD
        q = quantity
        return shift_tail(q) if q
      elsif nk == L::WORD
        return clock_words(v) if minutes_to?(i)
        if t[i + S + 1] == :oclock
          @i += S
          c = number(v, flags, true)
          @i += S unless Failure === c
          return c
        end
      elsif nk == L::REL
        return clock_words(v) if t[i + S + 1] == :past && flags & L::WORDY != 0 || (v <= 30 && @t[i + 2 * S] == L::NUM)
      elsif nk == L::NUM
        # "four twenty-three"
        if flags & L::WORDY != 0 && t[i + S + 2] & L::WORDY != 0 && v.between?(1, 12) && t[i + S + 1].between?(10, 59)
          @i += S
          c = Clock.new(v, t[i + S + 1], 0, nil, nil, false, false)
          @i += S
          if @t[@i] == L::MER
            c.meridiem = @t[@i + 1] == 0 ? :am : :pm
            @i += S
          end
          return c
        end
      end
      if nk == L::UNIT || nk == L::SLASH
        q = quantity
        return shift_tail(q) if q
      end
      loose ||= @n == S + i || nk == L::DASH || (nk == L::WORD && (RANGE[t[i + S + 1]] || t[i + S + 1] == :and))
      number(v, flags, loose)
    end

    # D42: "five to 9" is 8:55 when the minutes are a word; "5 to 9" and "from five to nine" are ranges
    def minutes_to?(i)
      @t[i + S + 1] == :to && @t[i + 2] & L::WORDY != 0 && @t[i + 1].between?(1, 30) && @t[i + 2 * S] == L::NUM &&
        @t[i + 2 * S + 1].between?(1, 12) && !(i >= S && @t[i - S] == L::WORD && (@t[i - S + 1] == :from || @t[i - S + 1] == :between))
    end

    def iso_date
      t = @t
      i = @i
      y = t[i + 1]
      m = t[i + 2 * S + 1]
      if t[i + 2 * S + 2] & L::DIGITS == 3
        # "2026-001": the day of the year
        days = Calendar.days_from_civil(y, 1, 1) + m - 1
        return failure(:invalid_date, i + 2 * S) unless m >= 1 && Calendar.year_of(days) == y
        ymd = Calendar.civil_from_days(days)
        m = ymd / 100 % 100
        d = ymd % 100
        @i += 3 * S
      elsif @t[i + 3 * S] == L::DASH && @t[i + 4 * S] == L::NUM
        d = t[i + 4 * S + 1]
        @i += 5 * S
      else
        @i += 3 * S
        return Date.new(y, m, nil, nil, false)
      end
      date = Date.new(y, m, d, nil, false)
      @i += S if @t[@i + 1] == :t && @t[@i + S] == L::CLOCK
      return date unless @t[@i] == L::CLOCK
      c = written(@t[@i + 1], @t[@i + 2])
      return c if Failure === c
      c.h24 = true unless c.meridiem || c.named # D4, D29: after an ISO date the time is 24-hour
      Within.new(c, date)
    end

    # "10/23", "23/10/2026", "11.9.2003", "8-15": the numbers as written; resolve picks the order
    def numeric_date(sep)
      t = @t
      i = @i
      a = t[i + 1]
      b = t[i + 2 * S + 1]
      @i += 3 * S
      year = nil
      short = false
      if @t[@i] == t[i + S] && @t[@i + S] == L::NUM
        digits = t[@i + S + 2] & L::DIGITS
        return failure(:invalid_date, @i + S) unless digits == 2 || digits == 4
        year = t[@i + S + 1]
        short = digits == 2
        @i += 2 * S
        # D37: year first only when the first number has four digits
        return Date.new(a, b, year, nil, false) if t[i + 2] & L::DIGITS == 4 && !short
      end
      Date.new(year, a, b, sep, short)
    end

    # "23 oct", "23 oct 2026"
    def day_month(day, i)
      @i = i + S
      Date.new(year, @t[i + 1], day, nil, false)
    end

    # "oct", "oct 23", "oct 23rd, 2026", "may 2010"
    def month_atom
      m = @t[@i + 1]
      @i += S
      day = nil
      k = @t[@i]
      if (k == L::NUM || k == L::ORD) && @t[@i + 2] & L::DIGITS <= 2 && @t[@i + 1] >= 1 && @t[@i + 1] <= 31 &&
         @t[@i + S] != L::MER && @t[@i + S] != L::UNIT
        day = @t[@i + 1]
        @i += S
      end
      Date.new(year, m, day, nil, false)
    end

    # An optional year after a date: four digits, or "of 2026"
    def year
      @i += S if @t[@i + 1] == :of && @t[@i + S] == L::NUM
      return unless @t[@i] == L::NUM && @t[@i + 2] & L::DIGITS == 4 && @t[@i + 2] & L::ZERO == 0
      @i += S
      @t[@i - S + 1]
    end

    def named(hour) = Clock.new(hour, 0, 0, nil, hour == 12 ? :noon : :midnight, false, false)

    # loose: a bare number counts as an hour (after "at" or another constituent, in a range, or alone)
    def number(v, flags, loose)
      digits = flags & L::DIGITS
      zero = flags & L::ZERO != 0
      at = @i
      @i += S
      kind = @t[@i]
      if (kind == L::MER || (kind == L::ART && @t[at + 4] == @t[@i + 3])) && digits <= 2 # "8a"
        return failure(:invalid_date, at) if v < 1 || v > 12
        meridiem = kind == L::ART || @t[@i + 1] == 0 ? :am : :pm
        @i += S
        Clock.new(v, 0, 0, meridiem, nil, false, false)
      elsif kind == L::NAMED && v == 12 && digits <= 2
        @i += S
        named(@t[@i - S + 1])
      elsif digits == 4
        four_digits(v, flags, at)
      elsif digits <= 2 && loose && kind != L::NUM
        return failure(:invalid_date, at) if v > 23
        Clock.new(v, 0, 0, nil, nil, zero, false)
      else
        failure(:incomplete, at)
      end
    end

    # D5: a time with a leading zero, after "at", or with "h"/"hrs"; otherwise a year
    def four_digits(v, flags, at)
      if flags & L::ZERO != 0 || (at >= S && @t[at - S] == L::AT) || @t[at + S] == L::UNIT
        return failure(:invalid_date, at) if v / 100 > 23 || v % 100 > 59
        Clock.new(v / 100, v % 100, 0, nil, nil, flags & L::ZERO != 0, false)
      else
        Date.new(v, nil, nil, nil, false)
      end
    end

    def written(v, flags)
      hour = v / 10_000
      min = v / 100 % 100
      sec = v % 100
      at = @i
      @i += S
      return failure(:invalid_date, at) if hour > 23 || min > 59 || sec > 59
      kind = @t[@i]
      if kind == L::MER || (kind == L::ART && @t[at + 4] == @t[@i + 3]) # "9:00a"
        return failure(:invalid_date, at) if hour < 1 || hour > 12
        meridiem = kind == L::ART || @t[@i + 1] == 0 ? :am : :pm
        @i += S
        Clock.new(hour, min, sec, meridiem, nil, false, flags & L::SECONDS != 0)
      elsif kind == L::NAMED && hour == 12 && min == 0 && sec == 0
        @i += S
        named(@t[@i - S + 1])
      else
        Clock.new(hour, min, sec, nil, nil, flags & L::ZERO != 0, flags & L::SECONDS != 0)
      end
    end
  end
end
