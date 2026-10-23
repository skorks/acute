module Acute
  class Rule
    # Standard 5-field cron, both ways (R20–R26): minute hour day-of-month month day-of-week, Sunday 0
    module Cron
      DAY = 86_400
      MONTHS = Ractor.make_shareable(%w[jan feb mar apr may jun jul aug sep oct nov dec])
      WEEKDAYS = Ractor.make_shareable(%w[sun mon tue wed thu fri sat])
      # name, first value, last value, the names for them, where a name's index counts from
      FIELDS = Ractor.make_shareable([["minute", 0, 59], ["hour", 0, 23], ["day of the month", 1, 31], ["month", 1, 12, MONTHS, 1],
                                      ["day of the week", 0, 7, WEEKDAYS, 0]])
      MACROS = Ractor.make_shareable({ "@yearly" => "0 0 1 1 *", "@annually" => "0 0 1 1 *", "@monthly" => "0 0 1 * *",
                                       "@weekly" => "0 0 * * 0", "@daily" => "0 0 * * *", "@midnight" => "0 0 * * *",
                                       "@hourly" => "0 * * * *" })
      # Anchored, with every repeat bounded and nothing nested, so a match can't backtrack
      ITEM = %r{\A(?:(\*)|(\w{1,3})(?:-(\w{1,3}))?)(?:/(\d{1,3}))?\z}
      # Quartz's last (L, 5L), nearest weekday (15W, LW), nth weekday (1#2) and no value (?)
      NONSTANDARD = /[#?]|\A(?:\d{0,2}l|\d{1,2}w|lw)\z/
      # first, last, whether steps are written: weekdays are listed, so the weekend is 0,6 and not */6
      WRITE = Ractor.make_shareable([[0, 59, true], [0, 23, true], [1, 31, true], [1, 12, true], [0, 6, false]])
      FINE = { minutely: 60, hourly: 3600 }.freeze

      # A Rule, or [code, message, character range] (R25)
      def self.read(line, now, zone, dst)
        raise ArgumentError, "a cron line must be a String, got #{line.class}" unless String === line
        ctx = Context.new(now, zone, :future, nil, nil, nil, nil, true, dst) # R18: occurrences follow dst:
        return [:too_long, "longer than #{MAX_LENGTH} bytes", 0...0] if line.bytesize > MAX_LENGTH
        return [:invalid_cron, "a cron line is plain ASCII", 0...0] unless line.valid_encoding? && line.ascii_only?
        text = line.strip.downcase
        lead = line.length - line.lstrip.length
        whole = lead...(lead + text.length)
        if text.start_with?("@")
          return [:unsupported_cron, "@reboot runs at boot, not at a time", whole] if text == "@reboot"
          text = MACROS[text] or return [:invalid_cron, "#{line.strip.inspect} is not a cron macro", whole]
          lead = nil
        end
        fields = []
        text.scan(/\S+/) { fields << [Regexp.last_match[0], Regexp.last_match.begin(0)] }
        return [:invalid_cron, "a cron line has 5 fields, this has #{fields.size}", whole] unless fields.size == 5
        sets = fields.each_with_index.map do |(f, at), i|
          set = field(f, *FIELDS[i])
          return [*set, lead ? (lead + at)...(lead + at + f.length) : whole] if Symbol === set[0]
          set
        end
        sunday = sets[4].pop # R25: 7 is Sunday too
        sets[4][0] ||= sunday
        out = build(sets, fields[2][0].start_with?("*"), fields[4][0].start_with?("*"), ctx, line)
        Rule === out ? out : [*out, whole]
      end

      # The field's values as an Array of booleans indexed by value, or [code, message]
      def self.field(text, name, low, high, names = nil, base = 0)
        set = Array.new(high + 1, false)
        text.split(",", -1).each do |item|
          return [:unsupported_cron, "#{item.upcase.inspect} is not standard cron: no L, W, # or ?"] if item.match?(NONSTANDARD)
          m = ITEM.match(item) or return [:invalid_cron, "#{item.inspect} is not a #{name}"]
          step = m[4]&.to_i
          return [:invalid_cron, "a step of #{m[4]} doesn't fit the #{name}"] if step && (step < 1 || step > high - low + 1)
          if m[1]
            a = low
            b = high
          else
            a = value(m[2], low, high, names, base) or return [:invalid_cron, "#{m[2].inspect} is not a #{name} (#{low}-#{high})"]
            b = m[3] ? value(m[3], low, high, names, base) : a
            return [:invalid_cron, "#{m[3].inspect} is not a #{name} (#{low}-#{high})"] unless b
            return [:invalid_cron, "#{item.inspect} runs backwards"] if b < a
            return [:invalid_cron, "a step needs a range or *: #{item.inspect}"] if step && !m[3] # Vixie
          end
          a.step(b, step || 1) { set[_1] = true }
        end
        set
      end

      def self.value(text, low, high, names, base)
        n = if text.match?(/\A\d{1,2}\z/) then text.to_i
            elsif names && (i = names.index(text)) then i + base
            end
        n if n && n >= low && n <= high
      end

      # R25, R26: cron's fields as the shapes acute's own rules take
      def self.build(sets, dom_star, dow_star, ctx, line)
        minutes, hours, doms, months, dows = sets.map { |s| (0...s.size).select { s[_1] } }
        all_doms = doms.size == 31
        all_dows = dows.size == 7
        # R26: with neither field starting with *, cron runs on a day either one matches (Vixie)
        if !dom_star && !dow_star && !all_doms && !all_dows
          return [:unsupported_cron, "cron runs when the day of the month or the day of the week matches; a rule can't say or"]
        elsif !dom_star && !dow_star
          all_doms = all_dows = true
        elsif !all_doms && !all_dows
          return [:unsupported_cron, "a rule can't hold a day of the month on given weekdays"]
        end
        all_months = months.size == 12
        every_day = all_doms && all_dows && all_months

        if every_day && hours.size == 24 && (n = grid(minutes, 0, 59)) && n < 60
          return fine(:minutely, n, ctx, line)
        elsif every_day && minutes == [0] && (n = grid(hours, 0, 23)) && n < 24
          return fine(:hourly, n, ctx, line)
        end
        secs = hours.flat_map { |h| minutes.map { h * 3600 + _1 * 60 } } # R25: each hour with each minute (R4)
        step = grid(months, 1, 12, offset: true)
        by = all_months ? [] : months # R25: BYMONTH
        parts = if all_doms && all_dows then [:daily, 1, by, [], []]
                elsif all_doms then [:weekly, 1, by, [], dows]
                elsif step && step < 12 then [:monthly, step, [], doms, []] # R23: every n months
                else [:yearly, 1, months, doms, []]
                end
        rule = Parts.new(*parts, [], nil, secs)
        start = first(rule, rule.interval > 1 && months, ctx) or return [:invalid_cron, "the line never runs"]
        Rule.new(rule, ctx.zone.name, start, true, nil, nil, [], false, ctx.dst_policy, now: ctx.now, text: line)
      end

      # The step n when values are every nth through high, from low or (offset) from less than n past it, and n
      # divides the field evenly so the step doesn't restart short (R23); else nil
      def self.grid(values, low, high, offset: false)
        size = high - low + 1
        n = values.size > 1 ? values[1] - values[0] : size
        n if size % n == 0 && (offset ? values[0] - low < n : values[0] == low) && values == values[0].step(high, n).to_a
      end

      # R23: a step finer than a day starts on cron's grid, counted from the top of the hour
      def self.fine(freq, n, ctx, line)
        step = n * FINE[freq]
        local = ctx.local(ctx.now)
        start = (local + step - 1).div(step) * step
        Rule.new(Parts.new(freq, n, [], [], [], [], nil, []), ctx.zone.name, start, true, nil, nil, [], false,
                 ctx.dst_policy, now: ctx.now, text: line)
      end

      # R2: the first run on or after now, as local wall seconds; with a step of months, only in those months
      def self.first(rule, months, ctx)
        today = ctx.local(ctx.now).div(DAY)
        (today...(today + Resolve::Recur::SEARCH)).each do |day|
          next unless rule.on?(day) && (!months || months.include?(Calendar.civil_from_days(day) / 100 % 100))
          rule.secs.each { |s| return day * DAY + s if ctx.zone.local_to_utc(day * DAY + s, ctx) >= ctx.now }
        end
        nil
      end

      # R20: the shortest way to write a field: *, */n, a-high/n, then runs and single values
      def self.write(values, low, high, steps)
        return "*" if values.size == high - low + 1
        if steps && values.size > 1
          n = values[1] - values[0]
          if n > 1 && values[0] - low < n && values == values[0].step(high, n).to_a
            return "*/#{n}" if values[0] == low
            return "#{values[0]}-#{high}/#{n}" if values.size > 2
          end
        end
        values.slice_when { _2 != _1 + 1 }.map { |run| run.size > 2 ? "#{run[0]}-#{run[-1]}" : run.join(",") }.join(",")
      end
    end

    def self.from_cron(line, now: nil, zone: nil, dst: nil)
      out = Cron.read(line, now, zone, dst)
      Rule === out ? out : nil
    end

    def self.from_cron!(line, now: nil, zone: nil, dst: nil)
      out = Cron.read(line, now, zone, dst)
      raise ParseError.new(out[1], code: out[0], position: out[2]) unless Rule === out
      out
    end

    def cron = cron_or_reason[0]

    def cron_reason = cron_or_reason[1]

    private

    def cant(what) = [nil, "cron can't express #{what.inspect}"]

    # [line, nil] or [nil, reason]: R20–R24
    def cron_or_reason
      p = @parts
      return cant("until") if @until # R21
      return cant("#{@count} times") if @count
      return cant("starting") if @started
      return cant("except") unless @exdates.empty?
      return [nil, "cron has no length"] if @duration # R29
      return cant("the #{list(p.nths.sort_by(&:first).map { ordinal(_1[0]) })} #{DAY_NAMES[p.nths[0][1]]}") unless p.nths.empty? # R24
      return cant("the #{list(p.setpos.map { ordinal(_1) })} weekday") if p.setpos
      return cant("the last day") if p.monthdays.any?(&:negative?)
      return cant(every("second")) if p.freq == :secondly
      return [nil, "cron has no seconds"] if p.secs.any? { _1 % 60 != 0 }

      n = p.interval
      fine = Cron::FINE[p.freq]
      unit = UNITS[p.freq]
      if fine && p.secs.empty? # R23
        step = n * fine
        return cant(every(unit)) unless 3600 % step == 0 || (step % 3600 == 0 && DAY % step == 0)
        minute = step < 3600 ? (0...60).step(step / 60).to_a : [0]
        hours = step < 3600 ? (0...24).to_a : (0...24).step(step / 3600).to_a
        return [cron_line([minute, hours, (1..31).to_a, (1..12).to_a, (0..6).to_a]), nil]
      end
      return cant(every(p.days.empty? ? unit : nil).delete_suffix(" on")) if n > 1 && !(p.freq == :monthly && 12 % n == 0) # R23
      minute = p.secs.empty? ? [0] : p.secs.map { _1 / 60 % 60 }.uniq.sort # R22
      hours = p.secs.empty? ? [0] : p.secs.map { _1 / 3600 }

      day = @timed ? @start.div(DAY) : @start
      ymd = Calendar.civil_from_days(day)
      doms = (1..31).to_a
      months = (1..12).to_a
      dows = (0..6).to_a
      case p.freq
      when :weekly then dows = p.days.empty? ? [Calendar.weekday(day)] : p.days.sort
      when :monthly
        doms = p.monthdays.empty? ? [ymd % 100] : p.monthdays.sort
        months = months.select { (_1 - ymd / 100 % 100) % n == 0 }
      when :yearly
        doms = p.months.empty? ? [ymd % 100] : p.monthdays
        months = [ymd / 100 % 100] if p.months.empty?
      end
      months &= p.months unless p.months.empty?
      [cron_line([minute, hours, doms, months, dows]), nil]
    end

    def cron_line(sets) = sets.zip(Cron::WRITE).map { |v, w| Cron.write(v.uniq, *w) }.join(" ")

    private_constant :Cron
  end
end
