module Acute
  # Rules, read only by Acute.recurrence. The words that make one ("every", "daily", a plural weekday) fail a
  # one-off parse, so phrase never comes here.
  class Grammar
    # interval: units between occurrences; days: weekdays picked (0 = Sunday); nths: [n, wday] within the month
    # (R8); monthdays: days of the month, -1 the last; setpos: BYSETPOS over Monday to Friday; month (the months)
    # and date: what was said (R9); until, start, within, except and window hold one-off trees; length the Units of "for 6
    # weeks"; minutes the minute marks said and minute_span [first, last, step] of "every 15 minutes from :00 to
    # :45", hours the Clocks of "in the 9am and 11am hours" (R28); months those of "in March and June, every
    # year" (R25); anchor what the steps count from (R23), 0 for "from midnight", else the month of "from January"
    Recur = Struct.new(:interval, :unit, :days, :nths, :monthdays, :setpos, :month, :date, :clocks, :part,
                       :until, :start, :within, :except_days, :except, :count, :length, :window, :minutes, :minute_span, :hours,
                       :months, :anchor)

    # R5
    FREQUENCY = { daily: [:day, 1], hourly: [:hour, 1], weekly: [:week, 1], monthly: [:month, 1], yearly: [:year, 1],
                  quarterly: [:month, 3], semiannual: [:month, 6], biweekly: [:week, 2], bimonthly: [:month, 2] }.freeze
    TAIL = { until: true, through: true, except: true, starting: true, in: true, for: true }.freeze
    MON_FRI = [1, 2, 3, 4, 5].freeze
    SAT_SUN = [6, 0].freeze

    MARKS = { every: true, once: true, **FREQUENCY.transform_values { true } }.freeze

    def self.rule(tokens) = new(tokens).rule

    # Whether the tokens hold a word that makes a rule: "every", a frequency, or a plural day or part of day
    def self.rule?(t)
      (0...t.size).step(S).any? do |i|
        k = t[i]
        (k == L::WORD && MARKS[t[i + 1]]) ||
          ((k == L::WDAY || k == L::PART || k == L::WEEKEND || (k == L::UNIT && t[i + 1] == :business_day)) && t[i + 2] & L::PLURAL != 0)
      end
    end

    COUNTS = { "twice" => "2 times", "thrice" => "3 times" }.freeze

    # R15: whether text that failed as a rule says how often but not when: a count per period with no days or
    # times ("twice a week", "3 times a day"), or a part of the day with no clock ("every morning"). Only
    # recurrence! asks, once the phrase has failed, so "twice" is no word the lexer has to know.
    def self.vague?(text)
      t = Lexer.lex(text.gsub(/\b(twice|thrice)\b/i) { COUNTS[$1.downcase] })
      return false unless Array === t
      count = days = part = false
      (0...t.size).step(S) do |i|
        k = t[i]
        return false if k == L::CLOCK || k == L::AT || k == L::MER
        days ||= k == L::WDAY || k == L::ORD || k == L::MONTH
        part ||= k == L::PART
        next unless k == L::NUM && t[i + S] == L::WORD && t[i + S + 1] == :times
        j = i + 2 * S
        count ||= (t[j] == L::WORD && FREQUENCY[t[j + 1]]) || # "3 times daily"
                  ((t[j] == L::ART || (t[j] == L::WORD && t[j + 1] == :every)) && t[j + S] == L::UNIT)
      end
      (count && !days) || (part && rule?(t))
    end

    # A Recur, or a Failure. Only text that fails as a rule is looked at as R29's days with hours, which no word
    # that makes a rule marks
    def rule
      out = recur
      Failure === out && (days = days_with_hours) ? days : out
    end

    private

    def blank = Recur.new(nil, nil, [], [], [], nil, nil, nil, [], nil, nil, nil, nil, [], [], nil, nil, nil, [], nil, [], [], nil)

    # R29: a span of days then a span of clocks, "monday to friday from 9 to 5", "tomorrow through sunday from 9
    # to 5": every day of the span (R13's window, as "in" gives), those hours each day. A span of weekdays is
    # those weekdays (R6), as "every monday to friday" has them. Nil when the tokens are no such thing.
    def days_with_hours
      f = (S...@n).step(S).find { |j| @t[j] == L::WORD && ((w = @t[j + 1]) == :from || w == :between) }
      return unless f
      hours = Grammar.new(@t[f...@n]).phrase
      return unless Range === hours && Clock === hours.from && Clock === hours.to
      days = Grammar.new(@t[0...f]).phrase
      return unless Range === days && !(Clock === days.from) && !(Clock === days.to)
      r = blank
      r.unit = :day
      r.within = days
      r.window = hours
      if Weekday === days.from && Weekday === days.to
        @i = 0
        r.days, = rule_days(true)
        return unless @i == f
      end
      r
    end

    def recur
      r = blank
      every = false
      while @i < @n
        k = @t[@i]
        v = @t[@i + 1]
        if k == L::WORD && v == :every
          every = true
          @i += S
          k = @t[@i]
          if k == L::WORD && @t[@i + 1] == :other # R7
            r.interval = 2
            @i += S
          elsif k == L::ORD && @t[@i + 1] == 2 && !r.unit && every_second?(@i) # R5: "every second" is the unit, not the 2nd of the month
            r.unit = :second
            @i += @i + S < @n && @t[@i + S + 1] == :of ? 4 * S : S
          elsif (k == L::NUM || (k == L::ORD && @t[@i + 2 * S + 1] != :of)) && @t[@i + S] == L::UNIT &&
                @t[@i + S + 1] != :business_day # R5: "every 2 weeks", "every third day"
            r.interval = @t[@i + 1]
            @i += S
          end
        elsif k == L::WORD && (f = FREQUENCY[v])
          return failure(:conflict) if r.unit
          every = true
          r.unit, r.interval = f
          @i += S
        elsif k == L::WORD && v == :once && @t[@i + S] == L::ART && @t[@i + 2 * S] == L::UNIT # R5: "once a week"
          every = true
          @i += 2 * S
        elsif k == L::WORD && (v == :the || v == :on)
          @i += S
        elsif k == L::WORD && v == :of
          @i += S
          k = @t[@i]
          w = @t[@i + 1] if k == L::WORD
          j = @i + S
          n = if w == :every && @t[j] == L::NUM then @t[j + 1] # "the 1st of every 3 months"
              elsif w == :every && @t[j] == L::WORD && @t[j + 1] == :other then 2 # R5
              end
          j += S if n
          if (w == :every || w == :the) && @t[j] == L::UNIT && @t[j + 1] == :month
            return failure(:conflict) if n && r.interval
            every ||= w == :every
            r.interval = n if n
            @i = j + S
          elsif k != L::MONTH && !(r.minute_span && !r.unit && k == L::WORD && @t[@i + 1] == :every) # R28: "of every hour"
            return failure(:conflict)
          end
        elsif k == L::WORD && v == :except
          @i += S
          if (k = @t[@i]) == L::WDAY || k == L::WEEKEND || (k == L::UNIT && @t[@i + 1] == :business_day)
            while (k = @t[@i]) == L::WDAY || k == L::WEEKEND || (k == L::UNIT && @t[@i + 1] == :business_day)
              r.except_days.concat(k == L::WDAY ? [@t[@i + 1]] : k == L::WEEKEND ? SAT_SUN : MON_FRI)
              @i += S
              @i += S if @t[@i] == L::WORD && @t[@i + 1] == :and
            end
          else
            loop do
              x = tail_phrase(true)
              return x if Failure === x
              r.except << x
              break unless @t[@i] == L::WORD && @t[@i + 1] == :and
              @i += S
            end
          end
        elsif k == L::WORD && (v == :until || v == :through)
          return failure(:conflict) if r.until
          @i += S
          r.until = tail_phrase
          return r.until if Failure === r.until
        elsif starting?(@i)
          @i += S
          r.start = tail_phrase
          return r.start if Failure === r.start
        elsif k == L::WORD && v == :from && !r.anchor &&
              (@t[@i + S] == L::MONTH || (@t[@i + S] == L::NAMED && @t[@i + S + 1] == 0 && (@i + 2 * S >= @n || window_end?(@i + 2 * S))))
          # R23: "every 3 hours from midnight", "the 1st of every 3 months from January" count as cron does; "from
          # midnight to 6am" is R27's window
          @i += S
          if @t[@i] == L::NAMED
            r.anchor = 0
            @i += S
          else
            d = month_atom
            return failure(:conflict) if d.year || d.day
            r.anchor = d.month
          end
        elsif k == L::WORD && (v == :from || v == :between) && r.unit == :minute && @t[@i + S] == L::MINUTE
          # R28: "every 15 minutes from :00 to :45" runs in each hour; the hours, if said, come after
          return failure(:conflict) if r.minute_span || !r.minutes.empty?
          j = @i + 2 * S
          w = @t[j + 1]
          return failure(:conflict) unless @t[j + S] == L::MINUTE &&
                                           (v == :between ? w == :and : @t[j] == L::DASH || w == :to || w == :through)
          r.minute_span = [@t[@i + S + 1], @t[j + S + 1], r.interval || 1]
          r.unit = r.interval = nil
          @i = j + 2 * S
        elsif k == L::WORD && (v == :from || v == :between) && !r.window # R27, R29: "every 15 minutes from 9 to 5"
          stop = @i + S
          stop += S while stop < @n && !window_end?(stop)
          r.window = Grammar.new(@t[@i...stop]).phrase
          return r.window if Failure === r.window
          @i = stop
        elsif k == L::WORD && v == :in && (r.minute_span || !r.minutes.empty?) && @t[@i + S + 1] == :the && @t[@i + S] == L::WORD
          @i += 2 * S # R28: "at :05 in the 9am and 11am hours"
          loop do
            at = @i
            c = atom(true)
            return c if Failure === c
            return failure(:conflict, at) unless Clock === c
            r.hours << c
            next if clock_at?(@i) # "the 9am, 11am and 3pm hours": a comma lexes as a space
            break unless @t[@i] == L::WORD && @t[@i + 1] == :and && clock_at?(@i + S)
            @i += S
          end
          return failure(:conflict) unless @t[@i] == L::UNIT && @t[@i + 1] == :hour
          @i += S
        elsif k == L::WORD && v == :in && (stop = yearly_months(@i + S)) # R25: "in March and June, every year"
          return failure(:conflict) unless r.months.empty?
          (@i...stop).step(S) { |j| r.months << @t[j + 1] if @t[j] == L::MONTH }
          @i = stop
        elsif (k == L::WORD && v == :in) || (k == L::REL && (v == :next || v == :this)) # R13: "in november", "next month"
          return failure(:conflict) if r.within
          @i += S if k == L::WORD
          # R13: a clock after the window is the rule's, each occurrence's: "every day in march at 9am", and so is
          # a span of clocks (R29): "every day in march from 9 to 5"
          r.within = tail_phrase(false, true)
          return r.within if Failure === r.within
        elsif k == L::WORD && v == :for
          @i += S
          if @t[@i] == L::NUM && @t[@i + S + 1] == :times # R11: "for 10 occurrences"
            r.count = @t[@i + 1]
            @i += 2 * S
          else
            stop = tail_end(@i)
            units = Grammar.new(@t[@i...stop]).duration
            return units if Failure === units
            r.length = units
            @i = stop
          end
        elsif k == L::NUM && @t[@i + S + 1] == :times && @t[@i + S] == L::WORD
          @i += 2 * S
          # R15: "3 times a day" is a count per period
          return failure(:conflict) if (k = @t[@i]) == L::ART || (k == L::WORD && @t[@i + 1] == :every)
          r.count = @t[@i - 2 * S + 1]
        elsif k == L::ORD || (k == L::REL && v == :last)
          ords = rule_ords
          k = @t[@i]
          if k == L::WDAY # R8
            days, plural = rule_days
            every ||= plural
            ords.each { |n| days.each { |w| r.nths << [n, w] } }
          elsif k == L::UNIT && @t[@i + 1] == :business_day
            r.setpos = ords
            @i += S
          else
            @i += S if k == L::UNIT && @t[@i + 1] == :day
            return failure(:conflict) if ords.any? { |n| n == 0 || n > 31 }
            r.monthdays.concat(ords)
          end
        elsif k == L::WDAY
          days, plural = rule_days(true)
          every ||= plural
          r.days.concat(days)
        elsif k == L::WEEKEND || (k == L::UNIT && v == :business_day) # R6
          every ||= @t[@i + 2] & L::PLURAL != 0
          r.days.concat(k == L::WEEKEND ? SAT_SUN : MON_FRI)
          @i += S
        elsif k == L::UNIT
          return failure(:conflict) if r.unit
          r.unit = v
          @i += S
        elsif k == L::PART
          return failure(:conflict) if r.part
          every ||= @t[@i + 2] & L::PLURAL != 0
          r.part = v
          @i += S
        elsif k == L::MONTH
          return failure(:conflict) if r.month
          d = month_atom
          return failure(:conflict) if d.year
          r.month = [d.month]
          r.date = d if d.day
          while month_next?(@i) # R9: "the 1st of January and August", "January 1 and August 1": each month, one day
            @i += S if @t[@i] == L::WORD
            e = month_atom
            return failure(:conflict) if e.year || e.day != d.day
            r.month << e.month
          end
        elsif k == L::MINUTE || (k == L::AT && @t[@i + S] == L::MINUTE) # R28: "at :05 and :10"
          return failure(:conflict) if r.minute_span || !r.minutes.empty?
          @i += S if k == L::AT
          loop do
            r.minutes << @t[@i + 1]
            @i += S
            break unless @t[@i] == L::WORD && @t[@i + 1] == :and && @t[@i + S] == L::MINUTE
            @i += S
          end
        elsif k == L::AT || clock_at?(@i) || k == L::NUM
          @i += S if k == L::AT
          loop do
            at = @i
            c = atom(true)
            return c if Failure === c
            if Date === c && !c.year && c.month && c.day && !r.month # "each 4/15"
              r.date = c
              break
            end
            return failure(:conflict, at) unless Clock === c
            r.clocks << c
            break unless @t[@i] == L::WORD && @t[@i + 1] == :and && (clock_at?(@i + S) || @t[@i + S] == L::AT)
            @i += S
            @i += S if @t[@i] == L::AT
          end
        else
          return failure(:conflict)
        end
      end
      every ? r : failure(:incomplete)
    end

    # R5: an ORD 2 after "every" that is "second" written as a word, and ends the phrase, goes on with a rule word
    # or is "of the day": "every second", "every second until 5pm". Before a day, a unit or "of the month" it is
    # an ordinal.
    def every_second?(i)
      return false unless @t[i + 2] & L::ENGLISH != 0
      j = i + S
      return true if j >= @n
      return false unless @t[j] == L::WORD
      w = @t[j + 1]
      TAIL[w] || (w == :of && (@t[j + S + 1] == :the || @t[j + S + 1] == :every) && @t[j + 2 * S] == L::UNIT &&
                  @t[j + 2 * S + 1] == :day)
    end

    # "first and third", "last", "second to last" (R8)
    def rule_ords
      out = []
      loop do
        if @t[@i] == L::ORD && @t[@i + S + 1] == :to && @t[@i + 2 * S] == L::REL && @t[@i + 2 * S + 1] == :last
          out << -@t[@i + 1]
          @i += 3 * S
        else
          out << (@t[@i] == L::REL ? -1 : @t[@i + 1])
          @i += S
        end
        break unless @t[@i] == L::WORD && @t[@i + 1] == :and && (@t[@i + S] == L::ORD || @t[@i + S + 1] == :last)
        @i += S
      end
      out
    end

    # "monday and wednesday", "mondays, wednesdays and fridays", "monday to friday", and whether one was plural
    # (R6)
    def rule_days(range = false)
      out = []
      plural = false
      loop do
        out << (d = @t[@i + 1])
        plural ||= @t[@i + 2] & L::PLURAL != 0
        @i += S
        k = @t[@i]
        # R6: "monday through friday" is each day of it, and "friday to monday" wraps as a one-off range does (D48).
        # An ordinal's day takes no range (R8): "every first monday through friday" is no set of nths
        if range && @t[@i + S] == L::WDAY && (k == L::DASH || (k == L::WORD && ((w = @t[@i + 1]) == :to || w == :through)))
          @i += S
          out << (d = (d + 1) % 7) while d != @t[@i + 1]
          plural ||= @t[@i + 2] & L::PLURAL != 0
          @i += S
        end
        break unless @t[@i] == L::WDAY || (@t[@i] == L::WORD && @t[@i + 1] == :and && @t[@i + S] == L::WDAY)
        @i += S if @t[@i] == L::WORD
      end
      [out, plural]
    end

    # Whether j goes on with a list of months, a month or "and" one: "March, June and July" (a comma lexes as a
    # space)
    def month_next?(j) = @t[j] == L::MONTH || (@t[j] == L::WORD && @t[j + 1] == :and && @t[j + S] == L::MONTH)

    # R25: where "March, June and July, every year" starting at j ends, or nil when j starts no such list
    def yearly_months(j)
      return unless @t[j] == L::MONTH
      j += S while month_next?(j)
      j + 2 * S if @t[j] == L::WORD && @t[j + 1] == :every && @t[j + S] == L::UNIT && @t[j + S + 1] == :year
    end

    # The one-off phrase up to the next rule word, or with and_stop: true also up to "and", and with clock_stop:
    # true up to "at" or a span of clocks
    def tail_phrase(and_stop = false, clock_stop = false)
      stop = tail_end(@i, and_stop)
      stop = (@i...stop).step(S).find { @t[_1] == L::AT || clock_span?(_1) } || stop if clock_stop
      return failure(:incomplete) if stop == @i
      node = Grammar.new(@t[@i...stop]).phrase
      @i = stop
      node
    end

    # R29: whether j starts "from 9 to 5" or "between 9 and 5", read as the from branch of recur reads it but up
    # to an "at", so the from branch also gets "from 9 to 5 at 9" and refuses it as it does without a window
    def clock_span?(j)
      return false unless @t[j] == L::WORD && ((w = @t[j + 1]) == :from || w == :between)
      stop = j + S
      stop += S while stop < @n && !window_end?(stop) && @t[stop] != L::AT
      span = Grammar.new(@t[j...stop]).phrase
      Range === span && Clock === span.from && Clock === span.to
    end

    # A window's clock range ends at the days it is on, its minute marks (R28), or the next rule word
    def window_end?(j)
      k = @t[j]
      w = @t[j + 1]
      (k == L::WORD && (TAIL[w] || w == :on || w == :every)) || k == L::WDAY || k == L::WEEKEND || k == L::MINUTE ||
        (k == L::AT && @t[j + S] == L::MINUTE) ||
        (k == L::UNIT && w == :business_day) || (k == L::NUM && @t[j + S + 1] == :times)
    end

    def tail_end(j, and_stop = false)
      j += S
      j += S while j < @n && !(@t[j] == L::WORD && (TAIL[w = @t[j + 1]] || (and_stop && w == :and))) &&
                   !(@t[j] == L::NUM && @t[j + S + 1] == :times)
      j > @n ? @n : j
    end
  end
end
