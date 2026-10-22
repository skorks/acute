module Acute
  module Resolve
    # A Recur to a Rule. DTSTART walks the days from now (R2) rather than a one-off cycle: BYSETPOS, -2FR and
    # lists of days have no one-off node to walk with.
    module Recur
      DAY = 86_400
      FREQ = { second: [:secondly, 1], minute: [:minutely, 1], hour: [:hourly, 1], day: [:daily, 1], week: [:weekly, 1],
               fortnight: [:weekly, 2], month: [:monthly, 1], quarter: [:monthly, 3], year: [:yearly, 1] }.freeze
      FINE = { secondly: true, minutely: true, hourly: true }.freeze
      FINE_GRAIN = { second: true, minute: true, hour: true }.freeze
      SEARCH = 8 * 366 + 1 # R9: the next 29 February can be 8 years away
      EVERY_DAY = [0, 1, 2, 3, 4, 5, 6].freeze

      # A Rule, or a Failure's code
      def self.call(r, ctx)
        freq, mult = FREQ[r.unit] if r.unit
        return :conflict if r.unit && !freq
        interval = (r.interval || 1) * (mult || 1)
        return :invalid_date if interval == 0 # R15
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
        elsif r.clocks.any? || r.part
          freq ||= :daily
        end
        return :conflict unless freq
        return :conflict if r.part && r.clocks.empty? # R15: "every morning"
        return :conflict if [r.until, r.within, r.length].compact.size > 1 || (r.count && (r.until || r.within || r.length))

        secs = r.clocks.map { clock(_1, r.part, ctx) }.uniq.sort
        return :conflict if secs.map { _1 % 3600 }.uniq.size > 1 # R4
        timed = !secs.empty? || FINE[freq]

        from = ctx.now
        if r.start || r.within # R13
          x = first(r.start || r.within, ctx)
          return x if Symbol === x
          from = x.begin if x.begin && (r.start || x.begin > from)
        end
        rule = Rule::Parts.new(freq, interval, month, monthdays, r.nths.any? ? [] : days, r.nths, r.setpos, secs)
        start = dtstart(rule, from, ctx)
        return :invalid_date unless start

        last = r.until || r.within
        if last
          x = first(last, ctx)
          return x if Symbol === x
          until_ = ending(x, timed, ctx)
          return until_ if Symbol === until_
        elsif r.length
          until_ = length(r.length, start, timed, ctx)
        end
        exdates = r.except.map do |node|
          x = first(node, ctx)
          return x if Symbol === x
          day = ctx.local(x.begin).div(DAY)
          timed ? secs.map { day * DAY + _1 } : day
        end
        Rule.new(rule, ctx.zone.name, start, timed, r.count, until_, exdates.flatten, r.start || r.within ? true : false,
                 ctx.dst_policy)
      end

      # R4: seconds of the day, as D4, D30 and D35 read the clock, first reading only
      def self.clock(c, part, ctx)
        return Clock.candidates(c, ctx, false)[0] unless part
        day = ctx.today
        Periodic.clock(c, G::Part.new(part), Named.part(part, day, ctx), ctx)[0].b - day * DAY
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
