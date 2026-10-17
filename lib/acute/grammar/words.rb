module Acute
  # Atoms led by a word: weekdays, months, parts of day, next/last, early/late, ordinals, "in", "a week"
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
        DayRef.new(v)
      elsif k == L::WDAY
        return failure(:incomplete) if t[i + 2] & L::PLURAL != 0
        @i += S
        of(Weekday.new(v))
      elsif k == L::MONTH then month_atom
      elsif k == L::REL then rel_atom
      elsif k == L::NAMED
        @i += S
        named(v)
      elsif k == L::ORD then ordinal_atom
      elsif k == L::PART
        @i += S
        of(Part.new(v))
      elsif k == L::NOW
        @i += S
        NOW
      elsif k == L::HOLIDAY
        return failure(:incomplete) if t[i + 2] & L::PLURAL != 0
        @i += S
        of(Holiday.new(v))
      elsif k == L::WORD then word_atom(v)
      elsif k == L::ART then article_atom
      elsif k == L::FUZZ then fuzzy_atom
      elsif k == L::WEEKEND
        @i += S
        WEEKEND
      elsif k == L::SEASON
        @i += S
        Season.new(v)
      elsif k == L::UNIT
        return clock_words(15) if v == :quarter && @t[i + S] == L::REL || @t[i + S + 1] == :to
        return iso_week if v == :week && week_number?(i + S)
        if (w = t[i + S + 1]) == :after || w == :before # "the day after tomorrow"
          @i += S
          # "the week after next": the one after next week, when "next" has nothing of its own
          if w == :after && t[i + 2 * S + 1] == :next && t[i + 2 * S] == L::REL &&
             (!(k = t[i + 3 * S]) || k == L::CLOCK || k == L::NUM || k == L::AT)
            @i += 2 * S
            return Shift.new(1, v, Rel.new(:next, Unit.new(v, nil)))
          end
          return shift_tail(Unit.new(v, 1))
        end
        failure(:incomplete)
      elsif k == L::DECADE then decade_atom
      else failure(:conflict)
      end
    end

    # "the 90s", "1990s"; "30s ago" is seconds
    def decade_atom
      return shift_tail(quantity) if @t[@i + 2] == 2 && SHIFT_TAIL[@t[@i + S + 1]]
      v = @t[@i + 1]
      @i += S
      Years.new(:decade, v, v < 100)
    end

    def word_atom(v)
      i = @i
      case v
      when :in
        @i += S
        if (q = quantity)
          return q if Failure === q
          return shifts(1, q, more_units, nil)
        end
        @i += S if @t[@i + 1] == :the
        return failure(:incomplete) if @i >= @n
        # D42: "in 3" is a count without its unit, not 3 o'clock
        return failure(:incomplete) if @t[@i] == L::NUM && @t[@i + 2] & L::DIGITS <= 2 && @i + S >= @n
        atom(false)
      when :within
        @i += S
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
      else failure(:conflict)
      end
    end

    def article_atom
      i = @i
      return clock_words(15) if @t[i + S] == L::UNIT && @t[i + S + 1] == :quarter && clock_word?(i + 2 * S)
      q = quantity
      return failure(:conflict) unless q
      shift_tail(q)
    end

    def clock_word?(i) = (@t[i] == L::REL && @t[i + 1] == :past) || @t[i + 1] == :to

    # "twenty past four", "half past twelve", "a quarter to six"
    def clock_words(minutes)
      @i += S
      @i += S if @t[@i - S] == L::ART
      @i += S if @t[@i] == L::UNIT && @t[@i + 1] == :quarter
      return failure(:incomplete) unless clock_word?(@i)
      to = @t[@i + 1] == :to
      @i += S
      return failure(:incomplete) unless @t[@i] == L::NUM && @t[@i + 1].between?(1, 12)
      hour = @t[@i + 1]
      @i += S
      meridiem = nil
      if @t[@i] == L::MER
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
      k = @t[@i]
      # D12: "the 15th century", "the 3rd century A.D."
      if k == L::UNIT && @t[@i + 1] == :century && @t[@i + S + 1] != :of && n >= 1
        @i += S
        @i += S if @t[@i + 1] == :ad
        return Years.new(:century, (n - 1) * 100, false)
      end
      return counted(n) if counted?(@i)
      if k == L::WDAY || k == L::UNIT || k == L::WEEKEND
        inner = k == L::WDAY ? Weekday.new(@t[@i + 1]) : k == L::UNIT ? Unit.new(@t[@i + 1], nil) : WEEKEND
        @i += S
        return of(Nth.new(n, inner))
      elsif k == L::MONTH
        @i += S
        return dated(@t[@i - S + 1], n)
      elsif @t[@i + 1] == :of && @t[@i + S] == L::MONTH
        @i += 2 * S
        return dated(@t[@i - S + 1], n)
      end
      return failure(:invalid_date, @i - S) if n < 1 || n > 31
      # "first" alone is not a date; "the first" and "first of next month" are
      if @t[@i - S + 2] & L::WORDY != 0 && @t[@i + 1] != :of && !(@i >= 2 * S && @t[@i - 2 * S] == L::WORD && @t[@i - 2 * S + 1] == :the)
        return failure(:incomplete, @i - S)
      end
      of(Date.new(nil, nil, n, nil, false))
    end

    # "... of <period>": "second tuesday of march", "tuesday of next week", "morning of xmas", "labor day of 2012"
    def of(node)
      return node unless @t[@i + 1] == :of
      @i += S
      @i += S if @t[@i + 1] == :the
      # D42: "the first monday of the month" repeats monthly, so it is the coming one: next month's once passed
      if @t[@i] == L::UNIT && @t[@i + 1] == :month && (Date === node || (Nth === node && !(Unit === node.node && UNIT_SIZE[node.node.unit] >= 5)))
        @i += S
        return node
      end
      outer = @t[@i] == L::UNIT ? this_unit : atom(true)
      return outer if Failure === outer
      Within.new(node, outer)
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

    # "the month" in "the first monday of the month": the current one
    def this_unit
      @i += S
      Rel.new(:this, Unit.new(@t[@i - S + 1], nil))
    end

    def rel_atom
      w = @t[@i + 1]
      start = @i
      @i += S
      if w == :this && @t[@i] == L::REL && (@t[@i + 1] == :next || @t[@i + 1] == :past) # D40: "this coming week"
        w = @t[@i + 1] == :next ? :coming : :past # D44: "this past sunday" is "past sunday"
        @i += S
      end
      k = @t[@i]
      v = @t[@i + 1]
      # D42: "this second", "last second": with nothing after it to count, "second" is the unit
      if k == L::ORD && unit_at(@i) && ![L::WDAY, L::UNIT, L::WEEKEND].include?(@t[@i + S])
        k = L::UNIT
        v = :second
      end
      return failure(:conflict) if k == L::WDAY && @t[@i + 2] & L::PLURAL != 0
      if k == L::WDAY || k == L::UNIT || k == L::WEEKEND
        node = k == L::WDAY ? Weekday.new(v) : k == L::UNIT ? Unit.new(v, nil) : WEEKEND
        @i += S
        # "last friday of june"; "last sunday in march" when a month follows
        return of(Nth.new(-1, node)) if w == :last && (@t[@i + 1] == :of || (@t[@i + 1] == :in && @t[@i + S] == L::MONTH))
        Rel.new(w, node)
      elsif k == L::NUM && unit_at(@i + S)
        q = quantity
        Rel.new(w, q)
      elsif k == L::MONTH && @t[@i + S] != L::NUM && @t[@i + S] != L::ORD
        @i += S
        Rel.new(w, Date.new(nil, v, nil, nil, false))
      elsif k == L::SEASON || k == L::HOLIDAY || k == L::PART
        @i += S
        Rel.new(w, k == L::SEASON ? Season.new(v) : k == L::HOLIDAY ? Holiday.new(v) : Part.new(v))
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

    # "early next week", "mid-october", "end of the month", "late tonight"
    def fuzzy_atom
      pos = @t[@i + 1]
      @i += S
      # "mid day", "mid-night": midday and midnight
      if pos == :mid && ((day = @t[@i + 1] == :day) || @t[@i + 1] == :night) && (@t[@i] == L::UNIT || @t[@i] == L::PART)
        @i += S
        return named(day ? 12 : 0)
      end
      @i += S if @t[@i + 1] == :of
      @i += S if @t[@i + 1] == :the
      @i += S if @t[@i] == L::DASH && (@t[@i + S] == L::NUM || @t[@i + S] == L::DECADE) # "mid-1990s"
      return failure(:incomplete) if @i >= @n
      node = @t[@i] == L::UNIT ? this_unit : atom(true)
      Failure === node ? node : Fuzzy.new(pos, node)
    end
  end
end
