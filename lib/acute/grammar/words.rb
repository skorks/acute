module Acute
  # Atoms led by a word: weekdays, months, parts of day, next/last, early/late, "in", "a week"
  class Grammar
    private

    # An if chain, the commonest kinds first: a case over constants tests each with a method call
    def atom(loose)
      t = @t
      i = @i
      k = t[i]
      v = t[i + 1]
      if k == L::NUM then number_atom(loose)
      elsif k == L::CLOCK then written(v, t[i + 2])
      elsif k == L::DAY
        @i += S
        # "tomorrow week": a week after it
        if t[i + S] == L::UNIT && WEEKS[u = t[i + S + 1]] && (k = t[i + 2 * S]) != L::NUM && k != L::ORD
          @i += S
          return Shift.new(1, u, DayRef.new(v))
        end
        DayRef.new(v)
      elsif k == L::WDAY
        return failure(:incomplete) if t[i + 2] & L::PLURAL != 0
        @i += S
        around(of(Weekday.new(v)))
      elsif k == L::MONTH then around(month_atom)
      elsif k == L::REL then rel_atom
      elsif k == L::NAMED
        @i += S
        named(v)
      elsif k == L::ORD then ordinal_atom
      elsif k == L::PART
        return failure(:incomplete) if t[i + 2] & L::PLURAL != 0
        @i += S
        of(Part.new(v))
      elsif k == L::NOW
        @i += S
        NOW
      elsif k == L::HOLIDAY
        return failure(:incomplete) if t[i + 2] & L::PLURAL != 0
        @i += S
        # D48: "labor day weekend" is the long weekend with the holiday
        if t[@i] == L::WEEKEND
          @i += S
          return Within.new(WEEKEND, Holiday.new(v))
        end
        around(of(Holiday.new(v)))
      elsif k == L::WORD then word_atom(v)
      elsif k == L::ART then article_atom
      elsif k == L::FUZZ then fuzzy_atom
      elsif k == L::WEEKEND
        @i += S
        around(WEEKEND)
      elsif k == L::SEASON
        @i += S
        of(Season.new(v))
      elsif k == L::UNIT
        return clock_words(15) if v == :quarter && @t[i + S] == L::REL || @t[i + S + 1] == :to
        return iso_week if v == :week && week_number?(i + S)
        # D44: "H1 2027", "H2 2026"
        if v == :hour && t[i + 4] - t[i + 3] == 1 && t[i + S] == L::NUM && t[i + S + 1].between?(1, 2) && t[i + 4] == t[i + S + 3] &&
           t[i + 2 * S] == L::NUM && t[i + 2 * S + 2] & L::DIGITS == 4
          @i += 3 * S
          return Within.new(half(t[i + S + 1]), Date.new(t[i + 2 * S + 1], nil, nil, nil, false))
        end
        # "the year 1980", "in the year '89", "the year twenty ten", "the year two thousand"
        if v == :year && t[i + S] == L::NUM && ((f = t[i + S + 2]) & L::DIGITS == 4 || f & L::SHORT != 0 ||
                                                (f & L::WORDY != 0 && (t[i + 2 * S] == L::NUM || t[i + 2 * S + 1] == :thousand)))
          @i += S
          return number_atom(true)
        end
        # D48: "year 247": three digits after "year" are the year as written
        if v == :year && t[i + S] == L::NUM && t[i + S + 2] & L::DIGITS == 3 && t[i + S + 2] & L::ZERO == 0 && i + 2 * S >= @n
          @i += 2 * S
          return Date.new(t[i + S + 1], nil, nil, nil, false)
        end
        if (w = t[i + S + 1]) == :after || w == :before # "the day after tomorrow"
          @i += S
          # "the week after next", "the month after the next": the one after next week, when "next" has
          # nothing of its own
          j = i + 2 * S
          j += S if t[j] == L::WORD && t[j + 1] == :the
          if w == :after && t[j + 1] == :next && t[j] == L::REL && nothing_own?(j + S)
            @i = j + S
            return Shift.new(1, v, Rel.new(:next, Unit.new(v, nil)))
          end
          return shift_tail(Unit.new(v, 1))
        end
        return shift_tail(Unit.new(v, 1)) if starting?(i + S) && (@i += S) # "the week starting february 4"
        # D44: "the week of october 6th", "the month of may": the one that holds it
        if (v == :week || v == :month) && w == :of && t[i + S] == L::WORD
          @i += 2 * S
          node = item(true)
          return Failure === node ? node : Holding.new(v, node)
        end
        failure(:incomplete)
      elsif k == L::DECADE then decade_atom
      elsif k == L::MER && t[i + S] == L::CLOCK && i >= S && t[i - S] == L::NUM then meridiem_first(v)
      else failure(:conflict)
      end
    end

    # D48: "2020/10/9 PM 2:26": a meridiem before the clock after a date, the East Asian order
    def meridiem_first(v)
      at = @i
      @i += S
      c = written(@t[@i + 1], @t[@i + 2])
      return failure(:conflict, at) unless Clock === c && !c.meridiem && c.hour >= 1 && c.hour <= 12
      Clock.new(c.hour, c.min, c.sec, v == 0 ? :am : :pm, nil, false, c.seconds, c.frac)
    end

    # "the 90s", "1990s"; "30s ago" is seconds
    def decade_atom
      return shift_tail(quantity) if SHIFT_TAIL[@t[@i + S + 1]] # D47: "5400s ago" as "30s ago"
      v = @t[@i + 1]
      @i += S
      Years.new(:decade, v, v < 100)
    end

    def word_atom(v)
      i = @i
      case v
      when :in
        @i += S
        if @t[@i + 1] == :around # D14: "in about 5 hours"
          @approx = true
          @i += S
        end
        if (q = duration_quantity)
          return q if Failure === q
          return shifts(1, q, more_units(q), nil)
        end
        @i += S if @t[@i + 1] == :the
        return failure(:incomplete) if @i >= @n
        # D42: "in 3" is a count without its unit, not 3 o'clock
        return failure(:incomplete) if @t[@i] == L::NUM && @t[@i + 2] & L::DIGITS <= 2 && @i + S >= @n
        atom(false)
      when :within
        @i += S
        if @t[@i + 1] == :around
          @approx = true
          @i += S
        end
        # "within the next 5 days" is within 5 days
        @i += 2 * S if @t[@i + 1] == :the && @t[@i + S] == L::REL && @t[@i + S + 1] == :next
        @i += S if @t[@i] == L::REL && @t[@i + 1] == :next && @t[@i + S] == L::NUM # "within next 10 months"
        q = quantity
        q && !(Failure === q) ? Rel.new(:next, q) : failure(:incomplete, i) # D31
      when :q
        return failure(:incomplete) unless @t[i + S] == L::NUM && (1..4).cover?(@t[i + S + 1])
        @i += 2 * S
        Nth.new(@t[i + S + 1], Unit.new(:quarter, nil))
      when :fy
        return failure(:incomplete) unless @t[i + S] == L::NUM
        @i += 2 * S
        y = @t[i + S + 1]
        Fiscal.new(@t[i + S + 2] & L::DIGITS == 2 ? 2000 + y : y)
      when :half
        (q = quantity) ? shift_tail(q) : clock_words(30)
      when :sametime then same_time
      when :closest then closest(1)
      when :all # D48: "all week" is this whole week
        return failure(:conflict) unless @t[i + S] == L::UNIT && @t[i + S + 2] & L::PLURAL == 0
        @i += S
        this_unit
      when :rest # D48: "rest of the week" is from now to its end, as "through this week" (D16)
        return failure(:conflict) unless @t[i + S] == L::WORD && @t[i + S + 1] == :of
        @i += 2 * S
        @i += S if @t[@i + 1] == :the
        return failure(:incomplete) if @i >= @n
        node = @t[@i] == L::UNIT ? this_unit : atom(true)
        Failure === node ? node : Open.new(:until, node)
      when :hundred, :thousand, :million then (q = quantity) ? shift_tail(q) : failure(:conflict)
      when :couple
        (q = quantity) ? shift_tail(q) : failure(@i + S < @n ? :conflict : :incomplete, @i + S)
      else failure(:conflict)
      end
    end

    # D48: "the closest monday to oct 5th", "the 3rd closest xmas to today"
    def closest(n)
      @i += S
      node = atom(true)
      return node if Failure === node
      return failure(@i < @n ? :conflict : :incomplete) unless @t[@i + 1] == :to && @t[@i] == L::WORD
      @i += S
      anchor = atom(true)
      Failure === anchor ? anchor : Closest.new(n, node, anchor)
    end

    def article_atom
      i = @i
      if @t[i + S] == L::UNIT && ((u = @t[i + S + 1]) == :quarter || u == :minute) && clock_word?(i + 2 * S) && hour?(i + 3 * S)
        return clock_words(u == :quarter ? 15 : 1)
      end
      q = quantity
      return failure(:conflict) unless q
      shift_tail(q)
    end

    def rel_atom
      w = @t[@i + 1]
      start = @i
      @i += S
      if w == :this && @t[@i] == L::REL && @t[@i + 1] != :this # D40: "this coming week"
        w = @t[@i + 1] == :next ? :coming : :past # D44: "this past sunday" is "past sunday"; D48: so is "this last"
        @i += S
      end
      k = @t[@i]
      v = @t[@i + 1]
      # D42: "this second", "last second": with nothing after it to count, "second" is the unit
      if k == L::ORD && unit_at(@i) && ![L::WDAY, L::UNIT, L::WEEKEND].include?(@t[@i + S])
        k = L::UNIT
        v = :second
      end
      return failure(:conflict) if (k == L::WDAY || k == L::PART) && @t[@i + 2] & L::PLURAL != 0
      if k == L::WDAY || k == L::UNIT || k == L::WEEKEND
        node = k == L::WDAY ? Weekday.new(v) : k == L::UNIT ? Unit.new(v, nil) : WEEKEND
        @i += S
        # "last friday of june"; "last sunday in march" when a month follows
        return of(Nth.new(-1, node)) if w == :last && (@t[@i + 1] == :of || (@t[@i + 1] == :in && @t[@i + S] == L::MONTH))
        # D48: "last tuesday this month" is the last of that month
        if w == :last && k == L::WDAY && @t[@i] == L::REL && @t[@i + S + 1] == :month && @t[@i + S] == L::UNIT
          month = atom(true)
          return Within.new(Nth.new(-1, node), month)
        end
        Rel.new(w, node)
      elsif k == L::NUM && unit_at(@i + S)
        q = quantity
        Rel.new(w, q)
      elsif k == L::MONTH && @t[@i + S] != L::NUM && @t[@i + S] != L::ORD
        @i += S
        Rel.new(w, Date.new(nil, v, nil, nil, false))
      elsif k == L::NUM && @t[@i + S] == L::SLASH && @t[@i + 3 * S] != L::SLASH && @t[@i + 2 * S] == L::NUM
        d = atom(true) # D48: "last 9/11": the latest one, as "last christmas"
        Failure === d || !(Date === d) ? failure(:conflict, start) : Rel.new(w, d)
      elsif k == L::WORD && v == :work_week
        @i += S # D48: "next working week" is Monday to Friday of next week
        Within.new(Range.new(Weekday.new(1), Weekday.new(5)), Rel.new(w, Unit.new(:week, nil)))
      elsif k == L::SEASON || k == L::HOLIDAY || k == L::PART
        @i += S
        Rel.new(w, k == L::SEASON ? Season.new(v) : k == L::HOLIDAY ? Holiday.new(v) : Part.new(v))
      elsif k == L::WORD && v == :fy && @t[@i + S] != L::NUM # D17
        @i += S
        Rel.new(w, Fiscal.new(nil))
      elsif (k == L::WORD && v == :q) || (k == L::ORD && @t[@i + S + 1] == :quarter) # D32: "next q1", "last 2nd quarter"
        q = atom(false)
        Failure === q ? q : Rel.new(w, q)
      elsif (k == L::NUM && (@t[@i + S] == L::MER || @t[@i + S] == L::NAMED)) || k == L::CLOCK || k == L::NAMED
        c = k == L::NAMED ? (@i += S) && named(v) : k == L::CLOCK ? written(v, @t[@i + 2]) : number(v, @t[@i + 2], true)
        Failure === c ? c : Rel.new(w, c) # D18: "next 3pm"
      else
        failure(@i < @n ? :conflict : :incomplete, @i < @n ? @i : start)
      end
    end

    EDGES = { eod: %i[end day], eom: %i[end month], eoy: %i[end year], bom: %i[start month], boy: %i[start year] }.freeze

    def day_named?(i)
      k = @t[i]
      k == L::DAY || k == L::WDAY || k == L::MONTH
    end

    # "early next week", "mid-october", "end of the month", "late tonight"
    def fuzzy_atom
      pos = @t[@i + 1]
      @i += S
      # "mid day", "mid-night": midday and midnight
      if pos == :mid && ((day = @t[@i + 1] == :day) || @t[@i + 1] == :night) && (@t[@i] == L::UNIT || @t[@i] == L::PART)
        @i += S
        return named(day ? 12 : 0)
      end
      # D2: "EOD", "end of day tomorrow", "EOD friday": the end of the day named next, else of today; "EOM",
      # "BOY": of this month or year
      if (edge = EDGES[pos])
        pos, unit = edge
      elsif @t[@i + 1] == :of && @t[@i + S] == L::UNIT && @t[@i + S + 1] == :day && day_named?(@i + 2 * S)
        @i += 2 * S
        unit = :day
      end
      if unit
        node = unit == :day && day_named?(@i) ? atom(true) : Rel.new(:this, Unit.new(unit, nil))
        return Failure === node ? node : Fuzzy.new(pos, node)
      end
      # "early tomorrow evening", "late friday night": the part of that day
      if (@t[@i] == L::DAY || @t[@i] == L::WDAY) && @t[@i + S] == L::PART
        day = atom(true)
        return day if Failure === day
        part = atom(true)
        return Failure === part ? part : Within.new(Fuzzy.new(pos, part), day)
      end
      @i += S if @t[@i + 1] == :of
      if @t[@i + 1] == :around && @t[@i] == L::WORD # D48: "beginning of around next week", as "around the beginning of"
        @approx = true
        @i += S
      end
      @i += S if @t[@i + 1] == :the
      @i += S if @t[@i] == L::DASH && (@t[@i + S] == L::NUM || @t[@i + S] == L::DECADE) # "mid-1990s"
      return failure(:incomplete) if @i >= @n
      node = @t[@i] == L::UNIT ? this_unit : atom(true)
      return node if Failure === node
      # D44: "end of past week" is the end of last week; a rolling week's edges are now and a week ago
      node = Rel.new(:last, node.node) if Rel === node && node.word == :past && Unit === node.node && !node.node.count
      Fuzzy.new(pos, node)
    end
  end
end
