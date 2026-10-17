require_relative "lexer"

module Acute
  # Tokens to a tree of what was said, by recursive descent. It knows nothing of now, the zone or the
  # D-rules: a bare "4" stays hour 4 with no am/pm, and "10/11" stays two numbers and a slash; resolve
  # decides what they mean.
  #
  #   phrase := (after|before|since|until|by) body | around body | body
  #   body   := between item and item | from item to item | item [(to|through|until|-) item]
  #   item   := atom+ [zone]        each atom is one constituent: a date, a weekday, a clock, a shift...
  #
  # An item's atoms are nested by size, the coarsest outside: "friday 3pm" is Within(Clock, Weekday) and
  # "christmas 2015" is Within(Holiday, Date 2015). Two atoms of the same size conflict.
  class Grammar
    # h24: written with a leading zero, a 24-hour form (D4); seconds: written with seconds
    Clock = Struct.new(:hour, :min, :sec, :meridiem, :named, :h24, :seconds)
    DayRef = Struct.new(:offset)
    # Any of the three may be nil. With sep (:slash, :dash, :dot, :space), month and day are the first and
    # second numbers as written and resolve picks the order (D10, D37); short: a two-digit year (D23)
    Date = Struct.new(:year, :month, :day, :sep, :short)
    Weekday = Struct.new(:wday)
    Part = Struct.new(:name)
    Season = Struct.new(:name)
    Holiday = Struct.new(:name)
    Weekend = Struct.new(:count)
    Fiscal = Struct.new(:year)
    # A unit, alone ("next week") or counted ("next 3 days", "3 days" in "3 days ago")
    Unit = Struct.new(:unit, :count)
    Rel = Struct.new(:word, :node)              # next / this / last / past / coming
    Shift = Struct.new(:count, :unit, :anchor)  # signed count of units from the anchor, or from now
    Nth = Struct.new(:n, :node)                 # the nth (n = -1: the last) node inside its outer period
    Within = Struct.new(:inner, :outer)
    Range = Struct.new(:from, :to)
    Open = Struct.new(:dir, :node)              # :after, :before, :since, :until
    Approx = Struct.new(:node)
    Fuzzy = Struct.new(:pos, :node)             # :early, :mid, :late, :start, :end
    Zoned = Struct.new(:node, :offset, :numeric)
    Now = Struct.new
    NOW = Now.new.freeze
    WEEKEND = Weekend.new(nil).freeze

    L = Lexer
    S = Lexer::STRIDE
    OPEN = { after: :after, before: :before, since: :since, until: :until, by: :until }.freeze
    RANGE = { to: true, through: true, until: true }.freeze
    UNIT_SIZE = { second: 0, minute: 0, hour: 0, day: 2, business_day: 2, week: 3, fortnight: 3, month: 5,
                  quarter: 6, year: 7, decade: 8, century: 9 }.freeze

    def self.parse(tokens) = new(tokens).phrase

    def initialize(tokens)
      @t = tokens
      @n = tokens.size
      @i = 0
    end

    def phrase
      return failure(:incomplete) if @n == 0
      node = top
      return node if Failure === node
      return failure(:conflict) if @i < @n
      return failure(:incomplete) if Unit === node
      node
    end

    private

    def top
      w = word
      if (dir = OPEN[w]) && @i + S < @n
        @i += S
        node = body
        return node if Failure === node
        # "after 3 hours" is a shift, not an open end
        return Shift.new(node.count, node.unit, nil) if Unit === node && node.count && dir == :after
        return failure(:incomplete) if Unit === node
        Open.new(dir, node)
      elsif w == :around
        @i += S
        node = body
        Failure === node ? node : Approx.new(node)
      else
        body
      end
    end

    def body
      w = word
      if w == :between || w == :from
        start = @i
        @i += S
        from = item(true)
        return from if Failure === from
        return @i = start && failure(:incomplete) unless separator?(word == :and)
        @i += S
        to = item(true)
        return to if Failure === to
        return range(from, to)
      end
      from = item(false)
      return from if Failure === from
      return from unless separator?(false)
      @i += S
      start = @i
      to = item(true)
      return to if Failure === to
      # "june 3-7": the end is a day of the same month
      if Date === from && from.day && !from.sep && Clock === to && @t[start] == L::NUM && @i == start + S
        to = Date.new(from.year, from.month, @t[start + 1], nil, false)
      end
      range(from, to)
    end

    # The range's trailing atoms ("between 9:30 and 11:00 on thursday") belong to both ends
    def range(from, to)
      if Within === to && Clock === from && Clock === to.inner
        return Within.new(Range.new(from, to.inner), to.outer)
      end
      Range.new(from, to)
    end

    def separator?(and_ok)
      return false if @i >= @n
      k = @t[@i]
      k == L::DASH || (k == L::WORD && (RANGE[@t[@i + 1]] || (and_ok && @t[@i + 1] == :and)))
    end

    # One constituent after another, then nested by size
    def item(loose)
      atoms = []
      starts = []
      zone = nil
      numeric = false
      at = false
      while @i < @n
        k = @t[@i]
        v = @t[@i + 1]
        if k == L::AT
          @i += S
          at = true
          next
        elsif k == L::WORD && (v == :the || v == :on)
          @i += S
          next
        elsif k == L::ZONE
          zone = v
          @i += S
          if @i + S < @n && (@t[@i] == L::PLUS || @t[@i] == L::DASH) && (off = offset(@i + S))
            zone += @t[@i] == L::PLUS ? off : -off
            numeric = true
            @i += 2 * S
          end
          next
        elsif (k == L::PLUS || (k == L::DASH && (machine?(atoms) || dash_offset?(atoms)))) && @i + S < @n &&
              (off = offset(@i + S))
          zone = k == L::PLUS ? off : -off
          numeric = true
          @i += 2 * S
          next
        elsif k == L::DASH || (k == L::WORD && (RANGE[v] || v == :and))
          break
        end
        starts << @i
        a = atom(loose || at || !atoms.empty?)
        return a if Failure === a
        atoms << a
        at = false
      end
      return failure(:incomplete) if at || atoms.empty?
      node = combine(atoms, starts)
      return node if Failure === node
      zone ? Zoned.new(node, zone, numeric) : node
    end

    def machine?(atoms)
      a = atoms.last
      a = a.inner if Within === a
      Clock === a && (a.seconds || a.h24)
    end

    # D42: "15:45 -0800", "11:00 -03:00": after a clock, a dash with a space before it and none after, then
    # four digits or hh:mm, is an offset; "3:00 - 5:00" and "9-5" stay ranges
    def dash_offset?(atoms)
      return false unless Clock === atoms.last && @i + S < @n && @t[@i + 3] > @t[@i - 1] && @t[@i + S + 3] == @t[@i + 4]
      k = @t[@i + S]
      (k == L::NUM && @t[@i + S + 2] & L::DIGITS == 4) || (k == L::CLOCK && @t[@i + S + 2] & L::DIGITS == 2)
    end

    # "+01:00", "-0400", "+1"
    def offset(i)
      k = @t[i]
      v = @t[i + 1]
      if k == L::CLOCK && v % 100 == 0 then (v / 10_000) * 3600 + (v / 100 % 100) * 60
      elsif k == L::NUM && @t[i + 2] & L::DIGITS == 4 then (v / 100) * 3600 + (v % 100) * 60
      elsif k == L::NUM && @t[i + 2] & L::DIGITS <= 2 && v <= 14 then v * 3600
      end
    end

    def combine(atoms, starts)
      return atoms[0] if atoms.size == 1
      merge_year(atoms, starts)
      return atoms[0] if atoms.size == 1
      sizes = atoms.map { size(_1) }
      # coarsest first, in the order said among equals; an insertion sort, as there are only a few
      order = []
      j = 0
      while j < sizes.size
        k = order.size
        k -= 1 while k > 0 && sizes[order[k - 1]] < sizes[j]
        order.insert(k, j)
        j += 1
      end
      node = atoms[order[0]]
      o = 1
      while o < order.size
        j = order[o]
        a = atoms[j]
        if sizes[j] == sizes[order[o - 1]] && !(Weekday === a && Date === node && node.day) &&
           !(Date === a && a.day && Weekday === node)
          return failure(:conflict, starts[j])
        end
        return failure(:conflict, starts[j]) if Unit === a || Unit === node
        # D37: a weekday with a date only picks among the date's readings
        node = Weekday === node && Date === a ? Within.new(node, a) : Within.new(a, node)
        o += 1
      end
      node
    end

    # "23 oct" + "2026", or "10/23" + "2026", is one date
    def merge_year(atoms, starts)
      y = atoms.index { |a| Date === a && a.year && a.month.nil? && a.sep.nil? }
      return unless y
      d = atoms.index { |a| Date === a && a.year.nil? && a.month }
      return unless d
      atoms[d] = Date.new(atoms[y].year, atoms[d].month, atoms[d].day, atoms[d].sep, false)
      atoms.delete_at(y)
      starts.delete_at(y)
    end

    # How coarse a constituent is, for nesting: clock 0, part 1, day 2, week 3, month 5, season 6, year 7
    def size(a)
      case a
      when Clock, Approx then 0
      when Part then 1
      when DayRef, Weekday, Holiday then 2
      when Weekend then 3
      when Date then a.day ? 2 : a.month ? 5 : 7
      when Season then 6
      when Fiscal then 7
      when Unit then UNIT_SIZE[a.unit]
      when Rel, Fuzzy then size(a.node) - (Fuzzy === a ? 1 : 0)
      when Nth then Unit === a.node ? UNIT_SIZE[a.node.unit] : size(a.node)
      when Shift then UNIT_SIZE[a.unit] >= 2 ? 2 : 0
      when Within then size(a.inner)
      when Range then size(a.from)
      else 2
      end
    end

    def word = @i < @n && @t[@i] == L::WORD ? @t[@i + 1] : nil

    def kind_at(i) = i < @n ? @t[i] : -1

    # Points at token index i, or at the end of the text when the tokens ran out
    def failure(code, i = @i)
      if i < @n
        Failure.new(code, @t[i + 3], @t[i + 4])
      else
        stop = @n == 0 ? 0 : @t[@n - 1]
        Failure.new(code, stop, stop)
      end
    end
  end
end

require_relative "grammar/words"
require_relative "grammar/numbers"
require_relative "grammar/duration"
