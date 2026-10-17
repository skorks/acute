module Acute
  # Counts of units: "3 days", "a week"; moved from now or an anchor: "3 days ago", "2 years 4 months ago", "+2 days"
  class Grammar
    private

    # After a quantity: "ago", "from now", "from tomorrow", "after next tuesday", or nothing. D44: more
    # quantities before the tail are each applied in the order said ("1 week and a day from now").
    def shift_tail(q)
      start = @i
      more = more_units
      w = @t[@i + 1]
      w = :after if w == :past && @t[@i] == L::REL # "three hours past noon"
      if more && !SHIFT_TAIL[w]
        @i = start
        more = nil
      end
      case w
      when :ago
        @i += S
        shifts(-1, q, more, nil)
      when :hence, :later
        @i += S
        shifts(1, q, more, nil)
      when :from, :after, :before
        @i += S
        anchor = item(true)
        return anchor if Failure === anchor
        shifts(w == :before ? -1 : 1, q, more, Now === anchor ? nil : anchor)
      else
        return q unless !more && starting?(@i)
        @i += S
        @i += S if @t[@i + 1] == :from
        start = item(true)
        Failure === start ? start : Lasting.new(q, start)
      end
    end

    # D44: "starting", "commencing", or "beginning" with no "of" after it: from the start of what follows. Not
    # "start from october", a verb before its own "from".
    def starting?(i)
      return true if @t[i] == L::WORD && @t[i + 1] == :starting
      @t[i] == L::FUZZ && @t[i + 1] == :start && (w = @t[i + S + 1]) != :of && w != :from
    end

    # D44: "3 fridays from now", "2nd monday before may 25", "two weekends ago": i is the day after the count
    def counted?(i)
      k = @t[i]
      (k == L::WDAY || k == L::WEEKEND || k == L::HOLIDAY) && @t[i + S] == L::WORD && SHIFT_TAIL[@t[i + S + 1]]
    end

    # D44: "the sunday after next wed", "the monday before christmas" are the first one after or before the
    # day named; "friday after next", "March after the next", "tuesday before last" the one after next friday
    def around(node)
      return node unless @t[@i] == L::WORD && ((w = @t[@i + 1]) == :after || w == :before)
      j = @i + S
      j += S if @t[j] == L::WORD && @t[j + 1] == :the
      k = @t[j]
      if k == L::REL && (r = @t[j + 1]) == (w == :after ? :next : :last) && nothing_own?(j + S)
        @i = j + S
        return Counted.new(w == :after ? 1 : -1, node, Rel.new(r, node))
      end
      return node unless k == L::REL || k == L::WDAY || k == L::DAY || k == L::HOLIDAY || k == L::MONTH
      @i += S
      anchor = item(true)
      return anchor if Failure === anchor
      Counted.new(w == :after ? 1 : -1, node, anchor)
    end

    # "next" in "the week after next" has nothing of its own when what follows is a time or nothing
    def nothing_own?(j)
      k = @t[j]
      !k || k == L::CLOCK || k == L::NUM || k == L::AT || k == L::PART || (k == L::WORD && @t[j + 1] == :in)
    end

    def counted(n)
      k = @t[@i]
      v = @t[@i + 1]
      node = k == L::WDAY ? Weekday.new(v) : k == L::HOLIDAY ? Holiday.new(v) : WEEKEND
      w = @t[@i + S + 1]
      @i += 2 * S
      return Counted.new(-n, node, nil) if w == :ago
      return Counted.new(n, node, nil) if w == :hence || w == :later
      anchor = item(true)
      return anchor if Failure === anchor
      Counted.new(w == :before ? -n : n, node, Now === anchor ? nil : anchor)
    end

    def shifts(sign, q, more, anchor)
      node = Shift.new(sign * q.count, q.unit, anchor)
      more&.each { |u| node = Shift.new(sign * u.count, u.unit, node) }
      node
    end

    # "4 months" in "2 years 4 months ago", "a day" in "1 week and a day"; nil when none follow
    def more_units
      list = nil
      while @i < @n
        save = @i
        @i += S if @t[@i + 1] == :and
        unless (q = quantity)
          @i = save
          break
        end
        (list ||= []) << q
      end
      list
    end

    # D44: "+2 days", "-3y", "- 3 seconds", "2023-12-29 -10days": a signed count of units shifts what comes
    # before it, or now. After other atoms a minus needs a space before it and none after.
    def signed?(last)
      return false unless @t[@i + S] == L::NUM && unit_at(@i + 2 * S)
      @t[@i] == L::PLUS || last.nil? || (@t[@i + 3] > @t[@i - 1] && @t[@i + 4] == @t[@i + S + 3])
    end

    # Each sign holds for the unsigned counts after it: "+1 day 2 hours", "+1 decade -2 years"
    def signed_shifts(node)
      sign = 1
      while @i < @n
        k = @t[@i]
        if (signed = k == L::PLUS || k == L::DASH)
          sign = k == L::PLUS ? 1 : -1
          @i += S
        end
        unless (q = quantity)
          return failure(:incomplete) if signed
          break
        end
        node = Shift.new(sign * q.count, q.unit, node)
      end
      node
    end

    # "a week", "3 days", "1/2 hour"; nil (nothing read) unless the tokens are a count and a unit
    def quantity
      i = @i
      count = nil
      if @t[i] == L::ART then count = 1
      elsif @t[i] == L::NUM
        count = @t[i + 1]
        if @t[i + S] == L::SLASH && @t[i + 2 * S] == L::NUM && @t[i + 2 * S + 1] > 0
          count = Rational(count, @t[i + 2 * S + 1])
          i += 2 * S
        elsif @t[i + S] == L::DOT && @t[i + 2 * S] == L::NUM && @t[i + 3 * S] == L::UNIT # "2.5 hours"
          count += Rational(@t[i + 2 * S + 1], 10**(@t[i + 2 * S + 2] & L::DIGITS))
          i += 2 * S
        end
      elsif @t[i + 1] == :half && @t[i + S] == L::ART # "half an hour"
        count = Rational(1, 2)
        i += S
      elsif @t[i] == L::DECADE && @t[i + 2] == 2 # "30s": seconds, not the thirties
        @i = i + S
        return Unit.new(:second, @t[i + 1])
      else return
      end
      unit = unit_at(i + S)
      return unless unit
      @i = i + 2 * S
      Unit.new(unit, count)
    end

    # "second" is the ordinal unless it follows a count
    def unit_at(i)
      k = @t[i]
      return @t[i + 1] if k == L::UNIT
      :second if k == L::ORD && @t[i + 1] == 2 && @t[i + 2] & L::WORDY != 0 && @t[i + S] != L::UNIT # not "2005 second quarter"
    end
  end
end
