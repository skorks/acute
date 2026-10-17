require_relative "lexer"
require_relative "calendar"

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
  #
  # Tokens are read straight from the flat Array: @t[i] is a kind and @t[i + 1] a value, both nil past the
  # end. A function word's Symbol is no other kind's value, so `@t[@i + 1] == :of` is the word "of".
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
    # A decade or century from its first year; short: a decade's two digits, for the 50-year window (D12)
    Years = Struct.new(:unit, :year, :short)
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
    # Each node's class as a Symbol, to dispatch on in one step: a case over the classes tests them in turn
    KIND = { Clock => :clock, DayRef => :day_ref, Date => :date, Weekday => :weekday, Part => :part, Season => :season,
             Holiday => :holiday, Weekend => :weekend, Fiscal => :fiscal, Unit => :unit, Rel => :rel, Shift => :shift,
             Nth => :nth, Within => :within, Range => :range, Open => :open, Approx => :approx, Fuzzy => :fuzzy,
             Zoned => :zoned, Now => :now, Years => :years }.freeze

    L = Lexer
    S = Lexer::STRIDE
    OPEN = { after: :after, before: :before, since: :since, until: :until, by: :until }.freeze
    RANGE = { to: true, through: true, until: true }.freeze
    SHIFT_TAIL = { ago: true, hence: true, later: true, from: true, after: true, before: true }.freeze
    UNIT_SIZE = { second: 0, minute: 0, hour: 0, day: 2, business_day: 2, week: 3, fortnight: 3, month: 5,
                  quarter: 6, year: 7, decade: 8, century: 9 }.freeze

    def self.parse(tokens) = new(tokens).phrase

    # The longest prefix of the tokens that is a phrase (or with duration: true, a duration), as [tree, its
    # length in Array entries], or nil. A failure says which token the parser stuck at; a longer prefix gets
    # no further, so the next try ends before it. Each try is a new Array: a lookahead past the end must
    # read nil.
    def self.longest(tokens, duration: false)
      while tokens.size > 0
        g = new(tokens)
        tree = duration ? g.duration : g.phrase
        return [tree, tokens.size] unless Failure === tree
        stop = g.stuck < tokens.size ? g.stuck : tokens.size - S
        tokens = tokens[0, stop]
      end
    end

    def initialize(tokens)
      @t = tokens
      @n = tokens.size
      @i = 0
    end

    attr_reader :stuck

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
      w = @t[@i + 1]
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
        body(w)
      end
    end

    def body(w = @t[@i + 1])
      open = w == :between || w == :from
      if open
        start = @i
        @i += S
      end
      fs = @i
      from = item(open)
      return from if Failure === from
      if open
        return @i = start && failure(:incomplete) unless separator?(@t[@i + 1] == :and)
      else
        return from unless separator?(false)
      end
      fe = @i
      @i += S
      ts = @i
      to = item(true)
      return to if Failure === to
      range(from, to, fs, fe, ts)
    end

    # The range's trailing atoms ("between 9:30 and 11:00 on thursday") belong to both ends, and so do its
    # leading ones ("monday 8-9am"). D44: a bare day takes its month from the other end ("june 3-7", "13 to
    # 15 july", "4 to 22 this month"), and a year said only at the end is the start's too.
    def range(from, to, fs, fe, ts)
      return Range.new(from, to) if Clock === from && Clock === to
      if Date === from && from.month && from.day && !from.sep && (Clock === to || (Date === to && !to.month)) &&
         (d = bare_day(ts, @i))
        to = Date.new(from.year, from.month, d, nil, from.short)
      elsif Date === to && to.month && to.day && !to.sep && (Clock === from || (Date === from && !from.month)) &&
            (d = bare_day(fs, fe))
        from = Date.new(to.year, to.month, d, nil, to.short)
      elsif Within === to && size(to.outer) == 5 && (d = bare_day(fs, fe) || (Date === from && !from.month && from.day)) &&
            (e = Date === to.inner && !to.inner.month ? to.inner.day : Clock === to.inner && bare_day(ts, ts + S))
        return Range.new(Within.new(Date.new(nil, nil, d, nil, false), to.outer),
                         Within.new(Date.new(nil, nil, e, nil, false), to.outer))
      end
      if Date === from && Date === to && from.month && to.month && !from.year && to.year && !from.sep && !to.sep
        later = from.month > to.month || (from.month == to.month && (from.day || 0) > (to.day || 0))
        from = Date.new(later ? to.year - 1 : to.year, from.month, from.day, nil, to.short)
      end
      if Within === to && Clock === from && Clock === to.inner
        return Within.new(Range.new(from, to.inner), to.outer)
      end
      return Within.new(Range.new(from.inner, to), from.outer) if Within === from && Clock === from.inner && Clock === to
      Range.new(from, to)
    end

    # The day a range end written as one number or ordinal names ("15", "the 15th"), or nil
    def bare_day(s, e)
      s += S if @t[s + 1] == :the
      return unless e == s + S && (@t[s] == L::NUM || @t[s] == L::ORD) && @t[s + 2] & (L::DIGITS | L::SHORT) <= 2
      v = @t[s + 1]
      v if v >= 1 && v <= 31
    end

    def separator?(and_ok)
      return false if @i >= @n
      k = @t[@i]
      k == L::DASH || (k == L::WORD && (RANGE[@t[@i + 1]] || (and_ok && @t[@i + 1] == :and)))
    end

    # One constituent after another, then nested by size. Most items are one or two atoms, so the lists of
    # atoms and of where each starts are made only for a third.
    def item(loose)
      last = nil
      a1 = s1 = a2 = s2 = nil
      atoms = nil
      starts = nil
      dates = 0
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
        elsif (k == L::PLUS || (k == L::DASH && ((machine?(last) && @t[@i + 4] == @t[@i + S + 3]) || dash_offset?(last)))) && @i + S < @n &&
              (off = offset(@i + S))
          zone = k == L::PLUS ? off : -off
          numeric = true
          @i += 2 * S
          next
        elsif k == L::DASH || (k == L::WORD && (RANGE[v] || v == :and))
          break
        end
        start = @i
        a = atom(loose || at || !last.nil?)
        return a if Failure === a
        if atoms
          atoms << a
          starts << start
        elsif a2
          atoms = [a1, a2, a]
          starts = [s1, s2, start]
        elsif a1
          a2 = a
          s2 = start
        else
          a1 = a
          s1 = start
        end
        last = a
        dates += 1 if Date === a
        at = false
      end
      return failure(:incomplete) if at || last.nil?
      node = last
      if a2 && !atoms && dates < 2
        node = pair(a1, s1, a2, s2)
      elsif a2
        atoms ||= [a1, a2]
        starts ||= [s1, s2]
        merge_year(atoms, starts) if dates > 1
        node = combine(atoms, starts)
      end
      return node if Failure === node
      zone ? Zoned.new(node, zone, numeric) : node
    end

    def machine?(a)
      a = a.inner if Within === a
      Clock === a && (a.seconds || a.h24)
    end

    # D42: "15:45 -0800", "11:00 -03:00": after a clock, a dash with a space before it and none after, then
    # four digits or hh:mm, is an offset; "3:00 - 5:00" and "9-5" stay ranges
    def dash_offset?(last)
      return false unless Clock === last && @i + S < @n && @t[@i + 3] > @t[@i - 1] && @t[@i + S + 3] == @t[@i + 4]
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

    # Points at token index i, or at the end of the text when the tokens ran out
    def failure(code, i = @i)
      @stuck = i > @i ? i : @i
      if i < @n
        Failure.new(code, @t[i + 3], @t[i + 4])
      else
        stop = @n == 0 ? 0 : @t[@n - 1]
        Failure.new(code, stop, stop)
      end
    end
  end
end

require_relative "grammar/nesting"
require_relative "grammar/words"
require_relative "grammar/numbers"
require_relative "grammar/duration"
