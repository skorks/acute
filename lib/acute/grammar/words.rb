module Acute
  # Atoms led by a word: weekdays, months, parts of day, next/last, early/late, ordinals, "in", "a week"
  class Grammar
    private

    def atom(loose)
      t = @t
      i = @i
      v = t[i + 1]
      case t[i]
      when L::NOW
        @i += S
        NOW
      when L::DAY
        @i += S
        DayRef.new(v)
      when L::NUM then number_atom(loose)
      when L::CLOCK then written(v, t[i + 2])
      when L::ORD then ordinal_atom
      when L::NAMED
        @i += S
        named(v)
      when L::WDAY
        @i += S
        Weekday.new(v)
      when L::MONTH then month_atom
      when L::PART
        @i += S
        Part.new(v)
      when L::SEASON
        @i += S
        Season.new(v)
      when L::HOLIDAY
        @i += S
        Holiday.new(v)
      when L::WEEKEND
        @i += S
        WEEKEND
      when L::REL then rel_atom
      when L::FUZZ then fuzzy_atom
      when L::ART then article_atom
      when L::UNIT
        return clock_words(15) if v == :quarter && kind_at(i + S) == L::REL || word_at(i + S) == :to
        failure(:incomplete)
      when L::WORD then word_atom(v)
      else failure(:conflict)
      end
    end

    def word_at(i) = i < @n && @t[i] == L::WORD ? @t[i + 1] : nil

    def word_atom(v)
      i = @i
      case v
      when :in
        @i += S
        if (q = quantity)
          return q if Failure === q
          return Shift.new(q.count, q.unit, nil)
        end
        @i += S if word == :the
        return failure(:incomplete) if @i >= @n
        # D42: "in 3" is a count without its unit, not 3 o'clock
        return failure(:incomplete) if kind_at(@i) == L::NUM && @t[@i + 2] & L::DIGITS <= 2 && @i + S >= @n
        atom(false)
      when :within
        @i += S
        q = quantity
        q && !(Failure === q) ? Rel.new(:next, q) : failure(:incomplete, i) # D31
      when :q
        return failure(:incomplete) unless kind_at(i + S) == L::NUM && (1..4).cover?(@t[i + S + 1])
        @i += 2 * S
        Nth.new(@t[i + S + 1], Unit.new(:quarter, nil))
      when :fy
        return failure(:incomplete) unless kind_at(i + S) == L::NUM
        @i += 2 * S
        y = @t[i + S + 1]
        Fiscal.new(@t[i + S + 2] & L::DIGITS == 2 ? 2000 + y : y)
      when :half
        clock_words(30)
      else failure(:conflict)
      end
    end

    # "a week", "3 days", "1/2 hour"; nil (nothing read) unless the tokens are a count and a unit
    def quantity
      i = @i
      count = nil
      if kind_at(i) == L::ART then count = 1
      elsif kind_at(i) == L::NUM
        count = @t[i + 1]
        if kind_at(i + S) == L::SLASH && kind_at(i + 2 * S) == L::NUM && @t[i + 2 * S + 1] > 0
          count = Rational(count, @t[i + 2 * S + 1])
          i += 2 * S
        end
      else return
      end
      unit = unit_at(i + S)
      return unless unit
      @i = i + 2 * S
      Unit.new(unit, count)
    end

    # "second" is the ordinal unless it follows a count
    def unit_at(i)
      k = kind_at(i)
      return @t[i + 1] if k == L::UNIT
      :second if k == L::ORD && @t[i + 1] == 2 && @t[i + 2] & L::WORDY != 0
    end

    # After a quantity: "ago", "from now", "from tomorrow", "after next tuesday", or nothing
    def shift_tail(q)
      case word
      when :ago
        @i += S
        Shift.new(-q.count, q.unit, nil)
      when :hence, :later
        @i += S
        Shift.new(q.count, q.unit, nil)
      when :from, :after, :before
        sign = word == :before ? -1 : 1
        @i += S
        anchor = item(true)
        return anchor if Failure === anchor
        Shift.new(sign * q.count, q.unit, Now === anchor ? nil : anchor)
      else q
      end
    end

    def article_atom
      i = @i
      return clock_words(15) if kind_at(i + S) == L::UNIT && @t[i + S + 1] == :quarter && clock_word?(i + 2 * S)
      q = quantity
      return failure(:conflict) unless q
      shift_tail(q)
    end

    def clock_word?(i) = (kind_at(i) == L::REL && @t[i + 1] == :past) || word_at(i) == :to

    # "twenty past four", "half past twelve", "a quarter to six"
    def clock_words(minutes)
      @i += S
      @i += S if kind_at(@i - S) == L::ART
      @i += S if kind_at(@i) == L::UNIT && @t[@i + 1] == :quarter
      return failure(:incomplete) unless clock_word?(@i)
      to = word == :to
      @i += S
      return failure(:incomplete) unless kind_at(@i) == L::NUM && @t[@i + 1].between?(1, 12)
      hour = @t[@i + 1]
      @i += S
      meridiem = nil
      if kind_at(@i) == L::MER
        meridiem = @t[@i + 1] == 0 ? :am : :pm
        @i += S
      end
      return Clock.new(hour == 1 ? 12 : hour - 1, 60 - minutes, 0, meridiem, nil, false, false) if to
      Clock.new(hour, minutes, 0, meridiem, nil, false, false)
    end

    # "3rd", "the 3rd of may", "second tuesday of march", "1st day of next month", "first of next month"
    def ordinal_atom
      n = @t[@i + 1]
      @i += S
      k = kind_at(@i)
      if k == L::WDAY || k == L::UNIT || k == L::WEEKEND
        inner = k == L::WDAY ? Weekday.new(@t[@i + 1]) : k == L::UNIT ? Unit.new(@t[@i + 1], nil) : WEEKEND
        @i += S
        return of(Nth.new(n, inner))
      elsif k == L::MONTH
        @i += S
        return Date.new(year, @t[@i - S + 1], n, nil, false)
      elsif word == :of && kind_at(@i + S) == L::MONTH
        @i += 2 * S
        return Date.new(year, @t[@i - S + 1], n, nil, false)
      end
      return failure(:invalid_date, @i - S) if n < 1 || n > 31
      # "first" alone is not a date; "the first" and "first of next month" are
      if @t[@i - S + 2] & L::WORDY != 0 && word != :of && !(@i >= 2 * S && @t[@i - 2 * S] == L::WORD && @t[@i - 2 * S + 1] == :the)
        return failure(:incomplete, @i - S)
      end
      of(Date.new(nil, nil, n, nil, false))
    end

    # "... of <period>"
    def of(node)
      return node unless word == :of
      @i += S
      @i += S if word == :the
      # D42: "the first monday of the month" repeats monthly, so it is the coming one: next month's once passed
      if kind_at(@i) == L::UNIT && @t[@i + 1] == :month && (Date === node || !(Unit === node.node && UNIT_SIZE[node.node.unit] >= 5))
        @i += S
        return node
      end
      outer = kind_at(@i) == L::UNIT ? this_unit : atom(true)
      return outer if Failure === outer
      Within.new(node, outer)
    end

    # "the month" in "the first monday of the month": the current one
    def this_unit
      @i += S
      Rel.new(:this, Unit.new(@t[@i - S + 1], nil))
    end

    def rel_atom
      w = @t[@i + 1]
      start = @i
      @i += S
      if w == :this && kind_at(@i) == L::REL && @t[@i + 1] == :next # D40: "this coming week"
        w = :coming
        @i += S
      end
      k = kind_at(@i)
      v = @t[@i + 1]
      # D42: "this second", "last second": with nothing after it to count, "second" is the unit
      if k == L::ORD && unit_at(@i) && ![L::WDAY, L::UNIT, L::WEEKEND].include?(kind_at(@i + S))
        k = L::UNIT
        v = :second
      end
      if k == L::WDAY || k == L::UNIT || k == L::WEEKEND
        node = k == L::WDAY ? Weekday.new(v) : k == L::UNIT ? Unit.new(v, nil) : WEEKEND
        @i += S
        return of(Nth.new(-1, node)) if w == :last && word == :of
        Rel.new(w, node)
      elsif k == L::NUM && unit_at(@i + S)
        q = quantity
        Rel.new(w, q)
      elsif k == L::MONTH && kind_at(@i + S) != L::NUM && kind_at(@i + S) != L::ORD
        @i += S
        Rel.new(w, Date.new(nil, v, nil, nil, false))
      elsif k == L::SEASON || k == L::HOLIDAY || k == L::PART
        @i += S
        Rel.new(w, k == L::SEASON ? Season.new(v) : k == L::HOLIDAY ? Holiday.new(v) : Part.new(v))
      elsif (k == L::NUM && (kind_at(@i + S) == L::MER || kind_at(@i + S) == L::NAMED)) || k == L::CLOCK || k == L::NAMED
        c = k == L::NAMED ? (@i += S) && named(v) : k == L::CLOCK ? written(v, @t[@i + 2]) : number(v, @t[@i + 2], true)
        Failure === c ? c : Rel.new(w, c) # D18: "next 3pm"
      else
        failure(@i < @n ? :conflict : :incomplete, @i < @n ? @i : start)
      end
    end

    # "early next week", "mid-october", "end of the month", "late tonight"
    def fuzzy_atom
      pos = @t[@i + 1]
      @i += S
      @i += S if word == :of
      @i += S if word == :the
      return failure(:incomplete) if @i >= @n
      node = kind_at(@i) == L::UNIT ? this_unit : atom(true)
      Failure === node ? node : Fuzzy.new(pos, node)
    end
  end
end
