module Acute
  # A range's two ends, and the atoms they share
  class Grammar
    private

    # The range's trailing atoms ("between 9:30 and 11:00 on thursday") belong to both ends, and so do its
    # leading ones ("monday 8-9am"). D44: a bare day takes its month from the other end ("june 3-7", "13 to
    # 15 july", "4 to 22 this month"), and a year said only at the end is the start's too.
    def range(from, to, fs, fe, ts)
      return Range.new(from, to) if Clock === from && Clock === to
      # "9:30 - 11:00 CST": the zone is a trailing atom too
      if Zoned === to && Clock === to.node
        return Zoned.new(Range.new(from, to.node), to.offset, to.numeric) if Clock === from
        # "15:00 GMT - 18:00 GMT": the same zone at both ends is one zone for the range
        if Zoned === from && Clock === from.node && from.offset == to.offset
          return Zoned.new(Range.new(from.node, to.node), to.offset, to.numeric)
        end
      end
      if Date === from && from.month && from.day && !from.sep && (Clock === to || (Date === to && !to.month)) &&
         (d = bare_day(ts, @i))
        to = Date.new(from.year, from.month, d, nil, from.short)
      elsif Date === to && to.month && to.day && !to.sep && (Clock === from || (Date === from && !from.month)) &&
            (d = bare_day(fs, fe))
        from = Date.new(to.year, to.month, d, nil, to.short)
      elsif Date === to && to.sep == :dot && to.year && to.month > 12 && to.day <= 12 && Clock === from && (d = bare_day(fs, fe))
        # D48: "12.-14.06.2021": a day before a dotted date that can only be day first is a day of its month
        to = Date.new(to.year, to.day, to.month, nil, to.short)
        from = Date.new(to.year, to.month, d, nil, to.short)
      elsif Within === to && size(to.outer) == 5 && (d = bare_day(fs, fe) || (Date === from && !from.month && from.day)) &&
            (e = Date === to.inner && !to.inner.month ? to.inner.day : Clock === to.inner && bare_day(ts, ts + S))
        return Range.new(Within.new(Date.new(nil, nil, d, nil, false), to.outer),
                         Within.new(Date.new(nil, nil, e, nil, false), to.outer))
      end
      if Date === from && Date === to && from.month && to.month && !from.year && to.year && from.sep == to.sep
        later = !from.sep && (from.month > to.month || (from.month == to.month && (from.day || 0) > (to.day || 0)))
        from = Date.new(later ? to.year - 1 : to.year, from.month, from.day, from.sep, to.short)
      end
      if Within === to && Clock === from && Clock === to.inner
        return Within.new(Range.new(from, to.inner), to.outer)
      end
      return Within.new(Range.new(from.inner, to), from.outer) if Within === from && Clock === from.inner && Clock === to
      Range.new(from, to)
    end

    # D44: "later than 9:30 but before 11:00 on thursday" is the range between two clock times; the day an
    # after starts on, or ends on, would differ from a range's
    def between(dir, node)
      r = Within === node ? node.inner : node
      return failure(:conflict) unless (dir == :after || dir == :from) && Range === r && Clock === r.from && Clock === r.to
      node
    end

    # D44: "2012 or later", "3 pm onwards": from X on; "2012 or earlier": until X's end, with no start. "or
    # after" and "or before" only end the phrase: "before 2010 or after 2018" is two
    def open_after(node)
      return node if Failure === node || Unit === node
      return failure(:conflict) if @but # "9 but before 11" says after nothing
      return node unless @t[@i] == L::WORD
      w = @t[@i + 1]
      if w == :or && @i + 2 * S == @n && @t[@i + S] == L::WORD && ((x = @t[@i + S + 1]) == :after || x == :before)
        @i += S
        w = x == :after ? :orlater : :orearlier
      end
      return node unless w == :orlater || w == :orearlier
      @i += S
      Open.new(w == :orlater ? :from : :through, node)
    end

    # D44: "june 12-14, 2021", "august 10 to 22 2012": a bare day and a year end a range begun with a month's
    # day, and the year is both ends'
    def day_and_year(from, ts)
      return unless Date === from && from.month && from.day && !from.year && !from.sep
      return unless @t[ts + S] == L::NUM && @t[ts + S + 2] & L::DIGITS == 4 && (d = bare_day(ts, ts + S))
      year = @t[ts + S + 1]
      @i = ts + 2 * S
      Range.new(Date.new(year, from.month, from.day, nil, false), Date.new(year, from.month, d, nil, false))
    end

    # The day a range end written as one number or ordinal names ("15", "the 15th"), or nil
    def bare_day(s, e)
      s += S if @t[s + 1] == :the
      return unless e == s + S && (@t[s] == L::NUM || @t[s] == L::ORD) && @t[s + 2] & (L::DIGITS | L::SHORT) <= 2
      v = @t[s + 1]
      v if v >= 1 && v <= 31
    end
  end
end
