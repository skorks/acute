module Acute
  # Counts of units moved from now or from an anchor: "3 days ago", "2 years 4 months ago", "+2 days"
  class Grammar
    private

    # After a quantity: "ago", "from now", "from tomorrow", "after next tuesday", or nothing. D44: more
    # quantities before the tail are each applied in the order said ("1 week and a day from now").
    def shift_tail(q)
      start = @i
      more = more_units
      w = @t[@i + 1]
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
      else q
      end
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
  end
end
