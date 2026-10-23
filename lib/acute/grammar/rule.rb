module Acute
  # Rules, read only by Acute.recurrence. The words that make one ("every", "daily", a plural weekday) fail a
  # one-off parse, so phrase never comes here.
  class Grammar
    # interval: units between occurrences; days: weekdays picked (0 = Sunday); nths: [n, wday] within the month
    # (R8); monthdays: days of the month, -1 the last; setpos: BYSETPOS over Monday to Friday; month and date:
    # what was said (R9); until, start, within, except and window hold one-off trees; length the Units of "for 6
    # weeks"
    Recur = Struct.new(:interval, :unit, :days, :nths, :monthdays, :setpos, :month, :date, :clocks, :part,
                       :until, :start, :within, :except_days, :except, :count, :length, :window)

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

    def rule
      r = Recur.new(nil, nil, [], [], [], nil, nil, nil, [], nil, nil, nil, nil, [], [], nil, nil, nil)
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
          if k == L::WORD && ((w = @t[@i + 1]) == :every || w == :the) && @t[@i + S] == L::UNIT && @t[@i + S + 1] == :month
            every ||= w == :every
            @i += 2 * S
          elsif k != L::MONTH
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
        elsif k == L::WORD && (v == :from || v == :between) && r.unit && !r.window # R27: "every 15 minutes from 9 to 5"
          stop = @i + S
          stop += S while stop < @n && !window_end?(stop)
          r.window = Grammar.new(@t[@i...stop]).phrase
          return r.window if Failure === r.window
          @i = stop
        elsif k == L::WORD && v == :in
          @i += S
          r.within = tail_phrase
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
          d = month_atom
          return failure(:conflict) if d.year || r.month
          r.month = d.month
          r.date = d if d.day
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

    private

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

    # The one-off phrase up to the next rule word, or with and_stop: true also up to "and"
    def tail_phrase(and_stop = false)
      stop = tail_end(@i, and_stop)
      return failure(:incomplete) if stop == @i
      node = Grammar.new(@t[@i...stop]).phrase
      @i = stop
      node
    end

    # A window's clock range ends at the days it is on, or at the next rule word
    def window_end?(j)
      k = @t[j]
      w = @t[j + 1]
      (k == L::WORD && (TAIL[w] || w == :on || w == :every)) || k == L::WDAY || k == L::WEEKEND ||
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
