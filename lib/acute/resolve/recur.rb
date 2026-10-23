module Acute
  module Resolve
    # A Recur to a Rule. DTSTART walks the days from now (R2) rather than a one-off cycle: BYSETPOS, -2FR and
    # lists of days have no one-off node to walk with.
    module Recur
      DAY = 86_400
      FREQ = { second: [:secondly, 1], minute: [:minutely, 1], hour: [:hourly, 1], day: [:daily, 1], week: [:weekly, 1],
               fortnight: [:weekly, 2], month: [:monthly, 1], quarter: [:monthly, 3], year: [:yearly, 1] }.freeze
      FINE = { secondly: true, minutely: true, hourly: true }.freeze
      STEP = { secondly: 1, minutely: 60, hourly: 3600 }.freeze
      FINE_GRAIN = { second: true, minute: true, hour: true }.freeze
      SEARCH = 8 * 366 + 1 # R9: the next 29 February can be 8 years away
      EVERY_DAY = [0, 1, 2, 3, 4, 5, 6].freeze
      MAX_EXDATES = 24

      # A Rule, or a Failure's code
      # text: the input, which the Rule carries and nothing here reads
      def self.call(r, ctx, text)
        freq, mult = FREQ[r.unit] if r.unit
        return :conflict if r.unit && !freq
        interval = (r.interval || 1) * (mult || 1)
        length = nil
        return :invalid_date if interval == 0 # R15
        if r.minute_span || !r.minutes.empty?
          steps = marks(r, freq, interval, ctx)
          return steps if Symbol === steps
          if freq != :daily
            freq = nil
            interval = 1
          end
        elsif r.window && FINE[freq] # R27: the steps inside the window are the rule's clocks, on each day it runs
          return :conflict unless r.clocks.empty? && !r.part
          steps = window(r.window, interval * STEP[freq], ctx)
          return steps if Symbol === steps
          freq = nil
          interval = 1
        elsif r.window # R29: daily or coarser, a span of clocks is a clock and how long each occurrence lasts
          w = r.window
          return :conflict unless r.clocks.empty? && !r.part && G::Range === w && G::Clock === w.from && G::Clock === w.to
          span = span(r.window, ctx)
          return span if Symbol === span
          b, e = span
          return :conflict unless e > b && e - b < DAY
          steps = [b]
          length = e - b
        elsif (freq == :hourly || freq == :minutely) && r.days.any? && r.clocks.empty? && !r.part
          # R23: "every 2 hours on weekdays" is cron's */2 on those days, counted from midnight as R28's hours are
          step = interval * STEP[freq]
          return :conflict unless DAY % step == 0
          steps = (0...DAY).step(step).to_a
          freq = nil
          interval = 1
        end
        days = r.days.uniq
        days = EVERY_DAY if days.empty? && r.except_days.any? && (freq.nil? || freq == :daily)
        days -= r.except_days # R12
        return :invalid_date if days.empty? && r.days.any? || r.except_days.any? && days.empty?
        month = r.month
        monthdays = r.monthdays.uniq
        if r.date
          d = r.date.sep ? Dates.orders(r.date, ctx)[0] : r.date
          return :invalid_date unless d
          month = d.month
          monthdays = [d.day]
        end
        if month
          return :conflict if monthdays.empty?
          freq ||= :yearly # R9
          return :conflict unless freq == :yearly
        elsif r.nths.any? || r.setpos || monthdays.any?
          freq ||= :monthly # R8, R9
          return :conflict unless freq == :monthly
          return :invalid_date if r.nths.any? { |n, _| n == 0 || n.abs > 5 }
          days = MON_FRI if r.setpos
        elsif days.any?
          freq = :weekly if freq.nil? || freq == :daily # R6
          return :conflict unless freq == :weekly
        elsif r.clocks.any? || r.part || steps
          freq ||= :daily
        end
        return :conflict unless freq
        return :conflict if r.months.any? && freq == :yearly # R25: "in March, every year" is a yearly date's month
        return :conflict if r.part && r.clocks.empty? # R15: "every morning"
        return :conflict if [r.until, r.within, r.length].compact.size > 1 || (r.count && (r.until || r.within || r.length))

        secs = steps || r.clocks.map { clock(_1, r.part, ctx) }.uniq.sort
        return :conflict unless grid?(secs) # R4
        timed = !secs.empty? || FINE[freq]

        from = ctx.now
        if r.start || r.within # R13
          x = first(r.start || r.within, ctx)
          return x if Symbol === x
          from = x.begin if x.begin && (r.start || x.begin > from)
        end
        rule = Rule::Parts.new(freq, interval, month ? [month] : r.months.uniq.sort, monthdays, r.nths.any? ? [] : days, r.nths, r.setpos, secs)
        start = r.anchor ? counted(rule, r.anchor, from, ctx) : dtstart(rule, from, ctx)
        return start if Symbol === start
        return :invalid_date unless start

        last = r.until || r.within
        if last
          x = first(last, ctx)
          return x if Symbol === x
          until_ = ending(x, timed, ctx)
          return until_ if Symbol === until_
          return :no_occurrence if (timed ? ctx.local(until_) : until_) < start # R9
        elsif r.length
          until_ = length(r.length, start, timed, ctx)
        end
        bare = nil
        exdates = r.except.map do |node|
          x = first(node, ctx)
          return x if Symbol === x
          next ctx.local(x.begin) if FINE[freq] && FINE_GRAIN[x.grain] # R12: that instant, an occurrence or not
          day = ctx.local(x.begin).div(DAY)
          next day unless timed
          next secs.map { day * DAY + _1 } unless FINE[freq]
          bare ||= Rule.new(rule, ctx.zone.name, start, true, nil, nil, [], false, ctx.dst_policy, now: ctx.now, text: text)
          walls = day_walls(bare, day, ctx)
          return :conflict if walls.size > MAX_EXDATES # R12: "every 15 minutes except october 18"
          walls
        end
        Rule.new(rule, ctx.zone.name, start, timed, r.count, until_, exdates.flatten, r.start || r.within ? true : false,
                 ctx.dst_policy, now: ctx.now, text: text, length: length)
      end

      # R4: seconds of the day, as D4, D30 and D35 read the clock, first reading only
      def self.clock(c, part, ctx)
        return Clock.candidates(c, ctx, false)[0] unless part
        day = ctx.today
        Periodic.clock(c, G::Part.new(part), Named.part(part, day, ctx), ctx)[0].b - day * DAY
      end

      # R4: each hour with each minute, all at one second, as BYHOUR × BYMINUTE gives them
      def self.grid?(secs)
        rest = secs.map { _1 % 3600 }.uniq
        rest.map { _1 % 60 }.uniq.size <= 1 && secs.size == secs.map { _1 / 3600 }.uniq.size * rest.size
      end

      # R27: the seconds of the day from the window's start, a step apart, before its end; within one day
      def self.window(node, step, ctx)
        span = span(node, ctx)
        return span if Symbol === span
        b, e = span
        return :conflict if e > DAY || e <= b
        (b...e).step(step).to_a
      end

      # R27, R29: a span of clocks as wall seconds of its first day, [begin, end]; end past DAY when it runs past
      # midnight. Wall time, so a span on the day the clocks change is as long as on any other.
      def self.span(node, ctx)
        x = first(node, ctx)
        return x if Symbol === x
        return :incomplete unless x.begin && x.end
        b = ctx.local(x.begin)
        day = b.div(DAY)
        [b - day * DAY, ctx.local(x.end) - day * DAY]
      end

      # R28: each minute mark in each hour the rule runs, as seconds of the day: every hour, every n hours from
      # midnight (n dividing the day), each step of a window (R27), or the hours named, on the days a daily rule
      # runs. A span of marks keeps its last: ":10" names a minute, not the end of a window as R27's clock does
      def self.marks(r, freq, interval, ctx)
        return :conflict unless r.clocks.empty? && !r.part
        return :conflict unless r.hours.empty? ? freq.nil? || freq == :hourly : freq.nil? || freq == :daily
        minutes = r.minute_span ? (r.minute_span[0]..r.minute_span[1]).step(r.minute_span[2]).to_a : r.minutes.uniq.sort
        return :conflict if minutes.empty?
        hours = if r.hours.any? then r.hours.map { clock(_1, nil, ctx) }.uniq.sort
                elsif r.window then window(r.window, interval * 3600, ctx)
                elsif DAY % (interval * 3600) == 0 then (0...DAY).step(interval * 3600).to_a
                else :conflict
                end
        return hours if Symbol === hours
        return :conflict unless hours.all? { _1 % 3600 == 0 }
        hours.flat_map { |h| minutes.map { h + _1 * 60 } }
      end

      def self.first(node, ctx)
        readings = Resolve.call(node, ctx, failure: true)
        return readings.code if Failure === readings
        readings[0] || :invalid_date
      end

      # R2, R3, R14: the first occurrence on or after from, as local wall seconds (whole days: a day number)
      def self.dtstart(rule, from, ctx)
        local = ctx.local(from)
        first = local.div(DAY)
        day = first
        while day < first + SEARCH
          if rule.on?(day)
            return day unless rule.secs.any? || FINE[rule.freq]
            return day == first ? local : day * DAY if rule.secs.empty?
            rule.secs.each { |s| return day * DAY + s if ctx.zone.local_to_utc(day * DAY + s, ctx) >= from }
          end
          day += 1
        end
      end

      # R23: the first step on or after from counted as cron counts: "every 3 hours from midnight" on midnight's
      # grid, the step dividing the day; "the 1st of every 3 months from January" in January, April, July or
      # October, the step dividing the year
      def self.counted(rule, anchor, from, ctx)
        n = rule.interval
        if anchor == 0
          step = n * STEP[rule.freq] if rule.freq == :hourly || rule.freq == :minutely
          return :conflict unless step && DAY % step == 0 && rule.secs.empty?
          local = ctx.local(from)
          return (local + step - 1).div(step) * step
        end
        return :conflict unless rule.freq == :monthly && n > 1 && 12 % n == 0 && rule.monthdays.any?
        grid = rule.dup
        grid.months = ((anchor - 1) % n + 1).step(12, n).to_a
        dtstart(grid, from, ctx)
      end

      # R12: the wall times of an hourly or finer rule's occurrences on a local day, however many hours DST gives
      # it; past MAX_EXDATES, more than that. The rule's end is left out, as a daily rule's times are.
      def self.day_walls(rule, day, ctx)
        from = ctx.zone.local_to_utc(day * DAY, ctx) - 1
        walls = rule.next(MAX_EXDATES + 2, after: Time.at(from)).filter_map do |t|
          wall = t.to_i + t.utc_offset
          wall if wall < (day + 1) * DAY
        end
        walls.uniq
      end

      # R10, R14: through the end of x, inclusive; a clock is that instant
      def self.ending(x, timed, ctx)
        if FINE_GRAIN[x.grain]
          return timed ? x.begin : ctx.local(x.begin).div(DAY)
        end
        return :incomplete unless x.end
        day = ctx.local(x.end - 1).div(DAY)
        timed ? ctx.zone.local_to_utc((day + 1) * DAY - 1, ctx) : day
      end

      # R11: from DTSTART, its end left out; days or longer end on the whole day before
      def self.length(units, start, timed, ctx)
        t = timed ? start : start * DAY
        if units.all? { Period::SECONDS[_1.unit] }
          return ctx.zone.local_to_utc(t, ctx) + units.sum { Period::SECONDS[_1.unit] * _1.count } - 1
        end
        units.each do |u|
          n, unit = Period.whole(u.count, u.unit)
          t = Period.add(t, n, unit, ctx)
        end
        day = t.div(DAY) - 1
        timed ? ctx.zone.local_to_utc((day + 1) * DAY - 1, ctx) : day
      end

      MON_FRI = G::MON_FRI
    end
  end
end
