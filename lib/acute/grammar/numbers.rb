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
        return dotted_clock(i) if nk == L::DOT && dotted_clock?(i)
        # "1/2 hour", "2.5 hours"; not "22/0 y"
        if @t[i + 3 * S] == L::UNIT && @t[i + 2 * S] == L::NUM && (q = quantity)
          return shift_tail(q)
        end
        return numeric_date(nk == L::SLASH ? :slash : :dot) if @t[i + 2 * S] == L::NUM
      elsif nk == L::DASH
        return dashed_month(v, digits) if @t[i + 2 * S] == L::MONTH && joined?(i + S)
        if @t[i + 2 * S] == L::NUM
          # "5-2020": a month and its year
          f = t[i + 2 * S + 2]
          if digits <= 2 && v >= 1 && v <= 12 && f & L::DIGITS == 4 && f & L::ZERO == 0 && joined?(i + S)
            @i += 3 * S
            return Date.new(t[i + 2 * S + 1], v, nil, nil, false)
          end
          return iso_date if digits == 4
          w = t[i + 2 * S + 1]
          return numeric_date(:dash) if @t[i + 3 * S] == L::DASH || (w > 12 && w <= 31 && v <= 12) || v > 12 && v <= 31 && w <= 12
        elsif digits == 4 && @t[i + 2 * S] == L::UNIT && joined?(i + S) && (y = week_year(v, i + S))
          return y
        end
      elsif nk == L::MONTH
        return day_month(v, i + S) if digits <= 2 && v >= 1 && v <= 31
      elsif nk == L::UNIT
        return y if digits == 4 && t[i + 4] == t[i + S + 3] && (y = week_year(v, i))
        # D5: "1530h", "1530 hrs" are times
        if digits == 4 && t[i + S + 1] == :hour && @t[i + 2 * S] != L::WORD
          @i += 2 * S
          return four_digits(v, flags, i)
        end
      elsif (nk == L::WDAY || nk == L::WEEKEND || nk == L::HOLIDAY) && counted?(i + S)
        @i += S
        return counted(v)
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
      elsif nk == L::DECADE
        # "nineteen seventies"
        if flags & L::WORDY != 0 && t[i + S + 2] & L::WORDY != 0 && v >= 10
          @i += 2 * S
          return Years.new(:decade, v * 100 + t[i + S + 1], false)
        end
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
      loose ||= @n == S + i || nk == L::DASH || (nk == L::WORD && (RANGE[t[i + S + 1]] || t[i + S + 1] == :and)) ||
                part_next?(i + S)
      number(v, flags, loose)
    end

    # "6 in the morning", "12 at night": a part of day after a bare number makes it an hour
    def part_next?(j)
      k = @t[j]
      return false unless k == L::AT || (k == L::WORD && @t[j + 1] == :in)
      j += S
      j += S if @t[j + 1] == :the
      @t[j] == L::PART
    end

    # D13: the year of "2026-W42", "2026W01"; the week follows as its own atom
    def week_year(v, j)
      return unless @t[j + S] == L::UNIT && @t[j + S + 1] == :week && week_number?(j + 2 * S)
      @i = j + S
      Date.new(v, nil, nil, nil, false)
    end

    # D42: "five to 9" is 8:55 when the minutes are a word; "5 to 9" and "from five to nine" are ranges
    def minutes_to?(i)
      @t[i + S + 1] == :to && @t[i + 2] & L::WORDY != 0 && @t[i + 1].between?(1, 30) && @t[i + 2 * S] == L::NUM &&
        @t[i + 2 * S + 1].between?(1, 12) && !(i >= S && @t[i - S] == L::WORD && (@t[i - S + 1] == :from || @t[i - S + 1] == :between))
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
        # D37: year first only when the first number has four digits: "2026/11/23"
        if t[i + 2] & L::DIGITS == 4 && digits <= 2
          @i += 2 * S
          return Date.new(a, b, t[@i - S + 1], nil, false)
        end
        return failure(:invalid_date, @i + S) unless digits == 2 || digits == 4
        year = t[@i + S + 1]
        short = digits == 2
        @i += 2 * S
      elsif (d = t[i + 2 * S + 2] & L::DIGITS) == 4 || t[i + 2] & L::DIGITS == 4
        # D44: "11/2026", "2013/12": a month and its year
        return d == 4 ? Date.new(b, a, nil, nil, false) : Date.new(a, b, nil, nil, false) if (d == 4 ? a : b).between?(1, 12)
      end
      Date.new(year, a, b, sep, short)
    end

    # "23 oct", "23 oct 2026"
    def day_month(day, i)
      @i = i + S
      dated(@t[i + 1], day)
    end

    # D44: a dash with no space either side joins the parts of one written date: "20-Apr", "30-Mar-11",
    # "2003-Sep-25", "99-Jan-08". A first number past 31 is the year.
    def dashed_month(v, digits)
      m = @t[@i + 2 * S + 1]
      @i += 3 * S
      if digits == 4 || v > 31
        day = nil
        if joined?(@i) && @t[@i + S] == L::NUM && @t[@i + S + 2] & L::DIGITS <= 2 && @t[@i + S + 1].between?(1, 31)
          day = @t[@i + S + 1]
          @i += 2 * S
        end
        return Date.new(v, m, day, nil, digits == 2)
      end
      return failure(:invalid_date, @i - 3 * S) if v < 1
      dashed_year(m, v) || dated(m, v)
    end

    # The "-1999" or "-99" that ends a dashed date
    def dashed_year(m, day)
      return unless joined?(@i) && @t[@i + S] == L::NUM
      digits = @t[@i + S + 2] & L::DIGITS
      return unless digits == 2 || digits == 4
      @i += 2 * S
      Date.new(@t[@i - S + 1], m, day, nil, digits == 2)
    end

    # A dash at token index i with no space either side
    def joined?(i) = @t[i] == L::DASH && i >= S && @t[i - 1] == @t[i + 3] && @t[i + 4] == @t[i + S + 3]

    # "oct", "oct 23", "oct 23rd, 2026", "may 2010", "Oct-2", "Sep-25-2003", "Sep-2012"
    def month_atom
      m = @t[@i + 1]
      @i += S
      if joined?(@i) && @t[@i + S] == L::NUM
        f = @t[@i + S + 2]
        v = @t[@i + S + 1]
        if f & L::DIGITS == 4 && f & L::ZERO == 0
          @i += 2 * S
          return Date.new(v, m, nil, nil, false)
        elsif f & L::DIGITS <= 2 && v >= 1 && v <= 31
          @i += 2 * S
          return dashed_year(m, v) || dated(m, v)
        end
      end
      day = nil
      k = @t[@i]
      if (k == L::NUM || k == L::ORD) && @t[@i + 2] & (L::DIGITS | L::SHORT) <= 2 && @t[@i + 1] >= 1 && @t[@i + 1] <= 31 &&
         @t[@i + S] != L::MER && @t[@i + S] != L::UNIT
        day = @t[@i + 1]
        @i += S
      end
      dated(m, day)
    end

    # The date with its optional year after it: four digits, "of 2026", "'26", or after a day two digits that
    # are not a clock ("3 jan 10", "may 27 79") (D23)
    def dated(m, day)
      @i += S if @t[@i + 1] == :of && @t[@i + S] == L::NUM
      f = @t[@i + 2]
      if @t[@i] == L::NUM && ((f & L::DIGITS == 4 && f & L::ZERO == 0) || f & L::SHORT != 0 || (day && short_year?(f)))
        @i += S
        return Date.new(@t[@i - S + 1], m, day, nil, f & L::DIGITS != 4)
      end
      Date.new(nil, m, day, nil, false)
    end

    def short_year?(f)
      return false unless f & L::DIGITS == 2
      k = @t[@i + S]
      k != L::MER && k != L::UNIT && k != L::NAMED && k != L::ART && k != L::DASH &&
        !(k == L::WORD && ((w = @t[@i + S + 1]) == :oclock || RANGE[w] || w == :and))
    end

    def named(hour) = Clock.new(hour, 0, 0, nil, hour == 12 ? :noon : :midnight, false, false)

    # loose: a bare number counts as an hour (after "at" or another constituent, in a range, or alone)
    def number(v, flags, loose)
      digits = flags & L::DIGITS
      zero = flags & L::ZERO != 0
      at = @i
      @i += S
      return Date.new(v, nil, nil, nil, true) if flags & L::SHORT != 0 # "halloween '11"
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
      elsif digits == 8
        compact_date(v, at)
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
