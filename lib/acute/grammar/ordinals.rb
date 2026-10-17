module Acute
  # Atoms led by an ordinal, and what an atom is "of"
  class Grammar
    private

    # "3rd", "the 3rd of may", "second tuesday of march", "1st day of next month", "first of next month"
    def range_word?(j) = @t[j] == L::DASH || (@t[j] == L::WORD && RANGE[@t[j + 1]])

    def day_before?(j) = (@t[j] == L::ORD || @t[j] == L::NUM) && j >= S && @t[j - S] == L::MONTH

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
      # D44: "the first half of 2027" is its January to June; "the first 9 months of 1997" its first nine
      if n <= 2 && k == L::WORD && @t[@i + 1] == :half && @t[@i + S + 1] == :of
        @i += S
        return of(half(n))
      end
      if n == 1 && k == L::NUM && @t[@i + S] == L::UNIT && @t[@i + 2 * S + 1] == :of
        q = quantity
        node = of(q)
        return Within === node ? Lasting.new(q, node.outer) : failure(:incomplete)
      end
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
      # "first" alone is not a date; "the first", "first of next month", "from ninth till ...", "eighth to
      # eleventh may" and "april 9th through seventeenth" are
      if @t[@i - S + 2] & L::WORDY != 0 && @t[@i + 1] != :of && !(@i >= 2 * S && @t[@i - 2 * S] == L::WORD && BEFORE_DAY[@t[@i - 2 * S + 1]]) &&
         !(@t[@i + S] == L::ORD && range_word?(@i)) && !(@i >= 3 * S && range_word?(@i - 2 * S) && day_before?(@i - 3 * S))
        return failure(:incomplete, @i - S)
      end
      of(Date.new(nil, nil, n, nil, false))
    end

    def half(n) = Range.new(Date.new(nil, n * 6 - 5, nil, nil, false), Date.new(nil, n * 6, nil, nil, false))

    # "... of <period>": "second tuesday of march", "tuesday of next week", "morning of xmas", "labor day of 2012"
    def of(node)
      return node unless @t[@i] == L::WORD && @t[@i + 1] == :of
      @i += S
      @i += S if @t[@i] == L::WORD && @t[@i + 1] == :the
      # D42: "the first monday of the month" repeats monthly, so it is the coming one: next month's once passed
      unit = @t[@i] == L::UNIT && !(@t[@i + S] == L::WORD && @t[@i + S + 1] == :after) # not "the week after next"
      if unit && @t[@i + 1] == :month && (Date === node || (Nth === node && !(Unit === node.node && UNIT_SIZE[node.node.unit] >= 5)))
        @i += S
        return node
      end
      outer = unit ? this_unit : atom(true)
      return outer if Failure === outer
      Within.new(node, outer)
    end

    # "the month" in "the first monday of the month": the current one
    def this_unit
      @i += S
      Rel.new(:this, Unit.new(@t[@i - S + 1], nil))
    end
  end
end
