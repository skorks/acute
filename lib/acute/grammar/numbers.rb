module Acute
  # Atoms led by digits or a number word: clocks, numeric and ISO dates, years
  class Grammar
    MULTIPLIERS = { hundred: 100, thousand: 1000, million: 1_000_000 }.freeze

    private

    # D47: a count said past ninety-nine, "two million eight hundred and sixty seven thousand five hundred and
    # thirty two", "a hundred": its value and the index of its last token, or nil without a hundred, thousand or
    # million straight after the first number
    def spoken(i)
      t = @t
      return unless t[i + S] == L::WORD && MULTIPLIERS[t[i + S + 1]]
      if t[i] == L::ART then group = 1
      elsif t[i] == L::NUM && t[i + 1].between?(1, 99) then group = t[i + 1]
      else return
      end
      total = 0
      hundred = false
      below = nil # each thousand or million is smaller than the one before
      last = i
      j = i + S
      while j < @n
        k = t[j]
        m = k == L::WORD && MULTIPLIERS[t[j + 1]]
        if m == 100
          break if hundred || group < 1 || group > 99
          group *= 100
          hundred = true
        elsif m
          break if group < 1 || (below && m >= below)
          total += group * m
          group = 0
          hundred = false
          below = m
        elsif k == L::WORD && t[j + 1] == :and && t[j + S] == L::NUM && t[last] == L::WORD
          j += S
          next
        elsif k == L::NUM && t[last] == L::WORD && group % 100 == 0 && t[j + 1].between?(1, 99) &&
              t[j + 2] & L::WORDY != 0
          group += t[j + 1]
        else
          break
        end
        last = j
        j += S
      end
      [total + group, last]
    end

    def number_atom(loose)
      t = @t
      i = @i
      v = t[i + 1]
      flags = t[i + 2]
      digits = flags & L::DIGITS
      nk = @t[i + S]
      if nk == L::SLASH || nk == L::DOT
        return dotted_clock(i) if nk == L::DOT && dotted_clock?(i)
        return dashed_month(v, digits) if @t[i + 2 * S] == L::MONTH && joined?(i + S) # "25/Sep/2003"
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
          # D44: "2014-2018" is a range of years; "0900-1700" and "2010-2015-86" are not
          return iso_date if digits == 4 && (f & L::DIGITS != 4 || flags & L::ZERO != 0 || @t[i + 3 * S] == L::DASH)
          w = t[i + 2 * S + 1]
          # D44: not before a month's name, where they are its days ("12-14 June")
          if @t[i + 3 * S] == L::DASH || (@t[i + 3 * S] != L::MONTH && ((w > 12 && w <= 31 && v <= 12) || v > 12 && v <= 31 && w <= 12))
            return numeric_date(:dash)
          end
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
        if digits <= 2 && v <= 23 && t[i + S + 1] == :hour && t[i + S + 4] - t[i + 4] == 1 && t[i + 4] == t[i + S + 3] &&
           (c = h_clock(v, i, loose))
          return c
        end
      elsif (nk == L::WDAY || nk == L::WEEKEND || nk == L::HOLIDAY || nk == L::PART) && counted?(i + S)
        @i += S
        return counted(v)
      elsif nk == L::ORD
        q = quantity
        return shift_tail(q) if q
      elsif nk == L::WORD
        return clock_words(v) if minutes_to?(i)
        return shift_tail(q) if MULTIPLIERS[t[i + S + 1]] && (q = quantity)
        if t[i + S + 1] == :ad && flags & L::WORDY == 0 && v >= 1 # D44: "14 a.d." is the year 14
          @i += 2 * S
          return Date.new(v, nil, nil, nil, false)
        end
        return w if flags & L::WORDY != 0 && (w = said(v, i))
        # D44: "15 of february", "20 of next month": a number of a month is its day, as an ordinal is; not
        # "5 to 6 of April 22", where the month has its own
        if t[i + S + 1] == :of && digits <= 2 && v >= 1 && v <= 31
          mk = @t[i + 2 * S]
          return day_month(v, i + 2 * S) if mk == L::MONTH && !(@t[i + 3 * S] == L::NUM && @t[i + 3 * S + 2] & L::DIGITS <= 2)
          if mk == L::REL && @t[i + 3 * S] == L::UNIT && @t[i + 3 * S + 1] == :month
            @i += S
            return of(Date.new(nil, nil, v, nil, false))
          end
        end
        if t[i + S + 1] == :oclock
          if v == 24 && @t[i + 2 * S] != L::MER # D44: as "24:00"
            @i += 2 * S
            return Clock.new(24, 0, 0, nil, nil, true, false)
          end
          @i += S # read from the o'clock, so a meridiem after it is the clock's: "11 o'clock pm"
          return number(v, flags, true)
        end
      elsif nk == L::REL
        # D44: "2 upcoming weeks", "10 previous weeks" are "next 2 weeks", "previous 10 weeks"
        if t[i + 2 * S] == L::UNIT && t[i + 2 * S + 2] & L::PLURAL != 0
          @i += 3 * S
          return Rel.new(t[i + S + 1], Unit.new(t[i + 2 * S + 1], v))
        end
        return clock_words(v) if t[i + S + 1] == :past && flags & L::WORDY != 0 || (v <= 30 && (@t[i + 2 * S] == L::NUM || @t[i + 2 * S] == L::NAMED))
      elsif nk == L::DECADE
        # "nineteen seventies"
        if flags & L::WORDY != 0 && t[i + S + 2] & L::WORDY != 0 && v >= 10
          @i += 2 * S
          return Years.new(:decade, v * 100 + t[i + S + 1], false)
        end
      elsif nk == L::NUM
        return w if flags & L::WORDY != 0 && (w = said(v, i))
        return spaced_date(v, digits) if spaced_date?(i, digits)
        # D44: "at 3 15", "at 12 05": after "at", an hour then two digits are its minutes, as said aloud
        if digits <= 2 && v <= 23 && i >= S && t[i - S] == L::AT && t[i + S + 2] & (L::DIGITS | L::WORDY) == 2 && t[i + S + 1] <= 59
          @i += S
          return written(v * 10_000 + t[i + S + 1] * 100, flags & L::ZERO)
        end
      end
      if nk == L::UNIT || nk == L::SLASH
        # D44: "20 minutes past 3pm", "ten minutes to three"
        return clock_words(v) if t[i + S + 1] == :minute && v.between?(1, 59) && clock_word?(i + 2 * S) && hour?(i + 3 * S)
        q = quantity
        return shift_tail(q) if q
      end
      loose ||= @n == S + i || nk == L::DASH || (nk == L::WORD && (RANGE[t[i + S + 1]] || t[i + S + 1] == :and)) ||
                part_next?(i + S) || (@n == 2 * S + i && t[i + S + 1] == :around) # "11ish"
      number(v, flags, loose)
    end

    # "6 in the morning", "12 at night", D44: "7 tonight", "8 this evening", "9 tomorrow", "7, this morning":
    # a part of day or a day after a bare number makes it an hour; D46: so does "on" and a named day,
    # "5 on may 28", "5 on friday", as "at 5 on may 28"
    def part_next?(j)
      k = @t[j]
      return true if k == L::PART || k == L::DAY || (k == L::REL && @t[j + S] == L::PART)
      if k == L::WORD && @t[j + 1] == :on
        k = @t[j + S]
        return k == L::MONTH || k == L::WDAY || k == L::HOLIDAY
      end
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
        # D37: year first only when the first number has four digits: "2026/11/23"; D44: or is marked as a
        # year by an apostrophe, or is past 31: "'69-5-31", "78-12-22"
        f = t[i + 2]
        if digits <= 2 && (f & L::DIGITS == 4 || (f & L::DIGITS == 2 && (f & L::SHORT != 0 || a > 31)))
          @i += 2 * S
          return Date.new(a, b, t[@i - S + 1], nil, f & L::DIGITS == 2)
        end
        return failure(:invalid_date, @i + S) unless digits == 2 || digits == 4
        year = t[@i + S + 1]
        short = digits == 2
        @i += 2 * S
      elsif (d = t[i + 2 * S + 2] & L::DIGITS) == 4 || t[i + 2] & L::DIGITS == 4
        # D44: "11/2026", "2013/12": a month and its year
        return d == 4 ? Date.new(b, a, nil, nil, false) : Date.new(a, b, nil, nil, false) if (d == 4 ? a : b).between?(1, 12)
      elsif @t[@i] == L::NUM && short_year?(@t[@i + 2]) # D44: "08/12,15", as "3 jan 10"
        year = @t[@i + 1]
        short = true
        @i += S
      end
      Date.new(year, a, b, sep, short)
    end

    # "23 oct", "23 oct 2026"
    def day_month(day, i)
      @i = i + S
      dated(@t[i + 1], day)
    end

    # D44: a dash or slash with no space either side joins the parts of one written date: "20-Apr",
    # "30-Mar-11", "2003-Sep-25", "99-Jan-08", "25/Sep/2003". A first number past 31 is the year.
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

    # A dash, or a slash, at token index i with no space either side
    def joined?(i) = (@t[i] == L::DASH || @t[i] == L::SLASH) && i >= S && @t[i - 1] == @t[i + 3] && @t[i + 4] == @t[i + S + 3]

    # "oct", "oct 23", "oct 23rd, 2026", "may 2010", "Oct-2", "Sep-25-2003", "Sep-2012", "Sep/25/2003"
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
      if @t[@i] == L::NUM && @t[@i + S + 1] == :ad && @t[@i + S] == L::WORD && f & L::WORDY == 0 # D44: "10 August 88 AD"
        @i += 2 * S
        return Date.new(@t[@i - 2 * S + 1], m, day, nil, false)
      end
      # D44: "dec 79", "may 97": with no day, two digits past 31 are the year
      if @t[@i] == L::NUM && ((f & L::DIGITS == 4 && f & L::ZERO == 0) || f & L::SHORT != 0 ||
                              ((day || @t[@i + 1] > 31) && short_year?(f)))
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
      @i += 2 * S if in_the_meridiem?
      if @t[@i + 1] == :around && @t[@i + S] == L::MER && @t[@i] == L::WORD && @t[at + 4] == @t[@i + 3] # D48: "3ish pm"
        @approx = true
        @i += S
      end
      kind = @t[@i]
      if (kind == L::MER || (kind == L::ART && @t[at + 4] == @t[@i + 3])) && digits <= 2 # "8a"
        return failure(:invalid_date, at) if (v < 1 && !midnight_am?(kind)) || v > 12
        meridiem = kind == L::ART || @t[@i + 1] == 0 ? :am : :pm
        @i += S
        Clock.new(v, 0, 0, meridiem, nil, false, false)
      elsif kind == L::NAMED && v == 12 && digits <= 2
        @i += S
        named(@t[@i - S + 1])
      elsif (digits == 3 && (at >= S && (@t[at - S] == L::AT || @t[at - S] == L::PART))) || ((digits == 3 || digits == 4) && kind == L::MER)
        three_digits(v, at)
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
  end
end
