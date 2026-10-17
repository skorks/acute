require_relative "lexer"
require_relative "calendar"

module Acute
  # Tokens to a tree of what was said, by recursive descent. It knows nothing of now, the zone or the
  # D-rules: a bare "4" stays hour 4 with no am/pm, and "10/11" stays two numbers and a slash; resolve
  # decides what they mean.
  #
  #   phrase := (after|before|since|until|by|starting) body | around body | body
  #   body   := between item and item | from item to item | item [(to|through|until|-) item]
  #             | atom+ (between item and | from item to) item
  #   item   := atom+ [zone]        each atom is one constituent: a date, a weekday, a clock, a shift...
  #
  # "around" anywhere in an item makes the whole phrase Approx (D14).
  #
  # An item's atoms are nested by size, the coarsest outside: "friday 3pm" is Within(Clock, Weekday) and
  # "christmas 2015" is Within(Holiday, Date 2015). Two atoms of the same size conflict.
  #
  # Tokens are read straight from the flat Array: @t[i] is a kind and @t[i + 1] a value, both nil past the
  # end. A function word's Symbol is no other kind's value, so `@t[@i + 1] == :of` is the word "of".
  class Grammar
    # h24: written with a leading zero, a 24-hour form (D4); seconds: written with seconds, or :hour for an hour alone
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
    IsoWeek = Struct.new(:week, :day)            # D13: ISO week 1-53, and its day 1-7 (Monday 1) or nil
    # A decade or century from its first year; short: a decade's two digits, for the 50-year window (D12)
    Years = Struct.new(:unit, :year, :short)
    # A unit, alone ("next week") or counted ("next 3 days", "3 days" in "3 days ago")
    Unit = Struct.new(:unit, :count)
    Rel = Struct.new(:word, :node)              # next / this / last / past / coming
    Shift = Struct.new(:count, :unit, :anchor)  # signed count of units from the anchor, or from now
    Counted = Struct.new(:n, :node, :anchor)    # the nth node after the anchor or now (n < 0: before)
    Nth = Struct.new(:n, :node)                 # the nth (n = -1: the last) node inside its outer period
    Within = Struct.new(:inner, :outer)
    Range = Struct.new(:from, :to)
    Open = Struct.new(:dir, :node)              # :after, :before, :since, :until, :upto, :from, :through
    Lasting = Struct.new(:unit, :start)         # a counted Unit from the start's start: "3 days starting monday"
    Holding = Struct.new(:unit, :node)          # the calendar unit that holds the node: "the week of the 18th"
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
             Zoned => :zoned, Now => :now, Years => :years, IsoWeek => :iso_week, Counted => :counted,
             Lasting => :lasting, Holding => :holding }.freeze

    L = Lexer
    S = Lexer::STRIDE
    OPEN = { after: :after, before: :before, since: :since, until: :until, by: :until, upto: :upto, through: :until,
             onafter: :from, onbefore: :through }.freeze
    RANGE = { to: true, through: true, until: true, butbefore: true }.freeze
    BEFORE_DAY = { the: true, from: true, between: true }.freeze # words that make "ninth" a day
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
      @approx = false
    end

    attr_reader :stuck

    def phrase
      return failure(:incomplete) if @n == 0
      node = top
      return node if Failure === node
      return failure(:conflict) if @i < @n
      return failure(:incomplete) if Unit === node
      @approx ? Approx.new(node) : node
    end

    private

    def top
      w = @t[@i + 1]
      if ((dir = OPEN[w]) || starting?(@i)) && @i + S < @n
        dir ||= :from
        @i += S
        @i += S if dir == :from && @t[@i + 1] == :from # "starting from 1/1/2016"
        node = body
        return node if Failure === node
        return between(dir, node) if @but
        # "after 3 hours" is a shift, not an open end
        return Shift.new(node.count, node.unit, nil) if Unit === node && node.count && dir == :after
        return failure(:incomplete) if Unit === node
        Open.new(dir, node)
      elsif @t[@i] == L::WORD && w == :around
        @i += S
        @approx = true
        body
      else
        (w == :for && for_from) || open_after(body(w))
      end
    end

    def body(w = @t[@i + 1])
      open = @t[@i] == L::WORD && (w == :between || w == :from) # the kind first: Integer == Symbol is slow
      if open
        start = @i
        @i += S
      end
      fs = @i
      @mid = nil
      from = item(open)
      return from if Failure === from
      if open
        return @i = start && failure(:incomplete) unless separator?(@t[@i + 1] == :and)
      elsif @mid
        return failure(:incomplete) unless separator?(@mid == :between)
      else
        return from unless separator?(false)
      end
      fe = @i
      @but = @t[@i + 1] == :butbefore
      @i += S
      ts = @i
      to = day_and_year(from, ts)
      return to if to
      to = item(true)
      return to if Failure === to
      range(from, to, fs, fe, ts)
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
      signed = false
      while @i < @n
        k = @t[@i]
        v = @t[@i + 1]
        if k == L::AT
          @i += S
          at = true
          next
        elsif k == L::WORD && (v == :the || v == :on || (v == :ad && Date === last)) # D44: "1973 A.D."
          @i += S
          next
        elsif k == L::WORD && v == :around
          @approx = true # D14: "tomorrow around 10am", "3pm approximately", "11ish"
          @i += S
          next
        elsif k == L::WORD && (v == :from || v == :between) && last && !@mid
          # D44: "tomorrow from 9 to 5", "friday between 1 and 4pm": the range is within what came before
          @mid = v
          @i += S
          next
        elsif k == L::ZONE
          @i += S
          next if zone # D44: "GMT+0800 (CST)", "-0500 (CDT)": a second zone labels the first
          zone = v
          # "GMT-1", "UTC +8"; with spaces both sides it is a range ("15:00 GMT - 18:00 GMT")
          if Integer === zone && @i + S < @n && (@t[@i] == L::PLUS || @t[@i] == L::DASH) &&
             (@t[@i + 3] == @t[@i - 1] || @t[@i + S + 3] == @t[@i + 4]) && (off = offset(@i + S))
            zone += @t[@i] == L::PLUS ? off : -off
            numeric = true
            @i += 2 * S
          end
          next
        elsif (k == L::PLUS || k == L::DASH) && @i + S < @n && signed?(last)
          signed = true
          break
        elsif (k == L::PLUS || (k == L::DASH && ((machine?(last) && @t[@i + 4] == @t[@i + S + 3]) || dash_offset?(last)))) && @i + S < @n &&
              (off = offset(@i + S))
          zone = k == L::PLUS ? off : -off
          numeric = true
          @i += 2 * S
          next
        elsif k == L::DASH && Date === last && last.sep && last.day && @t[@i + S] == L::CLOCK &&
              @t[@i + 3] == @t[@i - 1] && @t[@i + 4] == @t[@i + S + 3]
          @i += S # D44: "05/31/2024-14:15": a clock joined to a numeric date by a dash is its time, as after a T
          next
        elsif k == L::DASH || (k == L::WORD && (RANGE[v] || v == :and || v == :or || v == :orlater || v == :orearlier))
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
      return signed_shifts(nil) if signed && last.nil?
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
      node = Zoned.new(node, zone, numeric) if zone
      signed ? signed_shifts(node) : node
    end

    def machine?(a)
      a = a.inner if Within === a
      Clock === a && (a.seconds || a.h24)
    end

    # D42: "15:45 -0800", "11:00 -03:00": after a clock, a dash with a space before it and none after, then
    # four digits or hh:mm, is an offset; "3:00 - 5:00" and "9-5" stay ranges
    def dash_offset?(last)
      last = last.inner if Within === last # "2010-09-12 3:12pm -0700"
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
require_relative "grammar/ranges"
require_relative "grammar/words"
require_relative "grammar/ordinals"
require_relative "grammar/clock_words"
require_relative "grammar/numbers"
require_relative "grammar/compact"
require_relative "grammar/shifts"
require_relative "grammar/duration"
