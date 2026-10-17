module Acute
  # Written forms with no words in them: ISO and compact ISO dates, ISO weeks, bare digits as clocks, dotted clocks
  class Grammar
    private

    # D44: "20261123", "20030925T104941", "20030925T10", "19980915T09:05:32": a compact ISO date, then the time after its T
    def compact_date(v, at)
      m = v / 100 % 100
      d = v % 100
      return failure(:invalid_date, at) unless m >= 1 && m <= 12 && d >= 1 && d <= 31
      date = Date.new(v / 10_000, m, d, nil, false)
      k = @t[@i]
      return date unless (k == L::NUM || k == L::CLOCK) && @t[@i + 3] - @t[at + 4] <= 1
      if k == L::CLOCK
        c = written(@t[@i + 1], @t[@i + 2])
        return c if Failure === c
      else
        n = @t[@i + 1]
        digits = @t[@i + 2] & L::DIGITS
        if digits == 2
          return failure(:invalid_date, @i) if n > 23
          @i += S
          return Within.new(Clock.new(n, 0, 0, nil, nil, true, :hour), date)
        end
        return failure(:invalid_date, @i) unless digits == 6 || digits == 4
        n *= 100 if digits == 4
        c = written(n, digits == 6 ? L::SECONDS : 0)
        return c if Failure === c
      end
      c.h24 = true unless c.meridiem
      Within.new(c, date)
    end

    # D44: "330 pm", "at 730 in the evening", "tonight 815": three digits marked as a time, by am or pm after
    # them or "at" or a part of day before, are its hour and minutes
    def three_digits(v, at)
      h = v / 100
      m = v % 100
      return failure(:invalid_date, at) if m > 59
      if @t[@i] == L::MER
        return failure(:invalid_date, at) if h > 12
        @i += S
        return Clock.new(h, m, 0, @t[@i - S + 1] == 0 ? :am : :pm, nil, false, false)
      end
      Clock.new(h, m, 0, nil, nil, false, false)
    end

    # D44: "15h30", "3h18": a joined "h" between hours and minutes is a 24-hour clock; "15h" alone after "at",
    # another atom or before a zone ("at 16h", "Thursday 8h GMT"). Nil when it counts: "2h ago", "15h" alone.
    def h_clock(v, i, loose)
      j = i + 2 * S
      if @t[j] == L::NUM && @t[j + 2] & L::DIGITS == 2 && @t[j + 3] == @t[i + S + 4]
        return failure(:invalid_date, j) if @t[j + 1] > 59
        @i = j + S
        return Clock.new(v, @t[j + 1], 0, nil, nil, true, false)
      end
      k = @t[j]
      return unless (loose && !(k == L::WORD && SHIFT_TAIL[@t[j + 1]])) || k == L::ZONE
      @i = j
      Clock.new(v, 0, 0, nil, nil, true, false)
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

    # D44: "9.30pm", "12.55 pm", "01.03.12 a.m.", "at 12.30": numbers joined by dots before am or pm, or two
    # after "at", are a clock
    def dotted_clock?(i)
      j = i + 2 * S
      return false unless @t[i + 2] & L::DIGITS <= 2 && @t[j] == L::NUM && @t[j + 2] & L::DIGITS == 2
      return @t[j + S] != L::DOT && @t[j + 1] <= 59 if i >= S && @t[i - S] == L::AT
      j += 2 * S if @t[j + S] == L::DOT && @t[j + 2 * S] == L::NUM && @t[j + 2 * S + 2] & L::DIGITS == 2
      @t[j + S] == L::MER
    end

    def dotted_clock(i)
      v = @t[i + 1] * 10_000 + @t[i + 2 * S + 1] * 100
      @i = i + 2 * S
      if @t[@i + S] == L::DOT
        @i += 2 * S
        return written(v + @t[@i + 1], L::SECONDS)
      end
      written(v, 0)
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
      @i += S if @t[@i] == L::WORD && @t[@i + 1] == :t && @t[@i + S] == L::CLOCK
      # D44: "2003-09-25T10", "1978-12-22T23Z": two digits alone after the date are its hour, at the hour's grain
      if @t[@i] == L::NUM && @t[@i + 2] & L::DIGITS == 2 && ((k = @t[@i + S]).nil? || k == L::ZONE) &&
         @t[@i + 3] - @t[@i - 1] <= 1
        return failure(:invalid_date, @i) if @t[@i + 1] > 23
        @i += S
        return Within.new(Clock.new(@t[@i - S + 1], 0, 0, nil, nil, true, :hour), date)
      end
      return date unless @t[@i] == L::CLOCK
      c = written(@t[@i + 1], @t[@i + 2])
      return c if Failure === c
      c.h24 = true unless c.meridiem || c.named # D4, D29: after an ISO date the time is 24-hour
      Within.new(c, date)
    end

    # D13: "week 42", "W42", "W42-3", "W423", "week 53 of 2026"
    def iso_week
      w = @t[@i + S + 1]
      day = nil
      if @t[@i + S + 2] & L::DIGITS == 3
        day = w % 10
        w /= 10
      end
      @i += 2 * S
      if !day && joined?(@i) && @t[@i + S] == L::NUM && @t[@i + S + 2] & L::DIGITS == 1 && @t[@i + S + 1].between?(1, 7)
        day = @t[@i + S + 1]
        @i += 2 * S
      end
      of(IsoWeek.new(w, day))
    end

    def week_number?(i)
      return false unless @t[i] == L::NUM
      v = @t[i + 1]
      # "W481": week 48, day 1, with no space after the W
      return @t[i - 1] == @t[i + 3] && (v / 10).between?(1, 53) && (v % 10).between?(1, 7) if @t[i + 2] & L::DIGITS == 3
      return false unless @t[i + 2] & L::DIGITS <= 2 && v.between?(1, 53)
      k = @t[i + S]
      k != L::UNIT && k != L::MER && k != L::SLASH && k != L::DOT && k != L::MONTH
    end
  end
end
