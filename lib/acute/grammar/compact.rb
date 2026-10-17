module Acute
  # Written forms with no words in them: ISO and compact ISO dates, dotted clocks
  class Grammar
    private

    # D44: "20261123", "20030925T104941", "19980915T09:05:32": a compact ISO date, then the time after its T
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
        return failure(:invalid_date, @i) unless digits == 6 || digits == 4
        n *= 100 if digits == 4
        c = written(n, digits == 6 ? L::SECONDS : 0)
        return c if Failure === c
      end
      c.h24 = true unless c.meridiem
      Within.new(c, date)
    end

    # D44: "9.30pm", "12.55 pm", "01.03.12 a.m.": numbers joined by dots before am or pm are a clock
    def dotted_clock?(i)
      j = i + 2 * S
      return false unless @t[i + 2] & L::DIGITS <= 2 && @t[j] == L::NUM && @t[j + 2] & L::DIGITS == 2
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
      @i += S if @t[@i + 1] == :t && @t[@i + S] == L::CLOCK
      return date unless @t[@i] == L::CLOCK
      c = written(@t[@i + 1], @t[@i + 2])
      return c if Failure === c
      c.h24 = true unless c.meridiem || c.named # D4, D29: after an ISO date the time is 24-hour
      Within.new(c, date)
    end
  end
end
