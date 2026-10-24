require "json"
require "date"

module Acute
  # A repeating time as an iCalendar rule (RFC 5545): a DTSTART, an RRULE and any EXDATE (R1). Frozen and
  # Ractor-shareable.
  class Rule
    DAYS = Ractor.make_shareable(%w[SU MO TU WE TH FR SA])
    DAY_NAMES = Ractor.make_shareable(%w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday])
    MONTH_NAMES = Ractor.make_shareable(%w[_ January February March April May June July August September October November December])
    ORDINALS = Ractor.make_shareable(%w[_ first second third fourth fifth])
    UNITS = Ractor.make_shareable({ secondly: "second", minutely: "minute", hourly: "hour", daily: "day", weekly: "week",
                                    monthly: "month", yearly: "year" })
    DAY = 86_400
    LISTED = 8 # R4: more clocks than this read as their hours with their minutes

    # What repeats: secs are seconds of the day, sorted, each hour said with each minute said (R4)
    # @api private
    Parts = Struct.new(:freq, :interval, :months, :monthdays, :days, :nths, :setpos, :secs) do
      def on?(day)
        ymd = Calendar.civil_from_days(day)
        m = ymd / 100 % 100
        return false unless months.empty? || months.include?(m)
        d = ymd % 100
        wday = Calendar.weekday(day)
        dim = Calendar.days_in_month(ymd / 10_000, m) unless monthdays.empty? && nths.empty? && !setpos
        return false unless monthdays.empty? || monthdays.any? { |md| md > 0 ? md == d : dim + md + 1 == d }
        return false unless nths.empty? || nths.any? { |n, w| w == wday && (n > 0 ? (d - 1) / 7 + 1 == n : (dim - d) / 7 + 1 == -n) }
        return false unless days.empty? || days.include?(wday)
        return true unless setpos
        picked = (1..dim).select { |x| days.include?(Calendar.weekday(day - d + x)) }
        setpos.any? { |n| picked[n > 0 ? n - 1 : n] == d }
      end

      # R9: a day of the month none of its months has, "every feb 30", so no search need look 8 years for it
      def never?
        months.any? && monthdays.any? && months.none? { |m| monthdays.any? { _1.abs <= Calendar.days_in_month(2000, m) } }
      end
    end

    # text: the input it was read from; zone: the zone its wall times are in; duration: how long each occurrence
    # lasts, an Acute::Duration, or nil when the rule says none (R29)
    attr_reader :text, :zone, :duration

    # @api private: rules come from recurrence and from_cron.
    # start: local wall seconds when timed, else a day number; until_: a UTC epoch when timed, else a day number;
    # exdates: as start; dst: the dst: policy occurrences follow (R18); now: the epoch it was read at; length: the
    # seconds each occurrence lasts, or nil (R29)
    def initialize(parts, zone, start, timed, count, until_, exdates, started, dst = nil, now:, text:, length: nil)
      @parts = parts
      @zone = zone
      @start = start
      @timed = timed
      @count = count
      @until = until_
      @exdates = exdates
      @started = started
      @dst = dst
      @now = now
      @text = -text
      @length = length
      @duration = length && Duration.new(hours: length / 3600, minutes: length / 60 % 60, seconds: length % 60)
      Ractor.make_shareable(self)
    end

    def kind = :rule

    # The now it was read at, in its zone: where next counts from (R16)
    def now = Time.at(@now, in: Zone.for(@zone).offset_at(@now))

    def rrule
      p = @parts
      out = ["FREQ=#{p.freq.upcase}"]
      out << "INTERVAL=#{p.interval}" if p.interval > 1
      out << "BYMONTH=#{p.months.join(",")}" unless p.months.empty?
      out << "BYMONTHDAY=#{p.monthdays.join(",")}" unless p.monthdays.empty?
      byday = p.nths.map { |n, w| "#{n}#{DAYS[w]}" } + sorted_days.map { DAYS[_1] }
      out << "BYDAY=#{byday.join(",")}" unless byday.empty?
      out << "BYSETPOS=#{p.setpos.join(",")}" if p.setpos
      unless p.secs.empty?
        out << "BYHOUR=#{p.secs.map { _1 / 3600 }.uniq.join(",")}"
        out << "BYMINUTE=#{p.secs.map { _1 / 60 % 60 }.uniq.sort.join(",")}"
        out << "BYSECOND=#{p.secs[0] % 60}" if p.secs[0] % 60 != 0
      end
      out << "COUNT=#{@count}" if @count
      out << "UNTIL=#{@timed ? Time.at(@until).utc.strftime("%Y%m%dT%H%M%SZ") : ymd(@until)}" if @until
      out.join(";")
    end

    # A Time in the zone when the rule has a clock, else a Date
    def dtstart
      return ::Date.new(*civil(@start)) unless @timed
      utc = Zone.for(@zone).local_to_utc(@start, Notes.new)
      Time.at(utc, in: Zone.for(@zone).offset_at(utc))
    end

    # The EXDATEs as `first` gives occurrences: Times in the zone when the rule has a clock, else Dates
    def exdates = expander.excepted.freeze

    def to_ical
      lines = ["DTSTART#{form}:#{stamp(@start)}"]
      lines << "DURATION:#{@duration.iso8601}" if @duration # R29
      lines << "RRULE:#{rrule}"
      lines << "EXDATE#{form}:#{@exdates.map { stamp(_1) }.join(",")}" unless @exdates.empty?
      lines.join("\n")
    end

    def to_s
      p = @parts
      # R25: BYMONTH repeats each year, which "in March" alone, a window (R13), doesn't
      months = p.months.empty? || p.freq == :yearly ? "" : " in #{list(p.months.map { MONTH_NAMES[_1] })}, every year"
      said = clocks
      if said&.start_with?("every") && p.interval == 1 # the clocks' phrase stands for every day
        return "#{said}#{months}#{tail}" if p.freq == :daily
        return "#{said} on #{weekdays(plural: true)}#{months}#{tail}" if p.freq == :weekly && !p.days.empty?
      end
      out = +if !p.nths.empty?
               "the #{nths} of #{every("month")}"
             elsif p.setpos
               "the #{list(p.setpos.map { ordinal(_1) })} weekday of #{every("month")}"
             elsif p.freq == :yearly && !p.months.empty?
               names = p.months.map { MONTH_NAMES[_1] }
               days = p.monthdays.map { _1 == -1 ? "last day" : nth(_1) }
               on = names.size == 1 && p.monthdays.size == 1 && p.monthdays[0] > 0 ? "#{names[0]} #{p.monthdays[0]}" : "the #{list(days)} of #{list(names)}"
               "#{every("year")} on #{on}" # R9: "the 1st and 15th of November" reads back, "November 1 and 15" doesn't
             elsif !p.monthdays.empty?
               "the #{list(p.monthdays.map { _1 == -1 ? "last day" : nth(_1) })} of #{every("month")}#{from_month}"
             elsif !p.days.empty?
               "#{every(nil)} #{weekdays}"
             elsif FINE[p.freq] && !@started && dtstart.to_i != @now.to_i
               "#{every(UNITS[p.freq])} from midnight" # R23: cron's grid, where reading it at now would start at now
             else
               every(UNITS[p.freq])
             end
      out << months
      out << "," unless months.empty? || p.secs.empty?
      out << " #{said || at}" unless p.secs.empty?
      out << tail
    end

    def to_h
      line, reason = cron_or_reason
      { kind: "rule", text: @text, description: to_s, rrule: rrule, dtstart: @timed ? dtstart.iso8601 : dtstart.to_s,
        exdates: exdates.map { @timed ? _1.iso8601 : _1.to_s },
        zone: @zone, duration: @duration&.iso8601, ical: to_ical, cron: line, cron_reason: reason }
    end

    def to_json(*args) = to_h.to_json(*args)

    def as_json(*) = JSON.parse(to_json)

    def ==(other) = Rule === other && other.state == state

    alias eql? ==

    def hash = state.hash

    def inspect = "#<Acute::Rule #{to_ical.tr("\n", " ")}>"

    protected

    # What next, each, to_s and to_h answer from, but not the text. No dst: policy acts as :compatible (R18).
    def state = [to_ical, @zone, @dst || :compatible, @started]

    private

    Notes = Struct.new(:dst)
    FINE = { hourly: true, minutely: true, secondly: true }.freeze
    private_constant :DAY, :LISTED, :FINE, :DAYS, :DAY_NAMES, :MONTH_NAMES, :ORDINALS, :UNITS, :Notes

    # The count, start and end, as to_s ends with them
    def tail
      out = +""
      out << " #{@count} times" if @count
      out << " starting #{date(@timed ? @start.div(DAY) : @start)}" if @started
      out << " until #{@timed ? until_local : date(@until)}" if @until
      out << " except #{list(exceptions)}" unless @exdates.empty?
      out
    end

    # R4, R27: the clocks as one phrase, or nil to list them. Minutes evenly spaced through a window of the day
    # are "every 15 minutes from 9am to 6pm"; more than LISTED clocks are their hours with their minutes,
    # "every hour at :05 and :10"
    def clocks
      secs = @parts.secs
      return if secs.size < 3 || secs[0] % 60 != 0
      minutes = secs.map { _1 / 60 % 60 }.uniq.sort
      step = even(secs)
      return stepping(step, secs[0], secs[-1]) if minutes.size > 1 && step && 3600 % step == 0
      return if secs.size <= LISTED
      hours = secs.map { _1 / 3600 }.uniq
      at = if minutes.size > 2 && (m = even(minutes))
             "#{every_n(m, "minute")} from #{format(":%02d", minutes[0])} to #{format(":%02d", minutes[-1])}"
           elsif minutes != [0]
             "at #{list(minutes.map { format(":%02d", _1) })}"
           end
      if hours.size > 2 && (h = even(hours))
        span = hours[0] == 0 && hours[-1] + h == 24 ? every_n(h, "hour") : stepping(h * 3600, hours[0] * 3600, hours[-1] * 3600)
        return span unless at
        at.start_with?("at") ? "#{span} #{at}" : "#{at} of #{span}"
      elsif at && hours.size > 1
        "#{at} in the #{list(hours.map { Describe.clock(_1 * 3600) })} hours"
      end
    end

    # The clocks listed, "at 9am and 5pm", or R29's one clock with its length, "from 9am to 5pm"
    def at
      secs = @parts.secs
      return "at #{list(secs.map { Describe.clock(_1) })}" unless @length
      "from #{Describe.clock(secs[0])} to #{Describe.clock((secs[0] + @length) % DAY)}"
    end

    # "every 15 minutes from 9am to 6pm": its end the step after the last, so it reads back as R27's end left out
    def stepping(step, first, last)
      stop = last + step
      stop = stop >= DAY ? "midnight" : Describe.clock(stop)
      "#{step % 3600 == 0 ? every_n(step / 3600, "hour") : every_n(step / 60, "minute")} from #{Describe.clock(first)} to #{stop}"
    end

    # R23: " from January" for the months a step of months that divides the year falls in, as cron's */3 does
    def from_month
      n = @parts.interval
      return "" unless n > 1 && 12 % n == 0
      " from #{MONTH_NAMES[(civil(@timed ? @start.div(DAY) : @start)[1] - 1) % n + 1]}"
    end

    def every_n(n, unit) = n == 1 ? "every #{unit}" : "every #{n} #{unit}s"

    # The gap between each value and the next, when it is always the same
    def even(values)
      gap = values[1] - values[0]
      gap if values.each_cons(2).all? { _2 - _1 == gap }
    end

    def form = @timed ? ";TZID=#{@zone}" : ";VALUE=DATE"

    def stamp(t)
      return ymd(t) unless @timed
      s = t % DAY
      format("%sT%02d%02d%02d", ymd(t.div(DAY)), s / 3600, s / 60 % 60, s % 60)
    end

    def ymd(day) = format("%08d", Calendar.civil_from_days(day))

    def civil(day)
      x = Calendar.civil_from_days(day)
      [x / 10_000, x / 100 % 100, x % 100]
    end

    def date(day)
      y, m, d = civil(day)
      "#{Result::MONTHS[m - 1]} #{d}, #{y}"
    end

    # R12: the excepted dates. On an hourly or finer rule a day keeps each excepted time unless they are all
    # of that day's occurrences, so it reads back to the same EXDATEs.
    def exceptions
      return @exdates.map { date(@timed ? _1.div(DAY) : _1) }.uniq unless FINE[@parts.freq]
      @exdates.group_by { _1.div(DAY) }.flat_map do |day, walls|
        walls.sort == day_walls(day) ? date(day) : walls.map { "#{date(day)} #{Describe.clock(_1 % DAY)}" }
      end
    end

    # The wall times this rule, without its exceptions, occurs at on a local day
    def day_walls(day)
      base = Rule.new(@parts, @zone, @start, @timed, @count, @until, [], @started, @dst, now: @now, text: @text, length: @length)
      lead = Time.at(day * DAY - 15 * 3600)
      base.each(after: lead).lazy.map { _1.to_i + _1.utc_offset }.select { _1 >= day * DAY }
          .take_while { _1 < (day + 1) * DAY }.to_a.uniq
    end

    # The day an UNTIL ends, or the instant when it isn't a day's last second (R10)
    def until_local
      t = @until + Zone.for(@zone).offset_at(@until)
      t % DAY == DAY - 1 ? date(t.div(DAY)) : "#{date(t.div(DAY))} #{Describe.clock(t % DAY)}"
    end

    def sorted_days = @parts.days.sort_by { (_1 + 6) % 7 }

    def weekdays(plural: false)
      days = sorted_days
      s = plural ? "s" : ""
      return "weekday#{s}" if days == [1, 2, 3, 4, 5]
      return "weekend#{s}" if days == [6, 0]
      list(days.map { |day| "#{DAY_NAMES[day]}#{s}" })
    end

    # "every month", "every other week", "every 3 days"; unit nil for weekdays, which take the interval in weeks
    def every(unit)
      n = @parts.interval
      return "every" if unit.nil? && n == 1
      return "every #{unit}".rstrip if n == 1
      return "every other #{unit}".rstrip if n == 2
      unit ? "every #{n} #{unit}s" : "every #{n} weeks on"
    end

    # R8: "first and third Monday and Friday" when each ordinal goes with each weekday, in the BYDAY's order, as
    # the grammar reads it back; otherwise, which no phrase reads, "first Monday and last Friday"
    def nths
      ords = @parts.nths.map(&:first).uniq
      days = @parts.nths.map(&:last).uniq
      return "#{list(ords.map { ordinal(_1) })} #{list(days.map { DAY_NAMES[_1] })}" if ords.product(days) == @parts.nths
      list(@parts.nths.map { |n, w| "#{ordinal(n)} #{DAY_NAMES[w]}" })
    end

    def ordinal(n) = n == -1 ? "last" : n < 0 ? "#{ORDINALS[-n]} to last" : ORDINALS[n]

    def nth(n) = "#{n}#{n % 100 / 10 == 1 ? "th" : { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(n % 10, "th")}"

    def list(items) = items.size == 1 ? items[0] : "#{items[0..-2].join(", ")} and #{items[-1]}"
  end
end
require_relative "rule/cron"
